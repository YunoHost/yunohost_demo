#!/bin/bash

# Purge l'ensemble de la config lxc pour les conteneurs de demo.
# Il sera nécessaire de lancer le script demo_lxc_build_init.sh pour réinstaller l'ensemble le cas échéant.
# !!! Ce script est conçu pour être exécuté par l'user root.

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$PWD/$(dirname "$0" | cut -d '.' -f2)"; fi

LXC_NAME1=$(cat "$script_dir/demo_lxc_build.sh" | grep LXC_NAME1= | cut -d '=' -f2)
DOMAIN=$(cat "$script_dir/demo_lxc_build.sh" | grep DOMAIN= | cut -d '=' -f2)

"$script_dir/demo_lxc_destroy.sh"

echo "> Retire l'ip forwarding."
sudo rm /etc/sysctl.d/lxc_demo.conf
sudo sysctl -p

echo "> Supprime le brige réseau"
sudo rm /etc/network/interfaces.d/lxc_demo

# LXC était déjà installé sur le serveur de demo actuel. On ne l'enlève pas.
echo "> Remove lxc lxctl"
sudo apt-get remove lxc lxctl

echo "> Suppression de la clé SSH"
rm -f $HOME/.ssh/$LXC_NAME1 $HOME/.ssh/$LXC_NAME1.pub
echo "> Et de sa config spécifique dans $HOME/.ssh/config"
BEGIN_LINE=$(cat $HOME/.ssh/config | grep -n "^# ssh $LXC_NAME1" | cut -d':' -f 1)
sed -i "$BEGIN_LINE,/^# End ssh $LXC_NAME1/d" $HOME/.ssh/config

# Suppression du reverse proxy
sudo rm /etc/nginx/conf.d/$DOMAIN.conf
sudo service nginx reload

# Suppression de la config haproxy
# La config haproxy est modifiée manuellement.
# On peut commenter les lignes des serveurs LXC. Et éventuellement relancer les conteneurs dockers.
