#!/bin/bash

# Purge l'ensemble de la config lxc pour les conteneurs de demo.
# Il sera nécessaire de lancer le script demo_lxc_build_init.sh pour réinstaller l'ensemble le cas échéant.

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$PWD/$(dirname "$0" | cut -d '.' -f2)"; fi

LXC_NAME1=$(cat "$script_dir/lxc_build.sh" | grep LXC_NAME1= | cut -d '=' -f2)

"$script_dir/demo_lxc_destroy.sh"

echo "> Retire l'ip forwarding."
sudo rm /etc/sysctl.d/lxc_demo.conf
sudo sysctl -p

echo "> Supprime le brige réseau"
sudo rm /etc/network/interfaces.d/lxc_demo

echo "> Remove lxc lxctl"
sudo apt-get remove lxc lxctl

echo "> Suppression des lignes de pchecker_lxc dans .ssh/config"
BEGIN_LINE=$(cat $HOME/.ssh/config | grep -n "^# ssh $LXC_NAME1$" | cut -d':' -f 1)
sed -i "$BEGIN_LINE,/^IdentityFile/d" $HOME/.ssh/config

# Suppression de la clé SSH...
# Suppression du reverse proxy ?
# Suppression de la config haproxy
