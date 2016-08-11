#!/bin/bash

PLAGE_IP="10.1.4"
LXC_NAME=yunohost_demo

echo "Initialisation du réseau pour le conteneur."
sudo ifup lxc_demo --interfaces=/etc/network/interfaces.d/lxc_demo

# Activation des règles iptables
echo "> Configure le parefeu"
sudo iptables -A FORWARD -i lxc_demo -o eth0 -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o lxc_demo -j ACCEPT
sudo iptables -t nat -A POSTROUTING -s $PLAGE_IP.0/24 -j MASQUERADE

# Démarrage de la machine
echo "> Démarrage de la machine"
sudo lxc-start -n $LXC_NAME -d
sleep 3

# Vérifie que la machine a démarré:
sudo lxc-ls -f
