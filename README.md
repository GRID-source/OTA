# OTA - Architecture Open Source pour l’Hébergement Multi-Utilisateurs

OTA (OpenSource Tenant Architecture) est un outil d’administration d’hébergement multi-utilisateurs écrit en Bash, conçu pour automatiser le déploiement et la gestion d’environnements web sous Linux.
Il fournit une interface interactive en terminal permettant de gérer facilement les utilisateurs, les hébergements web, les bases de données, les accès FTP/SSH, les quotas et les informations serveur.


# Fonctionnalités

**Gestion des hébergements**

- Création et suppression de comptes d’hébergement
- Modification des configurations
- Affichage des détails d’un hébergement
- Liste des utilisateurs hébergés

**Configuration utilisateur**

- Gestion des mots de passe
- Activation / Désactivation SSH
- Activation / Désactivation FTP
- Attribution des quotas disque
- Création automatique des dossiers utilisateurs

**Hébergement web**

- Création automatique des VirtualHosts Apache
- Génération du dossier `/www`
- Création d’un site par défaut
- Support d’installation WordPress

**Gestion des bases de données**

- Création et suppression de bases MySQL/MariaDB
- Gestion des utilisateurs et permissions
- Liste des bases existantes

**Informations serveur**

- Utilisation du disque
- Statistiques RAM
- État des services
- Informations réseau
- Vue globale des hébergements


# Services utilisés

OTA installe automatiquement les paquets nécessaires :

* apache2
* php
* mariadb-server
* wget
* unzip
* vsftpd
* quota

# Pourquoi OTA ?

OTA a été conçu pour fournir une alternative légère aux panels d’hébergement lourds comme cPanel ou Plesk.

Objectifs :
- Déploiement rapide
- Interface terminal simple
- Peu de dépendances
- Contrôle complet du système
- Solution open source et personnalisable
