#!/bin/bash

# Script d'upgrade des 2 conteneurs de demo.
# Ce script n'a vocation qu'a être dans un cron

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

LXC_NAME1=$(cat "$script_dir/demo_lxc_build.sh" | grep LXC_NAME1= | cut -d '=' -f2)
LXC_NAME2=$(cat "$script_dir/demo_lxc_build.sh" | grep LXC_NAME2= | cut -d '=' -f2)
IP_LXC1=$(cat "$script_dir/demo_lxc_build.sh" | grep IP_LXC1= | cut -d '=' -f2)
IP_LXC2=$(cat "$script_dir/demo_lxc_build.sh" | grep IP_LXC2= | cut -d '=' -f2)
PLAGE_IP=$(cat "$script_dir/demo_lxc_build.sh" | grep PLAGE_IP= | cut -d '=' -f2)
TIME_TO_SWITCH=$(cat "$script_dir/demo_lxc_build.sh" | grep TIME_TO_SWITCH= | cut -d '=' -f2)
MAIL_ADDR=$(cat "$script_dir/demo_lxc_build.sh" | grep MAIL_ADDR= | cut -d '=' -f2)
DOMAIN=$(cat "$script_dir/domain.ini")

IP_UPGRADE=$PLAGE_IP.150
LOOP=0

log_line=$(wc -l "$script_dir/demo_upgrade.log" | cut -d ' ' -f 1)	# Repère la fin du log actuel. Pour récupérer les lignes ajoutées sur cette exécution.
log_line=$(( $log_line + 1 ))	# Ignore la première ligne, reprise de l'ancien log.

UPGRADE_DEMO_CONTAINER () {		# Démarrage, upgrade et snapshot
	MACHINE=$1
	IP_MACHINE=$2
	# Attend que la machine soit éteinte.
	# Timeout à $TIME_TO_SWITCH +5 minutes, en seconde
	TIME_OUT=$(($TIME_TO_SWITCH * 60 + 300))
	sudo lxc-wait -n $MACHINE -s 'STOPPED' -t $TIME_OUT

	while test -e /var/lib/lxc/$MACHINE.lock_fileS; do
		sleep 5	# Attend que le conteneur soit libéré par le script switch.
	done

	sudo touch /var/lib/lxc/$MACHINE.lock_fileU	# Met en place un fichier pour indiquer que la machine est indisponible pendant l'upgrade

	# Restaure le snapshot
	sudo lxc-snapshot -r snap0 -n $MACHINE

	# Change l'ip du conteneur le temps de l'upgrade. Pour empêcher HAProxy de basculer sur le conteneur.
	sudo sed -i "s@address $IP_MACHINE@address $IP_UPGRADE@" /var/lib/lxc/$MACHINE/rootfs/etc/network/interfaces

	# Démarre le conteneur
	date >> "$script_dir/demo_boot.log"
	sudo lxc-start -n $MACHINE -o "$script_dir/demo_boot.log" -d > /dev/null
	sleep 10

	# Update
	update_apt=0
	sudo lxc-attach -n $MACHINE -- apt-get update
	sudo lxc-attach -n $MACHINE -- apt-get dist-upgrade --dry-run | grep -q "^Inst " > /dev/null	# Vérifie si il y aura des mises à jour.
	if [ "$?" -eq 0 ]; then
            date
            update_apt=1
            # Upgrade
            sudo lxc-attach -n $MACHINE -- apt-get dist-upgrade -y
            # Clean
            sudo lxc-attach -n $MACHINE -- apt-get autoremove -y
            sudo lxc-attach -n $MACHINE -- apt-get autoclean
	fi

	# Exécution des scripts de upgrade.d
	LOOP=$((LOOP + 1))
	while read LIGNE
	do
		if [ ! "$LIGNE" == "exemple" ] && [ ! "$LIGNE" == "old_scripts" ] && ! echo "$LIGNE" | grep -q ".fail$"	# Le fichier exemple, le dossier old_scripts et les scripts fail sont ignorés
		then
			date
			# Exécute chaque script trouvé dans upgrade.d
			echo "Exécution du script $LIGNE sur le conteneur $MACHINE"
			/bin/bash "$script_dir/upgrade.d/$LIGNE" $MACHINE
			if [ "$?" -ne 0 ]; then	# Si le script a échoué, le snapshot est annulé.
				echo "Échec du script $LIGNE"
				mv -f "$script_dir/upgrade.d/$LIGNE" "$script_dir/upgrade.d/$LIGNE.fail"
				echo -e "Échec d'exécution du script d'upgrade $LIGNE sur le conteneur $MACHINE sur le serveur de demo $DOMAIN!\nLe script a été renommé en .fail, il ne sera plus exécuté tant que le préfixe ne sera pas retiré.\n\nExtrait du log:\n$(tail -n +$log_line "$script_dir/demo_upgrade.log")" | mail -a "Content-Type: text/plain; charset=UTF-8" -s "Demo Yunohost" $MAIL_ADDR
				update_apt=0
			else
				echo "Le script $LIGNE a été exécuté sans erreur"
				update_apt=1
			fi
		fi
	done <<< "$(ls -1 "$script_dir/upgrade.d")"

	# Arrêt de la machine virtualisée
	sudo lxc-stop -n $MACHINE

	# Restaure l'ip d'origine du conteneur.
	sudo sed -i "s@address $IP_UPGRADE@address $IP_MACHINE@" /var/lib/lxc/$MACHINE/rootfs/etc/network/interfaces

	if [ "$update_apt" -eq "1" ]
	then
		# Archivage du snapshot
		sudo tar -cz --acls --xattrs -f /var/lib/lxcsnaps/$MACHINE/snap0.tar.gz /var/lib/lxcsnaps/$MACHINE/snap0
		# Remplacement du snapshot
		sudo lxc-snapshot -n $MACHINE -d snap0
		sudo lxc-snapshot -n $MACHINE

		if [ "$LOOP" -eq 2 ]
		then	# Après l'upgrade du 2e conteneur, déplace les scripts dans le dossier des anciens scripts si ils ont été exécutés avec succès.
			ls -1 "$script_dir/upgrade.d" | while read LIGNE
			do
				if [ ! "$LIGNE" == "exemple" ] && [ ! "$LIGNE" == "old_scripts" ] && ! echo "$LIGNE" | grep -q ".fail$"	# Le fichier exemple, le dossier old_scripts et les scripts fail sont ignorés
				then
					mv -f "$script_dir/upgrade.d/$LIGNE" "$script_dir/upgrade.d/old_scripts/$LIGNE"
				fi
			done
		fi
	fi
	sudo rm /var/lib/lxc/$MACHINE.lock_fileU	# Libère le lock, la machine est à nouveau disponible
}

echo ""
date
UPGRADE_DEMO_CONTAINER $LXC_NAME1 $IP_LXC1
UPGRADE_DEMO_CONTAINER $LXC_NAME2 $IP_LXC2
