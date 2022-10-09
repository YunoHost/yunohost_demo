#!/bin/bash

# Script de switch entre les 2 conteneurs de demo.
# Ce script n'a vocation qu'a être dans un cron

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

PLAGE_IP=$(cat "$script_dir/demo_lxc_build.sh" | grep PLAGE_IP= | cut -d '=' -f2)
LXC_NAME1=$(cat "$script_dir/demo_lxc_build.sh" | grep LXC_NAME1= | cut -d '=' -f2)
LXC_NAME2=$(cat "$script_dir/demo_lxc_build.sh" | grep LXC_NAME2= | cut -d '=' -f2)
MAIL_ADDR=$(cat "$script_dir/demo_lxc_build.sh" | grep MAIL_ADDR= | cut -d '=' -f2)
DOMAIN=$(cat "$script_dir/domain.ini")

log_line=$(wc -l "$script_dir/demo_switch.log" | cut -d ' ' -f 1)	# Repère la fin du log actuel. Pour récupérer les lignes ajoutées sur cette exécution.
log_line=$(( $log_line + 1 ))	# Ignore la première ligne, reprise de l'ancien log.
date >> "$script_dir/demo_switch.log"

while test -e /var/lib/lxc/$LXC_NAME1.lock_file* || test -e /var/lib/lxc/$LXC_NAME2.lock_file*; do
	sleep 5	# Attend que le conteneur soit libéré par les script upgrade ou switch, le cas échéant.
done

# Vérifie l'état des machines.
if [ "$(sudo lxc-info --name $LXC_NAME1 | grep -c "RUNNING")" -eq "1" ]
then	# Si la machine 1 est démarrée.
	LXC_A=$LXC_NAME1
	LXC_B=$LXC_NAME2
else	# Sinon, on suppose que c'est la machine 2 qui est en cours.
	LXC_A=$LXC_NAME2
	LXC_B=$LXC_NAME1
	# Si aucune machine ne tourne, la première démarrera.
fi

# Supprime les éventuels swap présents.
/sbin/swapoff /var/lib/lxc/$LXC_A/rootfs/swap_*

echo "Starting $LXC_B"
# Démarre le conteneur B et arrête le conteneur A.
sudo lxc-start -n $LXC_B -o "$script_dir/demo_switch.log" -d > /dev/null	# Démarre l'autre machine
sleep 10	# Attend 10 seconde pour s'assurer du démarrage de la machine.
if [ "$(sudo lxc-info --name $LXC_B | grep -c "STOPPED")" -eq "1" ]
then
	# Le conteneur n'a pas réussi à démarrer. On averti un responsable par mail...
	echo -e "Échec du démarrage du conteneur $LXC_B sur le serveur de demo $DOMAIN! \n\nExtrait du log:\n$(tail -n +$log_line "$script_dir/demo_switch.log")\n\nLe script 'demo_restore_crash.sh' va être exécuté pour tenter de fixer l'erreur." | mail -a "Content-Type: text/plain; charset=UTF-8" -s "Demo Yunohost" $MAIL_ADDR
	$script_dir/demo_restore_crash.sh &
	exit 1
else
	echo "Stopping $LXC_A"
	# Bascule sur le conteneur B avec le load balancing de nginx...
	# Automatique par nginx lorsque la machine A sera éteinte.
	# Arrêt du conteneur A. Il est remplacé par le B
	sudo touch /var/lib/lxc/$LXC_A.lock_fileS	# Met en place un fichier pour indiquer que la machine n'est pas encore dispo.
	sudo lxc-stop -n $LXC_A
	# Supprime les éventuels swap présents.
	/sbin/swapoff /var/lib/lxc/$LXC_A/rootfs/swap_*
	echo "Restauring $LXC_A from snapshot"
	# Restaure le snapshot de la machine A avant sa prochaine exécution
	sudo lxc-snapshot -r snap0 -n $LXC_A
	sudo rm /var/lib/lxc/$LXC_A.lock_fileS	# Libère le lock
fi
