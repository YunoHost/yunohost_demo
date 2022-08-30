#!/bin/bash

# Purge l'ensemble de la config lxc pour les conteneurs de demo.
# Il sera nécessaire de lancer le script demo_lxc_build_init.sh pour réinstaller l'ensemble le cas échéant.

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

LXC_NAME1=$(cat "$script_dir/demo_lxc_build.sh" | grep LXC_NAME1= | cut -d '=' -f2)
DOMAIN=$(cat "$script_dir/domain.ini")

# Check user
if [ "$USER" != "$(cat "$script_dir/setup_user")" ]; then
	echo -e "\e[91mCe script doit être exécuté avec l'utilisateur $(cat "$script_dir/setup_user")"
	echo -en "\e[0m"
	exit 0
fi

"$script_dir/demo_lxc_destroy.sh"

echo -e "\e[1m> Retire l'ip forwarding.\e[0m"
sudo rm /etc/sysctl.d/lxc_demo.conf
sudo sysctl -p

echo -e "\e[1m> Supprime le brige réseau\e[0m"
sudo rm /etc/network/interfaces.d/lxc_demo

echo -e "\e[1m> Remove lxc lxctl\e[0m"
sudo apt-get remove lxc lxctl

echo -e "\e[1m> Suppression de la clé SSH\e[0m"
rm -f $HOME/.ssh/$LXC_NAME1 $HOME/.ssh/$LXC_NAME1.pub
echo -e "\e[1m> Et de sa config spécifique dans $HOME/.ssh/config\e[0m"
BEGIN_LINE=$(cat $HOME/.ssh/config | grep -n "^# ssh $LXC_NAME1" | cut -d':' -f 1)
sed -i "$BEGIN_LINE,/^# End ssh $LXC_NAME1/d" $HOME/.ssh/config

# Suppression du reverse proxy
echo -e "\e[1m> Suppression de la config nginx\e[0m"
sudo rm /etc/nginx/conf.d/$DOMAIN.conf
sudo service nginx reload

# Suppression du certificat Let's encrypt
echo -e "\e[1m> Suppression de Let's encrypt\e[0m"
sudo rm -r /etc/letsencrypt
sudo rm -r ~/.local/share/letsencrypt
sudo rm -r ~/letsencrypt
sudo rm -r /var/lib/letsencrypt
# Supprime la tache cron
sudo rm /etc/cron.weekly/Certificate_Renewer
