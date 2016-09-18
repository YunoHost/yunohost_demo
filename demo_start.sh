#!/bin/bash

# Démarre le premier conteneur de demo et active la config réseau dédiée.

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

PLAGE_IP=$(cat "$script_dir/demo_lxc_build.sh" | grep PLAGE_IP= | cut -d '=' -f2)
LXC_NAME=$(cat "$script_dir/demo_lxc_build.sh" | grep LXC_NAME1= | cut -d '=' -f2)

"$script_dir/demo_stop.sh" > /dev/null 2>&1

echo "Initialisation du réseau pour le conteneur."
if ! sudo ifquery lxc_demo --state > /dev/null; then
	sudo ifup lxc_demo --interfaces=/etc/network/interfaces.d/lxc_demo
fi

# Activation des règles iptables
echo "> Configure le parefeu"
if ! sudo iptables -D FORWARD -i lxc_demo -o eth0 -j ACCEPT 2> /dev/null; then
	sudo iptables -A FORWARD -i lxc_demo -o eth0 -j ACCEPT
fi
if ! sudo iptables -C FORWARD -i eth0 -o lxc_demo -j ACCEPT 2> /dev/null; then
	sudo iptables -A FORWARD -i eth0 -o lxc_demo -j ACCEPT
fi
if ! sudo iptables -t nat -C POSTROUTING -s $PLAGE_IP.0/24 -j MASQUERADE 2> /dev/null; then
	sudo iptables -t nat -A POSTROUTING -s $PLAGE_IP.0/24 -j MASQUERADE
fi

# Démarrage de la machine
echo "> Démarrage de la machine"
sudo lxc-start -n $LXC_NAME -o "$script_dir/demo_boot.log" -d
sleep 3

# Vérifie que la machine a démarré
sudo lxc-ls -f
