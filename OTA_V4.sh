#!/bin/bash

#============================================================================
# PROJET OTA - OpenSource Tenant Architecture
# Version : V4
# Auteur : Axel Lobry, Queval Mathis, Divin Bisina
#============================================================================

#--------------------------------STYLES---------------------------------------#
	IT="\e[3m"
	BD="\e[1m"
	RS="\e[0m"
	GREEN='\033[0;32m'
	RED='\033[0;31m'
	YELLOW='\033[1;33m'
	CYAN='\033[0;36m'
	BOLD='\033[1m'
	NC='\033[0m' # No color
#-----------------------------------------------------------------------------#

# =============================================================================
# VÉRIFICATION DES DROITS ADMIN
# =============================================================================

check_admin() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[ERREUR] Vous devez avoir les droits administrateur pour lancer ce programme.${NC}"
        echo -e "${YELLOW}[INFO] Relancez le script avec sudo ou en tant que root.${NC}"
        exit 1
    fi
}

# =============================================================================
# FONCTIONS MESSAGE STYLE
# =============================================================================

success_msg() {
    echo -e "${GREEN}[OK] $1${NC}"
}

error_msg() {
    echo -e "${RED}[ERREUR] $1${NC}"
}

info_msg() {
    echo -e "${CYAN}[INFO] $1${NC}"
}

warn_msg() {
    echo -e "${YELLOW}[ATTENTION] $1${NC}"
}

pause() {
    echo ""
    read -rp "Appuyez sur [Entrée] pour continuer..."
}

user_exists() {
    id "$1" &>/dev/null
}

db_exists() {
    mysql -e "SHOW DATABASES LIKE '$1';" 2>/dev/null | grep -q "$1"
}

# =============================================================================
# INSTALLATION DES SERVICES
# =============================================================================

install_deps() {
    apt update -qq
    apt install -y apache2 php mariadb-server wget unzip vsftpd quota 2>/dev/null
}

# =============================================================================
# BANNIÈRE & MENU PRINCIPAL
# =============================================================================

show_menu() {
    clear
    echo -e "
${RED}┌──────────────────────────────────────────────────────────────────────────────┐${NC}
${RED}│${YELLOW}	           ▒████████    ▒██████████████     ▒████  ${NC}                    ${RED}│${NC}
${RED}│${YELLOW}     	          ▒██     ▒██         ▒██          ▒██ ▒██   ${NC}                  ${RED}│${NC}
${RED}│${YELLOW}     	         ▒██       ▒██        ▒██         ▒██   ▒██    ${NC}                ${RED}│${NC}
${RED}│${YELLOW}    	         ▒██       ▒██        ▒██        ▒██     ▒██   ${NC}                ${RED}│${NC}
${RED}│${YELLOW}    	         ▒██       ▒██        ▒██        ▒██████████   ${NC}                ${RED}│${NC}
${RED}│${YELLOW}    	         ▒██       ▒██        ▒██        ▒██     ▒██   ${NC}                ${RED}│${NC}
${RED}│${YELLOW}    	         ▒██       ▒██        ▒██       ▒██       ▒██  ${NC}                ${RED}│${NC}
${RED}│${YELLOW}   	          ▒██     ▒██         ▒██       ▒██       ▒██   ${NC}               ${RED}│${NC}
${RED}│${YELLOW}     	           ▒████████          ▒██      ▒██         ▒██  ${NC}               ${RED}│${NC}
${RED}│                                                                              ${RED}│${NC}
${RED}│${NC}        1.Créer un hébergement       |  5.Liste des utilisateurs              ${RED}│${NC}
${RED}│${NC}	 2.Supprimer un hébergement   |  6.Gestion des fichiers web            ${RED}│${NC}
${RED}│${NC}	 3.Modifier un hébergement    |  7.Gestion de la Base de donnée        ${RED}│${NC}
${RED}│${NC}	 4.Afficher un hébergement    |  8.Informations sur le serveur         ${RED}│${NC}
${RED}│${NC}	                              |  0.Quitter                             ${RED}│${NC}
${RED}│                                                                              │${NC}
${RED}└──────────────────────────────────────────────────────────────────────────────┘${NC}
"
}


# =============================================================================
# GESTION DES COMPTES UTILISATEURS
# =============================================================================

create_user() {
    clear
    echo -e "${RED}┌──────────────────────────────────┐${NC}"
    echo -e "${RED}│${YELLOW}   Créer un nouvel hébergement    ${RED}│${NC}"
    echo -e "${RED}└──────────────────────────────────┘${NC}"
    echo ""

    # --- Nom d'utilisateur ---
    read -rp " ● Nom d'utilisateur : " username

    if [[ -z "$username" ]]; then
        error_msg "Le nom d'utilisateur ne peut pas être vide."
        pause; return
    fi

    if ! [[ "$username" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error_msg "Nom d'utilisateur invalide. Utilisez uniquement lettres, chiffres, _ ou -."
        pause; return
    fi

    if user_exists "$username"; then
        error_msg "L'utilisateur '$username' existe déjà."
        pause; return
    fi

    # --- Mot de passe ---
    local mdp mdp2
    mdp="rien"
    mdp2=" "
    until [ "$mdp" = "$mdp2" ] && [ -n "$mdp" ]; do
        read -s -p " ● Mot de passe : " mdp
        echo " "
        read -s -p "   Retaper le mot de passe : " mdp2
        echo
        if [ "$mdp" != "$mdp2" ]; then
            echo " "
            echo -e "${RED}${IT}${BD}   Erreur: vous avez inséré deux mots de passe différents${RS}${NC}"
            echo " "
        fi
    done
    echo " "
    echo -e "${GREEN}${IT}   Mot de passe confirmé !${RS}${NC}"
    echo " "

    # --- Quota disque ---
    read -rp " ● Quota disque (ex: 500M, 1G) : " quota
    if [[ -z "$quota" ]]; then
        quota="500M"
        warn_msg "Quota par défaut défini à 500M."
    fi

    # --- Base de données ---
    echo " ● Création BDD :"
    local create_db
    select create_db in "oui" "non"; do
        if [ "$create_db" != "oui" ] && [ "$create_db" != "non" ]; then
            echo -e "${RED}${BD}ERREUR: Choix invalide${RS}${NC}"
        else
            break
        fi
    done

    # --- Accès SSH ---
    echo " ● Accès SSH :"
    local enable_ssh
    select enable_ssh in "oui" "non"; do
        if [ "$enable_ssh" != "oui" ] && [ "$enable_ssh" != "non" ]; then
            echo -e "${RED}${BD}ERREUR: Choix invalide${RS}${NC}"
        else
            break
        fi
    done

    echo ""
    info_msg "Création de l'hébergement pour '$username'..."

    # --- Création de l'utilisateur ---
    if [[ "$enable_ssh" == "oui" ]]; then
        useradd -m -d "/home/$username" -s /bin/bash "$username"
    else
        useradd -m -d "/home/$username" -s /usr/sbin/nologin "$username"
    fi

    if [[ $? -ne 0 ]]; then
        error_msg "Impossible de créer l'utilisateur Linux."
        pause; return
    fi

    echo "$username:$mdp" | chpasswd
    success_msg "Utilisateur Linux créé."

    # --- Création des dossiers ---
    mkdir -p "/home/$username/www"
    if [[ ! -d "/home/$username/www" ]]; then
        error_msg "Impossible de créer le dossier web /home/$username/www"
        pause
        return
    fi
    chown -R "$username:$username" "/home/$username"
    chmod 755 "/home/$username"
    chmod 755 "/home/$username/www"

    cat > "/home/$username/www/index.html" <<EOF
<!DOCTYPE html>
<html>
<head><title>Bienvenue $username</title></head>
<body>
<h1>Hébergement de $username</h1>
<p>Site en cours de construction.</p>
</body>
</html>
EOF
    chown "$username:$username" "/home/$username/www/index.html"
    success_msg "Dossiers /home/$username/www créés."

    # --- Quota disque ---
    if command -v setquota &>/dev/null; then
        local quota_num quota_unit quota_blocks
        quota_num=$(echo "$quota" | grep -oP '^\d+')
        quota_unit=$(echo "$quota" | grep -oP '[A-Za-z]+$')
        case "$quota_unit" in
            M|m) quota_blocks=$((quota_num * 1024)) ;;
            G|g) quota_blocks=$((quota_num * 1024 * 1024)) ;;
            *)   quota_blocks=$((quota_num)) ;;
        esac
        setquota -u "$username" "$quota_blocks" "$quota_blocks" 0 0 /home 2>/dev/null
        success_msg "Quota disque défini à $quota."
    else
        warn_msg "setquota non disponible. Quota non appliqué (installez quota)."
    fi

    # --- Configuration FTP (vsftpd) ---
    if systemctl list-units --type=service 2>/dev/null | grep -q vsftpd; then
        echo "$username" >> /etc/vsftpd.userlist 2>/dev/null
        success_msg "Accès FTP configuré."
    else
        warn_msg "vsftpd non détecté. FTP non configuré."
    fi

    # --- Création de la base de données ---
    if [[ "$create_db" == "oui" ]]; then
        create_database "$username"
    fi

    # --- Création du VirtualHost Apache ---
    create_virtualhost "$username"

    echo ""
    success_msg "Hébergement pour '$username' créé avec succès !"
    pause
}

create_virtualhost() {
    local username="$1"
    local vhost_file="/etc/apache2/sites-available/$username.conf"

    if [[ ! -d /etc/apache2/sites-available ]]; then
        warn_msg "Apache2 non détecté. VirtualHost non créé."
        return
    fi

    cat > "$vhost_file" <<EOF
<VirtualHost *:80>
    ServerName $username.local
    DocumentRoot /home/$username/www

    <Directory /home/$username/www>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/$username-error.log
    C.ustomLog \${APACHE_LOG_DIR}/$username-access.log combined
</VirtualHost>
EOF

    a2ensite "$username.conf" &>/dev/null
    systemctl reload apache2 &>/dev/null
    success_msg "VirtualHost Apache créé : $vhost_file"
}

# =============================================================================
# SUPPRESSION D'UN HÉBERGEMENT
# =============================================================================

delete_user() {
    clear
    echo -e "${RED}┌──────────────────────────────────┐${NC}"
    echo -e "${RED}│${YELLOW}   Supprimer un hébergement       ${RED}│${NC}"
    echo -e "${RED}└──────────────────────────────────┘${NC}"
    echo ""

    show_users_list
    echo ""
    read -rp " ● Nom d'utilisateur à supprimer : " username

    if [[ -z "$username" ]]; then
        error_msg "Nom vide."
        pause; return
    fi

    if ! user_exists "$username"; then
        error_msg "L'utilisateur '$username' n'existe pas."
        pause; return
    fi

    echo ""
    warn_msg "Cette action est IRRÉVERSIBLE !"
    echo " ● Confirmer la suppression :"
    local confirm
    select confirm in "oui" "non"; do
        [ "$confirm" = "oui" ] || [ "$confirm" = "non" ] && break
    done

    if [[ "$confirm" != "oui" ]]; then
        info_msg "Suppression annulée."
        pause; return
    fi

    # Supprimer la base de données
    local db_name="${username}_db"
    if command -v mysql &>/dev/null && db_exists "$db_name"; then
        delete_database "$username"
    fi

    # Supprimer le VirtualHost Apache
    if [[ -f "/etc/apache2/sites-available/$username.conf" ]]; then
        a2dissite "$username.conf" &>/dev/null
        rm -f "/etc/apache2/sites-available/$username.conf"
        systemctl reload apache2 &>/dev/null
        success_msg "VirtualHost Apache supprimé."
    fi

    # Supprimer l'accès FTP
    if grep -q "^$username$" /etc/vsftpd.userlist 2>/dev/null; then
        sed -i "/^$username$/d" /etc/vsftpd.userlist 2>/dev/null
        systemctl restart vsftpd &>/dev/null
        success_msg "Accès FTP supprimé."
    fi

    # Supprimer l'utilisateur Linux
    userdel -r "$username" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        success_msg "Utilisateur '$username' et /home/$username supprimés."
    else
        error_msg "Problème lors de la suppression de l'utilisateur."
    fi

    if [[ -d "/home/$username" ]]; then
        rm -rf "/home/$username"
        success_msg "Répertoire /home/$username supprimé manuellement."
    fi

    echo ""
    success_msg "Hébergement de '$username' entièrement supprimé."
    pause
}

# =============================================================================
# MODIFICATION D'UN HÉBERGEMENT
# =============================================================================

modify_user() {
    clear
    echo -e "${RED}┌──────────────────────────────────┐${NC}"
    echo -e "${RED}│${YELLOW}   Modifier un hébergement        ${RED}│${NC}"
    echo -e "${RED}└──────────────────────────────────┘${NC}"
    echo ""

    show_users_list
    echo ""
    read -rp " ● Nom d'utilisateur à modifier : " username

    if [[ -z "$username" ]]; then
        error_msg "Nom vide."
        pause; return
    fi

    if ! user_exists "$username"; then
        error_msg "L'utilisateur '$username' n'existe pas."
        pause; return
    fi

    echo ""
    echo -e "${YELLOW}${BD} --- Que souhaitez-vous modifier ? ---${RS}${NC}"
    echo "  1 - Changer le mot de passe"
    echo "  2 - Changer le quota disque"
    echo "  3 - Activer/Désactiver SSH"
    echo "  4 - Créer/Supprimer une base de données"
    echo "  5 - Activer/Désactiver FTP"
    echo "  0 - Retour"
    echo ""
    read -rp ">>> " mod_choice

    if [ "$mod_choice" = "1" ]; then
        local mdp mdp2
        mdp="rien"
        mdp2=" "
        until [ "$mdp" = "$mdp2" ] && [ -n "$mdp" ]; do
            read -s -p " ● Nouveau mot de passe : " mdp
            echo " "
            read -s -p "   Confirmer : " mdp2
            echo
            if [ "$mdp" != "$mdp2" ]; then
                echo " "
                echo -e "${RED}${IT}${BD}   Erreur: vous avez inséré deux mots de passe différents${RS}${NC}"
                echo " "
            fi
        done
        echo "$username:$mdp" | chpasswd
        success_msg "Mot de passe modifié."

    elif [ "$mod_choice" = "2" ]; then
        read -rp " ● Nouveau quota (ex: 1G, 500M) : " new_quota
        if command -v setquota &>/dev/null; then
            local quota_num quota_unit quota_blocks
            quota_num=$(echo "$new_quota" | grep -oP '^\d+')
            quota_unit=$(echo "$new_quota" | grep -oP '[A-Za-z]+$')
            case "$quota_unit" in
                M|m) quota_blocks=$((quota_num * 1024)) ;;
                G|g) quota_blocks=$((quota_num * 1024 * 1024)) ;;
                *)   quota_blocks=$((quota_num)) ;;
            esac
            setquota -u "$username" "$quota_blocks" "$quota_blocks" 0 0 /home 2>/dev/null
            success_msg "Quota modifié à $new_quota."
        else
            warn_msg "setquota non disponible."
        fi

    elif [ "$mod_choice" = "3" ]; then
        local current_shell
        current_shell=$(getent passwd "$username" | cut -d: -f7)
        if [[ "$current_shell" == "/bin/bash" ]]; then
            usermod -s /usr/sbin/nologin "$username"
            success_msg "SSH désactivé pour '$username'."
        else
            usermod -s /bin/bash "$username"
            success_msg "SSH activé pour '$username'."
        fi

    elif [ "$mod_choice" = "4" ]; then
        local db_name="${username}_db"
        if db_exists "$db_name"; then
            echo " ● La base '$db_name' existe. Supprimer ?"
            local confirm_del
            select confirm_del in "oui" "non"; do
                [ "$confirm_del" = "oui" ] || [ "$confirm_del" = "non" ] && break
            done
            [[ "$confirm_del" == "oui" ]] && delete_database "$username"
        else
            echo " ● Aucune base trouvée. Créer '$db_name' ?"
            local confirm_create
            select confirm_create in "oui" "non"; do
                [ "$confirm_create" = "oui" ] || [ "$confirm_create" = "non" ] && break
            done
            [[ "$confirm_create" == "oui" ]] && create_database "$username"
        fi

    elif [ "$mod_choice" = "5" ]; then
        if grep -q "^$username$" /etc/vsftpd.userlist 2>/dev/null; then
            sed -i "/^$username$/d" /etc/vsftpd.userlist 2>/dev/null
            success_msg "FTP désactivé pour '$username'."
        else
            echo "$username" >> /etc/vsftpd.userlist 2>/dev/null
            success_msg "FTP activé pour '$username'."
        fi
        systemctl restart vsftpd &>/dev/null

    elif [ "$mod_choice" = "0" ]; then
        return

    else
        error_msg "Choix invalide."
    fi

    pause
}

# =============================================================================
# AFFICHAGE D'UN HÉBERGEMENT
# =============================================================================

show_user() {
    clear
    echo -e "${RED}┌──────────────────────────────────┐${NC}"
    echo -e "${RED}│${YELLOW}   Détails d'un hébergement       ${RED}│${NC}"
    echo -e "${RED}└──────────────────────────────────┘${NC}"
    echo ""

    show_users_list
    echo ""
    read -rp " ● Nom d'utilisateur à afficher : " username

    if [[ -z "$username" ]]; then
        error_msg "Nom vide."
        pause; return
    fi

    if ! user_exists "$username"; then
        error_msg "L'utilisateur '$username' n'existe pas."
        pause; return
    fi

    echo ""
    echo -e "${YELLOW}${BD} --- Informations : $username ---${RS}${NC}"
    echo -e "  Répertoire home    : /home/$username"
    echo -e "  Répertoire web     : /home/$username/www"

    local shell
    shell=$(getent passwd "$username" | cut -d: -f7)
    if [[ "$shell" == "/bin/bash" ]]; then
        echo -e "  Accès SSH          : ${GREEN}Activé${NC}"
    else
        echo -e "  Accès SSH          : ${RED}Désactivé${NC}"
    fi

    local used
    used=$(du -sh "/home/$username" 2>/dev/null | cut -f1)
    echo -e "  Espace utilisé     : $used"

    local file_count
    file_count=$(find "/home/$username/www" -type f 2>/dev/null | wc -l)
    echo -e "  Fichiers dans www  : $file_count fichier(s)"

    if command -v mysql &>/dev/null; then
        local db_name="${username}_db"
        if db_exists "$db_name"; then
            echo -e "  Base de données    : ${GREEN}$db_name (existe)${NC}"
        else
            echo -e "  Base de données    : ${YELLOW}Aucune${NC}"
        fi
    fi

    if grep -q "^$username$" /etc/vsftpd.userlist 2>/dev/null; then
        echo -e "  Accès FTP          : ${GREEN}Activé${NC}"
    else
        echo -e "  Accès FTP          : ${YELLOW}Non configuré${NC}"
    fi

    if [[ -f "/etc/apache2/sites-available/$username.conf" ]]; then
        echo -e "  VirtualHost Apache : ${GREEN}Configuré${NC}"
    else
        echo -e "  VirtualHost Apache : ${YELLOW}Non configuré${NC}"
    fi

    pause
}

# =============================================================================
# LISTE DES UTILISATEURS
# =============================================================================

show_users_list() {
    echo -e "${YELLOW}${BD} --- Utilisateurs hébergés ---${RS}${NC}"
    local found=0
    while IFS=: read -r name _ uid _ _ home _; do
        if [[ $uid -ge 1000 && $uid -ne 65534 && -d "$home/www" ]]; then
            echo -e "  ${CYAN}$name${NC} -> $home"
            found=1
        fi
    done < /etc/passwd
    if [[ $found -eq 0 ]]; then
        echo -e "  ${YELLOW}Aucun hébergement trouvé.${NC}"
    fi
}

list_users() {
    clear
    echo -e "${RED}┌──────────────────────────────────┐${NC}"
    echo -e "${RED}│${YELLOW}   Liste des hébergements         ${RED}│${NC}"
    echo -e "${RED}└──────────────────────────────────┘${NC}"
    echo ""

    show_users_list
    echo ""
    echo -e "${YELLOW}${BD} --- Détails ---${RS}${NC}"

    while IFS=: read -r name _ uid _ _ home _; do
        if [[ $uid -ge 1000 && $uid -ne 65534 && -d "$home/www" ]]; then
            local used shell db_status ftp_status ssh_status
            used=$(du -sh "$home" 2>/dev/null | cut -f1)
            shell=$(getent passwd "$name" | cut -d: -f7)
            db_status="Non"
            command -v mysql &>/dev/null && db_exists "${name}_db" && db_status="Oui"
            ftp_status="Non"
            grep -q "^$name$" /etc/vsftpd.userlist 2>/dev/null && ftp_status="Oui"
            [[ "$shell" == "/bin/bash" ]] && ssh_status="Oui" || ssh_status="Non"
            echo -e "  ${CYAN}$name${NC} | Espace: $used | SSH: $ssh_status | DB: $db_status | FTP: $ftp_status"
        fi
    done < /etc/passwd

    pause
}

# =============================================================================
# GESTION DES FICHIERS WEB
# =============================================================================

install_wordpress() {
    local username="$1"
    local web_dir="/home/$username/www"

    info_msg "Téléchargement de WordPress..."

    if ! command -v wget &>/dev/null && ! command -v curl &>/dev/null; then
        error_msg "wget ou curl requis pour télécharger WordPress."
        return
    fi

    local wp_archive="/tmp/wordpress_$username.tar.gz"

    if command -v wget &>/dev/null; then
        wget -q -O "$wp_archive" "https://wordpress.org/latest.tar.gz"
    else
        curl -s -o "$wp_archive" "https://wordpress.org/latest.tar.gz"
    fi

    if [[ ! -f "$wp_archive" ]]; then
        error_msg "Téléchargement échoué."
        return
    fi

    info_msg "Extraction de WordPress dans $web_dir..."
    tar -xzf "$wp_archive" -C /tmp/
    rsync -a /tmp/wordpress/ "$web_dir/" 2>/dev/null || cp -r /tmp/wordpress/. "$web_dir/"
    chown -R "$username:$username" "$web_dir"
    chmod -R 755 "$web_dir"
    rm -rf "$wp_archive" /tmp/wordpress

    success_msg "WordPress installé dans $web_dir"
    info_msg "Configurez wp-config.php avec les identifiants de la base de données."
}

manage_web_files() {
    clear
    echo -e "${RED}┌──────────────────────────────────┐${NC}"
    echo -e "${RED}│${YELLOW}   Gestion des fichiers web       ${RED}│${NC}"
    echo -e "${RED}└──────────────────────────────────┘${NC}"
    echo ""

    show_users_list
    echo ""
    read -rp " ● Nom d'utilisateur : " username

    if [[ -z "$username" ]] || ! user_exists "$username"; then
        error_msg "Utilisateur invalide ou inexistant."
        pause; return
    fi

    local web_dir="/home/$username/www"
    local used
    used=$(du -sh "$web_dir" 2>/dev/null | cut -f1)

    echo ""
    echo -e "${YELLOW}${BD} --- $username ---${RS}${NC}"
    echo -e "  Site web        : $web_dir"
    echo -e "  Espace utilisé  : $used"
    echo ""
    echo -e "${YELLOW}${BD} --- Fichiers dans www ---${RS}${NC}"
    if [[ -d "$web_dir" ]]; then
        ls -lh "$web_dir" 2>/dev/null || echo "  (vide)"
    else
        echo -e "  ${YELLOW}Répertoire www introuvable.${NC}"
    fi

    echo ""
    echo "  1 - Installer WordPress"
    echo "  0 - Retour"
    echo ""
    read -rp ">>> " web_choice

    if [ "$web_choice" = "1" ]; then
        install_wordpress "$username"
    elif [ "$web_choice" = "0" ]; then
        return
    else
        error_msg "Choix invalide."
    fi

    pause
}

# =============================================================================
# GESTION DES BASES DE DONNÉES
# =============================================================================

create_database() {
    local username="$1"
    local db_name="${username}_db"
    local db_user="$username"

    if ! command -v mysql &>/dev/null; then
        warn_msg "MySQL/MariaDB non disponible. Base de données non créée."
        return
    fi

    local db_pass db_pass2
    db_pass="rien"
    db_pass2=" "
    until [ "$db_pass" = "$db_pass2" ] && [ -n "$db_pass" ]; do
        read -s -p " ● Mot de passe pour la base '$db_name' : " db_pass
        echo " "
        read -s -p "   Confirmer : " db_pass2
        echo
        if [ "$db_pass" != "$db_pass2" ]; then
            echo " "
            echo -e "${RED}${IT}${BD}   Erreur: vous avez inséré deux mots de passe différents${RS}${NC}"
            echo " "
        fi
    done

    mysql -e "CREATE DATABASE IF NOT EXISTS \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null
    mysql -e "CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_pass';" 2>/dev/null
    mysql -e "GRANT ALL PRIVILEGES ON \`$db_name\`.* TO '$db_user'@'localhost';" 2>/dev/null
    mysql -e "FLUSH PRIVILEGES;" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        success_msg "Base de données '$db_name' créée. Utilisateur : $db_user."
    else
        error_msg "Erreur lors de la création de la base de données."
    fi
}

delete_database() {
    local username="$1"
    local db_name="${username}_db"
    local db_user="$username"

    if ! command -v mysql &>/dev/null; then
        warn_msg "MySQL/MariaDB non disponible."
        return
    fi

    mysql -e "DROP DATABASE IF EXISTS \`$db_name\`;" 2>/dev/null
    mysql -e "DROP USER IF EXISTS '$db_user'@'localhost';" 2>/dev/null
    mysql -e "FLUSH PRIVILEGES;" 2>/dev/null

    success_msg "Base de données '$db_name' et utilisateur '$db_user' supprimés."
}

manage_databases() {
    clear
    echo -e "${RED}┌──────────────────────────────────┐${NC}"
    echo -e "${RED}│${YELLOW}   Gestion des bases de données   ${RED}│${NC}"
    echo -e "${RED}└──────────────────────────────────┘${NC}"
    echo ""

    if ! command -v mysql &>/dev/null; then
        error_msg "MySQL/MariaDB non détecté sur ce serveur."
        pause; return
    fi

    echo "  1 - Créer une base de données"
    echo "  2 - Supprimer une base de données"
    echo "  3 - Afficher toutes les bases"
    echo "  0 - Retour"
    echo ""
    read -rp ">>> " db_choice

    if [ "$db_choice" = "1" ]; then
        show_users_list
        echo ""
        read -rp " ● Utilisateur pour la base de données : " username
        if user_exists "$username"; then
            create_database "$username"
        else
            error_msg "Utilisateur '$username' inexistant."
        fi

    elif [ "$db_choice" = "2" ]; then
        show_users_list
        echo ""
        read -rp " ● Utilisateur dont supprimer la base : " username
        if user_exists "$username"; then
            local db_name="${username}_db"
            echo " ● Confirmer la suppression de '$db_name' ?"
            local confirm
            select confirm in "oui" "non"; do
                [ "$confirm" = "oui" ] || [ "$confirm" = "non" ] && break
            done
            [[ "$confirm" == "oui" ]] && delete_database "$username"
        else
            error_msg "Utilisateur '$username' inexistant."
        fi

    elif [ "$db_choice" = "3" ]; then
        echo ""
        echo -e "${YELLOW}${BD} --- Bases de données existantes ---${RS}${NC}"
        mysql -e "SHOW DATABASES;" 2>/dev/null | grep -v "^Database$\|information_schema\|performance_schema\|mysql\|sys"

    elif [ "$db_choice" = "0" ]; then
        return

    else
        error_msg "Choix invalide."
    fi

    pause
}

# =============================================================================
# INFORMATIONS SERVEUR
# =============================================================================

server_info() {
    clear
    echo -e "${RED}┌──────────────────────────────────┐${NC}"
    echo -e "${RED}│${YELLOW}   Informations Serveur           ${RED}│${NC}"
    echo -e "${RED}└──────────────────────────────────┘${NC}"
    echo ""

    echo -e "${YELLOW}${BD}[Système]${RS}${NC}"
    echo -e "  Hostname     : $(hostname)"
    echo -e "  OS           : $(lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
    echo -e "  Uptime       : $(uptime -p 2>/dev/null || uptime)"
    echo -e "  Date         : $(date)"
    echo ""

    echo -e "${YELLOW}${BD}[Disque]${RS}${NC}"
    df -h / | awk 'NR==2 {printf "  Total: %s | Utilisé: %s | Libre: %s | Usage: %s\n", $2, $3, $4, $5}'
    echo ""

    echo -e "${YELLOW}${BD}[Mémoire RAM]${RS}${NC}"
    free -h | awk 'NR==2 {printf "  Total: %s | Utilisé: %s | Libre: %s\n", $2, $3, $4}'
    echo ""

    echo -e "${YELLOW}${BD}[Hébergements]${RS}${NC}"
    local count=0
    while IFS=: read -r name _ uid _ _ home _; do
        if [[ $uid -ge 1000 && $uid -ne 65534 && -d "$home/www" ]]; then
            local used
            used=$(du -sh "$home" 2>/dev/null | cut -f1)
            echo -e "  ${CYAN}$name${NC} -> $home (Utilisé: $used)"
            ((count++))
        fi
    done < /etc/passwd
    echo -e "  Nombre total : $count hébergement(s)"
    echo ""

    echo -e "${YELLOW}${BD}[Services]${RS}${NC}"
    for service in apache2 nginx vsftpd mysql mariadb ssh; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "  $service : ${GREEN}Actif${NC}"
        elif systemctl list-units --type=service 2>/dev/null | grep -q "$service"; then
            echo -e "  $service : ${RED}Inactif${NC}"
        fi
    done
    echo ""

    echo -e "${YELLOW}${BD}[Réseau]${RS}${NC}"
    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    echo -e "  IP principale : $ip"

    pause
}

# =============================================================================
# POINT D'ENTRÉE
# =============================================================================

check_admin
install_deps

while true; do
    show_menu
    read -rp ">>> " choix

    if [ "$choix" = "1" ]; then
        create_user
    elif [ "$choix" = "2" ]; then
        delete_user
    elif [ "$choix" = "3" ]; then
        modify_user
    elif [ "$choix" = "4" ]; then
        show_user
    elif [ "$choix" = "5" ]; then
        list_users
    elif [ "$choix" = "6" ]; then
        manage_web_files
    elif [ "$choix" = "7" ]; then
        manage_databases
    elif [ "$choix" = "8" ]; then
        server_info
    elif [ "$choix" = "0" ]; then
        echo ""
        info_msg "Au revoir !"
        exit 0
    else
        echo ""
        error_msg "Choix invalide. Veuillez entrer un numéro entre 0 et 8."
        sleep 1
    fi
done
