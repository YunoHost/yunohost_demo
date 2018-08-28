#!/bin/bash

# Tente de réparer les conteneurs LXC à partir des snapshots et des sauvegardes.

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

PLAGE_IP=$(cat "$script_dir/demo_lxc_build.sh" | grep PLAGE_IP= | cut -d '=' -f2)
IP_LXC1=$(cat "$script_dir/demo_lxc_build.sh" | grep IP_LXC1= | cut -d '=' -f2)
IP_LXC2=$(cat "$script_dir/demo_lxc_build.sh" | grep IP_LXC2= | cut -d '=' -f2)
LXC_NAME1=$(cat "$script_dir/demo_lxc_build.sh" | grep LXC_NAME1= | cut -d '=' -f2)
LXC_NAME2=$(cat "$script_dir/demo_lxc_build.sh" | grep LXC_NAME2= | cut -d '=' -f2)

STOP_CONTAINER () {
	MACHINE=$1
	if [ $(sudo lxc-info --name $MACHINE | grep -c "STOPPED") -eq 0 ]; then
		echo "Arrêt du conteneur $MACHINE"
		sudo lxc-stop -n $MACHINE
	fi
}

CHECK_CONTAINER () {
	MACHINE=$1
	echo "Test du conteneur $MACHINE"
	sudo lxc-start -n $MACHINE -d > /dev/null 2>&1	# Démarre le conteneur
	sudo lxc-wait -n $MACHINE -s 'RUNNING' -t 20	# Attend pendant 20s maximum que le conteneur démarre
# 	sudo lxc-ls -f
	if [ $(sudo lxc-info --name $MACHINE | grep -c "RUNNING") -ne 1 ]; then
		return 1	# Renvoi 1 si le démarrage du conteneur a échoué
	else
		STOP_CONTAINER $MACHINE
		return 0	# Renvoi 0 si le démarrage du conteneur a réussi
	fi
}

RESTORE_SNAPSHOT () {
	MACHINE=$1
	echo -e "\e[1m> Restauration du snapshot du conteneur $MACHINE\e[0m"
	sudo lxc-snapshot -r snap0 -n $MACHINE
	CHECK_CONTAINER $MACHINE
	STATUS=$?
	if [ $STATUS -eq 1 ]; then
		echo -e "\e[91m> Conteneur $MACHINE en défaut.\e[0m"
		return 1
	else
		echo -e "\e[92m> Conteneur $MACHINE en état de marche.\e[0m"
		return 0
	fi
}

RESTORE_ARCHIVE_SNAPSHOT () {
	MACHINE=$1
	if ! test -e "/var/lib/lxcsnaps/$MACHINE/snap1.tar.gz"; then
		echo "Aucune archive de snapshot pour le conteneur $MACHINE"
		return 1
	fi
	echo -e "\e[1m> Restauration du snapshot archivé pour le conteneur $MACHINE\e[0m"
	echo "Suppression du snapshot"
	sudo lxc-snapshot -n $MACHINE -d snap0
	echo "Décompression de l'archive"
 	sudo tar -x --acls --xattrs -f /var/lib/lxcsnaps/$MACHINE/snap0.tar.gz -C /
	RESTORE_SNAPSHOT $MACHINE
	return $?
}

CLONE_CONTAINER () {
	MACHINE_SOURCE=$1
	MACHINE_CIBLE=$2
	IP_SOURCE=$3
	IP_CIBLE=$4
	echo "Suppression du conteneur $MACHINE_CIBLE"
	sudo lxc-snapshot -n $MACHINE_CIBLE -d snap0
	sudo rm -f /var/lib/lxcsnaps/$MACHINE_CIBLE/snap0.tar.gz
	sudo lxc-destroy -n $MACHINE_CIBLE -f

	echo -e "\e[1m> Clone le conteneur $MACHINE_SOURCE sur $MACHINE_CIBLE\e[0m"
	sudo lxc-copy --name=$MACHINE_SOURCE --newname=$MACHINE_CIBLE

	echo "Modification de l'ip du clone,"
	sudo sed -i "s@address $IP_SOURCE@address $IP_CIBLE@" /var/lib/lxc/$MACHINE_CIBLE/rootfs/etc/network/interfaces
	echo "du nom du veth"
	sudo sed -i "s@$MACHINE_SOURCE@$MACHINE_CIBLE@g" /var/lib/lxc/$MACHINE_CIBLE/config
	echo "Et enfin renseigne /etc/hosts sur le clone"
	sudo sed -i "s@^127.0.0.1 $MACHINE_SOURCE@127.0.0.1 $MACHINE_CIBLE@" /var/lib/lxc/$MACHINE_CIBLE/rootfs/etc/hosts

	CHECK_CONTAINER $MACHINE_CIBLE
	STATUS=$?
	if [ $STATUS -eq 1 ]; then
		echo -e "\e[91m> Conteneur $MACHINE_CIBLE en défaut.\e[0m"
	else
		echo -e "\e[92m> Conteneur $MACHINE_CIBLE en état de marche.\e[0m"
		echo "Création d'un nouveau snapshot pour le conteneur $MACHINE_CIBLE"
		sudo lxc-snapshot -n $MACHINE_CIBLE
	fi
	return $STATUS
}

echo "Désactive le cron switch."
sudo sed -i "s/.*demo_switch.sh/#&/" /etc/cron.d/demo_switch	# Le cron est commenté durant l'opération de maintenance.

echo "Suppression des lock et arrêt forcé des conteneurs."
sudo rm -f /var/lib/lxc/$LXC_NAME1.lock_fileS
sudo rm -f /var/lib/lxc/$LXC_NAME2.lock_fileS
sudo rm -f /var/lib/lxc/$LXC_NAME1.lock_fileU
sudo rm -f /var/lib/lxc/$LXC_NAME2.lock_fileU

STOP_CONTAINER $LXC_NAME1
STOP_CONTAINER $LXC_NAME2

echo "Initialisation du réseau pour le conteneur."
if ! sudo ifquery lxc_demo --state > /dev/null; then
	sudo ifup lxc_demo --interfaces=/etc/network/interfaces.d/lxc_demo
fi

# Activation des règles iptables
echo "Configure le parefeu"
if ! sudo iptables -D FORWARD -i lxc_demo -o eth0 -j ACCEPT 2> /dev/null; then
	sudo iptables -A FORWARD -i lxc_demo -o eth0 -j ACCEPT
fi
if ! sudo iptables -C FORWARD -i eth0 -o lxc_demo -j ACCEPT 2> /dev/null; then
	sudo iptables -A FORWARD -i eth0 -o lxc_demo -j ACCEPT
fi
if ! sudo iptables -t nat -C POSTROUTING -s $PLAGE_IP.0/24 -j MASQUERADE 2> /dev/null; then
	sudo iptables -t nat -A POSTROUTING -s $PLAGE_IP.0/24 -j MASQUERADE
fi

# Vérifie l'état des conteneurs.
CHECK_CONTAINER $LXC_NAME1
LXC1_STATUS=$?
CHECK_CONTAINER $LXC_NAME2
LXC2_STATUS=$?

if [ $LXC1_STATUS -eq 1 ]; then
	echo -e "\e[91m> Conteneur $LXC_NAME1 en défaut.\e[0m"
else
	echo -e "\e[92m> Conteneur $LXC_NAME1 en état de marche.\e[0m"
fi
if [ $LXC2_STATUS -eq 1 ]; then
	echo -e "\e[91m> Conteneur $LXC_NAME2 en défaut.\e[0m"
else
	echo -e "\e[92m> Conteneur $LXC_NAME2 en état de marche.\e[0m"
fi

# Restauration des snapshots
if [ $LXC1_STATUS -eq 1 ]; then
	RESTORE_SNAPSHOT $LXC_NAME1
	LXC1_STATUS=$?
fi
if [ $LXC2_STATUS -eq 1 ]; then
	RESTORE_SNAPSHOT $LXC_NAME2
	LXC2_STATUS=$?
fi

# Restauration des archives des snapshots
if [ $LXC1_STATUS -eq 1 ]; then
	RESTORE_ARCHIVE_SNAPSHOT $LXC_NAME1
	LXC1_STATUS=$?
fi
if [ $LXC2_STATUS -eq 1 ]; then
	RESTORE_ARCHIVE_SNAPSHOT $LXC_NAME2
	LXC2_STATUS=$?
fi

# Si des erreurs persistent, tente de cloner depuis un conteneur sain
if [ $LXC1_STATUS -eq 1 ] && [ $LXC2_STATUS -eq 0 ] ; then
	CLONE_CONTAINER $LXC_NAME2 $LXC_NAME1 $IP_LXC2 $IP_LXC1
	LXC1_STATUS=$?
fi
if [ $LXC2_STATUS -eq 1 ] && [ $LXC1_STATUS -eq 0 ]; then
	CLONE_CONTAINER $LXC_NAME1 $LXC_NAME2 $IP_LXC1 $IP_LXC2
	LXC2_STATUS=$?
fi

# Résultats finaux
if [ $LXC1_STATUS -eq 1 ] || [ $LXC2_STATUS -eq 1 ]; then
	if [ $LXC1_STATUS -eq 1 ]; then
		echo -e "\e[91m\n> Le conteneur $LXC_NAME1 n'a pas pu être réparé...\e[0m"
	fi
	if [ $LXC2_STATUS -eq 1 ]; then
		echo -e "\e[91m\n> Le conteneur $LXC_NAME2 n'a pas pu être réparé...\e[0m"
	fi
else
	echo -e "\e[92m\n> Les 2 conteneurs sont sains et fonctionnels.\e[0m"
fi

echo "Réactive le cron switch."
sudo sed -i "s/#*\*/\*/" /etc/cron.d/demo_switch	# Le cron est décommenté
echo "Restart la demo."
./demo_start.sh
