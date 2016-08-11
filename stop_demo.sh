#!/bin/bash

PLAGE_IP="10.1.4"
LXC_NAME=yunohost_demo

echo "> Arrêt de la machine virtualisée"
sudo lxc-stop -n $LXC_NAME

echo "> Suppression des règles de parefeu"
sudo iptables -D FORWARD -i lxc_demo -o eth0 -j ACCEPT
sudo iptables -D FORWARD -i eth0 -o lxc_demo -j ACCEPT
sudo iptables -t nat -D POSTROUTING -s $PLAGE_IP.0/24 -j MASQUERADE

echo "Arrêt de l'interface réseau pour le conteneur."
sudo ifdown --force lxc_demo
