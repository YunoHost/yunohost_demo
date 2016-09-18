#!/bin/bash

# Purge l'ensemble de la config lxc pour les conteneurs de demo.
# Il sera nécessaire de lancer le script demo_lxc_build_init.sh pour réinstaller l'ensemble le cas échéant.

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

LXC_NAME1=$(cat "$script_dir/demo_lxc_build.sh" | grep LXC_NAME1= | cut -d '=' -f2)
DOMAIN=$(cat "$script_dir/domain.ini")

# Check user
if [ "$USER" != "$(cat "$script_dir/setup_user")" ]; then
	echo -e "\e[91mCe script doit être exécuté avec l'utilisateur $(cat "$script_dir/sub_scripts/setup_user")"
	echo -en "\e[0m"
	exit 0
fi

"$script_dir/demo_lxc_destroy.sh"

echo "> Retire l'ip forwarding."
sudo rm /etc/sysctl.d/lxc_demo.conf
sudo sysctl -p

echo "> Supprime le brige réseau"
sudo rm /etc/network/interfaces.d/lxc_demo

echo "> Remove lxc lxctl"
sudo apt-get remove lxc lxctl

echo "> Suppression de la clé SSH"
rm -f $HOME/.ssh/$LXC_NAME1 $HOME/.ssh/$LXC_NAME1.pub
echo "> Et de sa config spécifique dans $HOME/.ssh/config"
BEGIN_LINE=$(cat $HOME/.ssh/config | grep -n "^# ssh $LXC_NAME1" | cut -d':' -f 1)
sed -i "$BEGIN_LINE,/^# End ssh $LXC_NAME1/d" $HOME/.ssh/config

# Suppression du reverse proxy
echo "> Suppression de la config nginx"
sudo rm /etc/nginx/conf.d/$DOMAIN.conf
sudo service nginx reload

# Suppression du certificat Let's encrypt
echo "> Suppression de Let's encrypt"
sudo rm -r /etc/letsencrypt
sudo rm -r ~/.local/share/letsencrypt
sudo rm -r ~/letsencrypt
sudo rm -r /var/lib/letsencrypt
# Supprime la tache cron
sudo rm /etc/cron.weekly/certificateRenewer
