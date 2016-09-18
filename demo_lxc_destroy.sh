#!/bin/bash

# Détruit les conteneurs lxc de demo.
# Permet de repartir sur des bases saines avec le script demo_lxc_build.sh

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

LXC_NAME1=$(cat "$script_dir/demo_lxc_build.sh" | grep LXC_NAME1= | cut -d '=' -f2)
LXC_NAME2=$(cat "$script_dir/demo_lxc_build.sh" | grep LXC_NAME2= | cut -d '=' -f2)
IP_LXC1=$(cat "$script_dir/demo_lxc_build.sh" | grep IP_LXC1= | cut -d '=' -f2)
IP_LXC2=$(cat "$script_dir/demo_lxc_build.sh" | grep IP_LXC2= | cut -d '=' -f2)

# Check user
if [ "$USER" != "$(cat "$script_dir/setup_user")" ]; then
	echo -e "\e[91mCe script doit être exécuté avec l'utilisateur $(cat "$script_dir/sub_scripts/setup_user")"
	echo -en "\e[0m"
	exit 0
fi

"$script_dir/demo_stop.sh"

echo "> Suppression des conteneurs et de leur snapshots"
sudo lxc-snapshot -n $LXC_NAME1 -d snap0
sudo rm -f /var/lib/lxcsnaps/$LXC_NAME1/snap0.tar.gz
sudo lxc-destroy -n $LXC_NAME1 -f
sudo lxc-snapshot -n $LXC_NAME2 -d snap0
sudo rm -f /var/lib/lxcsnaps/$LXC_NAME2/snap0.tar.gz
sudo lxc-destroy -n $LXC_NAME2 -f

echo "> Suppression des crons"
sudo rm /etc/cron.d/demo_switch
sudo rm /etc/cron.d/demo_upgrade

echo "> Suppression des clés ECDSA dans known_hosts"
ssh-keygen -f "$HOME/.ssh/known_hosts" -R $IP_LXC1
ssh-keygen -f "$HOME/.ssh/known_hosts" -R $IP_LXC2

echo "> Suppression du service"
sudo systemctl disable lutim.service
sudo rm -f /etc/systemd/system/lxc_demo.service
