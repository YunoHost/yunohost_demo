#!/bin/bash

# Script de switch entre les 2 conteneurs de demo.
# Ce script n'a vocation qu'a être dans un cron

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

source $script_dir/ynh_lxd
source /usr/share/yunohost/helpers

app=${__APP__:-yunohost_demo}
final_path=$(ynh_app_setting_get --app=$app --key=final_path)
lxdbr_demo_network=$(ynh_app_setting_get --app=$app --key=lxdbr_demo_network)
lxc_ip1=$(ynh_app_setting_get --app=$app --key=lxc_ip1)
lxc_ip2=$(ynh_app_setting_get --app=$app --key=lxc_ip2)
lxc_name1=$(ynh_app_setting_get --app=$app --key=lxc_name1)
lxc_name2=$(ynh_app_setting_get --app=$app --key=lxc_name2)
domain=$(ynh_app_setting_get --app=$app --key=domain)
path_url=$(ynh_app_setting_get --app=$app --key=path)

log_line=$(wc -l "$final_path/demo_switch.log" | cut -d ' ' -f 1)	# Repère la fin du log actuel. Pour récupérer les lignes ajoutées sur cette exécution.
log_line=$(( $log_line + 1 ))	# Ignore la première ligne, reprise de l'ancien log.

date | tee -a "$final_path/demo_switch.log" 2>&1
ynh_print_info --message=">> Start switching demo." | tee -a "$final_path/demo_switch.log" 2>&1

while test -e /var/lib/lxd/$lxc_name1.lock_file* || test -e /var/lib/lxd/$lxc_name2.lock_file*; do
	sleep 5	# Attend que le conteneur soit libéré par les script upgrade ou switch, le cas échéant.
done

# Vérifie l'état des machines.
if ynh_lxc_is_started --name=$lxc_name1
then	# Si la machine 1 est démarrée.
	LXC_A=$lxc_name1
	IP_A="$lxdbr_demo_network$lxc_ip1"
	LXC_B=$lxc_name2
	IP_B="$lxdbr_demo_network$lxc_ip2"
else	# Sinon, on suppose que c'est la machine 2 qui est en cours.
	LXC_A=$lxc_name2
	IP_A="$lxdbr_demo_network$lxc_ip2"
	LXC_B=$lxc_name1
	IP_B="$lxdbr_demo_network$lxc_ip1"
	# Si aucune machine ne tourne, la première démarrera.
fi

# Supprime les éventuels swap présents.
/sbin/swapoff /var/lib/lxd/$LXC_A/rootfs/swap_*

ynh_print_info --message="> Starting $LXC_B"
# Démarre le conteneur B et arrête le conteneur A.
ynh_lxc_start_as_demo --name=$LXC_B --ip=$IP_B
sleep 5	# Attend 10 seconde pour s'assurer du démarrage de la machine.
if ! ynh_lxc_is_started --name=$LXC_B
then
	# Le conteneur n'a pas réussi à démarrer. On averti un responsable par mail...
	ynh_print_info --message="> Échec du démarrage du conteneur $LXC_B sur le serveur de demo $DOMAIN! \n\nExtrait du log:\n$(tail -n +$log_line "$final_path/demo_switch.log")\n\nLe script 'demo_restore_crash.sh' va être exécuté pour tenter de fixer l'erreur." | mail -a "Content-Type: text/plain; charset=UTF-8" -s "Demo Yunohost" $MAIL_ADDR
	/bin/bash $final_path/demo_restore_crash.sh &
	exit 1
else
	ynh_print_info --message="> Stopping $LXC_A"
	# Bascule sur le conteneur B avec le load balancing de nginx...
	# Automatique par nginx lorsque la machine A sera éteinte.
	# Arrêt du conteneur A. Il est remplacé par le B
	touch /var/lib/lxd/$LXC_A.lock_fileS	# Met en place un fichier pour indiquer que la machine n'est pas encore dispo.
	ynh_lxc_stop_as_demo --name=$LXC_A
	# Supprime les éventuels swap présents.
	/sbin/swapoff /var/lib/lxd/$LXC_A/rootfs/swap_*
	ynh_print_info --message="> Restauring $LXC_A from snapshot"
	# Restaure le snapshot de la machine A avant sa prochaine exécution
	ynh_lxc_load_snapshot --name=$LXC_A --snapname=snap0
	ynh_lxc_stop --name=$LXC_A
	ynh_secure_remove --file="/var/lib/lxd/$LXC_A.lock_fileS"	# Libère le lock
	ynh_print_info --message="> Finish restoring $LXC_A"
fi

date | tee -a "$final_path/demo_switch.log" 2>&1
ynh_print_info --message=">> Finished switching demo." | tee -a "$final_path/demo_switch.log" 2>&1
