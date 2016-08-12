#!/bin/bash

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$PWD/$(dirname "$0" | cut -d '.' -f2)"; fi

PLAGE_IP=$(cat "$script_dir/demo_lxc_build.sh" | grep PLAGE_IP= | cut -d '"' -f2)
LXC_NAME1=$(cat "$script_dir/demo_lxc_build.sh" | grep LXC_NAME1= | cut -d '"' -f2)
LXC_NAME2=$(cat "$script_dir/demo_lxc_build.sh" | grep LXC_NAME2= | cut -d '"' -f2)

UPGRADE_DEMO_CONTAINER () {		# Démarrage, upgrade et snapshot
	MACHINE=$1
	# Attend que la machine soit éteinte.
	sudo lxc-wait -n $MACHINE -s STOPPED #-t 2000 (Timeout à 33 minutes, puisque le swith est à 30 minutes)

	# Restaure le snapshot
	sudo lxc-snapshot -r snap0 $MACHINE

	# Démarre le conteneur
	sudo lxc-start -n $MACHINE -d
	sleep 10

	# Update
	sudo lxc-attach -n $MACHINE -- apt-get update
	sudo lxc-attach -n $MACHINE -- apt-get dist-upgrade --dry-run | grep -q "^Inst "	# Vérifie si il y aura des mises à jour.
	update_apt=0
	if [ "$?" -eq 0 ]; then
		update_apt=1
	fi
	# Upgrade
	sudo lxc-attach -n $MACHINE -- apt-get dist-upgrade
	# Clean
	sudo lxc-attach -n $MACHINE -- apt-get autoremove
	sudo lxc-attach -n $MACHINE -- apt-get autoclean

	# Arrêt de la machine virtualisée
	sudo lxc-stop -n $MACHINE

	if [ "$update_apt" -eq 1 ]
	then
		# Archivage du snapshot
		sudo tar -cz --acls --xattrs -f /var/lib/lxcsnaps/$MACHINE/snap0.tar.gz /var/lib/lxcsnaps/$MACHINE/snap0
		# Remplacement du snapshot
		sudo lxc-snapshot -n $MACHINE -d snap0
		sudo lxc-snapshot -n $MACHINE
	fi
}

# Initialisation du réseau pour le conteneur.
if ! sudo ifquery lxc_demo --state > /dev/null; then
	sudo ifup lxc_demo --interfaces=/etc/network/interfaces.d/lxc_demo
fi

# Activation des règles iptables
if ! sudo iptables -D FORWARD -i lxc_demo -o eth0 -j ACCEPT 2> /dev/null; then
	sudo iptables -A FORWARD -i lxc_demo -o eth0 -j ACCEPT
fi
if ! sudo iptables -C FORWARD -i eth0 -o lxc_demo -j ACCEPT 2> /dev/null; then
	sudo iptables -A FORWARD -i eth0 -o lxc_demo -j ACCEPT
fi
if ! sudo iptables -t nat -C POSTROUTING -s $PLAGE_IP.0/24 -j MASQUERADE 2> /dev/null; then
	sudo iptables -t nat -A POSTROUTING -s $PLAGE_IP.0/24 -j MASQUERADE
fi

UPGRADE_DEMO_CONTAINER $LXC_NAME1
UPGRADE_DEMO_CONTAINER $LXC_NAME2
