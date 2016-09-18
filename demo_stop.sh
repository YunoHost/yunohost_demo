#!/bin/bash

# Stoppe les conteneurs de demo et arrête la config réseau dédiée.

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

PLAGE_IP=$(cat "$script_dir/demo_lxc_build.sh" | grep PLAGE_IP= | cut -d '=' -f2)
LXC_NAME1=$(cat "$script_dir/demo_lxc_build.sh" | grep LXC_NAME1= | cut -d '=' -f2)
LXC_NAME2=$(cat "$script_dir/demo_lxc_build.sh" | grep LXC_NAME2= | cut -d '=' -f2)

if [ "$#" -eq 1 ] && [ "$1" == "-f" ]
then
	echo "> Suppression des lock et arrêt forcé des conteneurs."
	sudo rm -f /var/lib/lxc/$LXC_NAME1.lock_fileS
	sudo rm -f /var/lib/lxc/$LXC_NAME2.lock_fileS
	sudo rm -f /var/lib/lxc/$LXC_NAME1.lock_fileU
	sudo rm -f /var/lib/lxc/$LXC_NAME2.lock_fileU
else
	echo "> Attend la libération des lock sur les conteneurs."
	while test -e /var/lib/lxc/$LXC_NAME1.lock_file* || test -e /var/lib/lxc/$LXC_NAME2.lock_file*; do
		sleep 5	# Attend que les conteneur soit libérés par les script upgrade ou switch, le cas échéant.
	done
fi

echo "> Arrêt des conteneurs"
if [ $(sudo lxc-info --name $LXC_NAME1 | grep -c "STOPPED") -eq 0 ]; then
	echo "Arrêt du conteneur $LXC_NAME1"
	sudo lxc-stop -n $LXC_NAME1
fi
if [ $(sudo lxc-info --name $LXC_NAME2 | grep -c "STOPPED") -eq 0 ]; then
	echo "Arrêt du conteneur $LXC_NAME2"
	sudo lxc-stop -n $LXC_NAME2
fi

echo "> Suppression des règles de parefeu"
if sudo iptables -C FORWARD -i lxc_demo -o eth0 -j ACCEPT 2> /dev/null; then
	sudo iptables -D FORWARD -i lxc_demo -o eth0 -j ACCEPT
fi
if sudo iptables -C FORWARD -i eth0 -o lxc_demo -j ACCEPT 2> /dev/null; then
	sudo iptables -D FORWARD -i eth0 -o lxc_demo -j ACCEPT
fi
if sudo iptables -t nat -C POSTROUTING -s $PLAGE_IP.0/24 -j MASQUERADE 2> /dev/null; then
	sudo iptables -t nat -D POSTROUTING -s $PLAGE_IP.0/24 -j MASQUERADE
fi

echo "Arrêt de l'interface réseau pour le conteneur."
if sudo ifquery lxc_demo --state > /dev/null; then
	sudo ifdown --force lxc_demo
fi

sudo lxc-ls -f
