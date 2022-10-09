# Scripts de gestion et mise en place des serveurs de demo Yunohost sous LXC

## Prérequis
* `apt install sudo git nginx -y`
* register a dns name to your demo server and make you demo server available from internet for TCP/80 and TCP/443

## demo_lxc_build
Ce script construit les conteneurs de demo et les paramètres.  
Il met également en places les crons et démarre le 1er conteneur.  
Après l'exécution de ce script, la demo est en place.

## demo_lxc_destroy
Ce script arrête les conteneurs et les détruits.  
Il sert en général à une reconstruction des conteneurs avec de nouveaux paramètres. Et devrait donc être suivi du script demo_lxc_build.

## demo_lxc_remove
Ce script, après avoir appelé demo_lxc_destroy va désinstaller LXC et remettre le serveur à son état d'origine. Retirant les paramétrages mis en place pour la demo.  
Il ne devrait être utilisé qu'en cas de changement de serveur hôte.

## demo_start
Permet simplement un démarrage propre du 1er conteneur. Avec la mise en place du bridge réseau et des règles de parefeu.

## demo_stop
Arrête proprement les conteneurs et désactive la config réseau spécifique.

## demo_switch
Ce script est placé en cron par demo_lxc_build.  
Il va alterner toutes les 30 minutes (par défaut) les 2 conteneurs et rétablir le snapshot du conteneurs après son extinction.

## demo_upgrade
Ce script est placé en cron par demo_lxc_build.  
demo_upgrade vérifie chaque nuit les mises à jour sur les conteneurs, et les applique le cas échéant. Si nécessaire, il se charge également de refaire le snapshot.

## demo_restore_crash
Tente de réparer les conteneurs qui ne démarre pas à partir des snapshots ou des archives de snapshots précédents.

Pour effectuer des modifications pérennes sur les conteneurs, il est possible d'ajouter des scripts dans le dossier upgrade.d. Ces scripts seront exécutés après l'upgrade des packages dans chaque conteneur.
En cas d'échec d'exécution, le script sera mis de côté en attendant sa correction. Sinon, il sera archivé.
