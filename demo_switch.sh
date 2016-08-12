#!/bin/bash

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$PWD/$(dirname "$0" | cut -d '.' -f2)"; fi

PLAGE_IP=$(cat "$script_dir/demo_lxc_build.sh" | grep PLAGE_IP= | cut -d '"' -f2)
LXC_NAME1=$(cat "$script_dir/demo_lxc_build.sh" | grep LXC_NAME1= | cut -d '"' -f2)
LXC_NAME2=$(cat "$script_dir/demo_lxc_build.sh" | grep LXC_NAME2= | cut -d '"' -f2)

# Vérifie l'état des machines.
if [ $(sudo lxc-info --name $LXC_NAME1 | grep -c "STOPPED") -eq 0 ]; then	# Si la machine 1 est démarrée.
	LXC_A=$LXC_NAME1
	LXC_B=$LXC_NAME2
else	# Sinon, on suppose que c'est la machine 2 qui est en cours.
	LXC_A=$LXC_NAME2
	LXC_B=$LXC_NAME1
	# Si aucune machine ne tourne, la première démarrera.
fi


# Démarre le conteneur B et arrête le conteneur A.
sudo lxc-start -n $LXC_B -d	# Démarre l'autre machine
sleep 10	# Attend 10 seconde pour s'assurer du démarrage de la machine.
if [ $(sudo lxc-info --name $LXC_B | grep -c "STOPPED") -ne 0 ]; then
	# Le conteneur n'a pas réussi à démarrer. On devrait avertir un responsable par mail...
	# [...]
	return 1
else
	# Bascule sur le conteneur B avec HAProxy...
	# [...]
	# Arrêt du conteneur A. Il est remplacé par le B
	sudo lxc-stop -n $LXC_A
	# Restaure le snapshot de la machine A avant sa prochaine exécution
# 	sudo rsync -aEAX --delete -i /var/lib/lxcsnaps/$LXC_A/snap0/rootfs/ /var/lib/lxc/$LXC_A/rootfs/
	sudo lxc-snapshot -r snap0 $LXC_A
fi
