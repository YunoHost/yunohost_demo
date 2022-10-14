#!/bin/bash

# Tente de réparer les conteneurs LXC à partir des snapshots et des sauvegardes.

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

source $script_dir/ynh_lxd
source $script_dir/ynh_lxd_demo
source /usr/share/yunohost/helpers

app=${__APP__:-yunohost_demo}
final_path=$(ynh_app_setting_get --app=$app --key=final_path)
lxdbr_demo_network=$(ynh_app_setting_get --app=$app --key=lxdbr_demo_network)
lxc_ip1=$(ynh_app_setting_get --app=$app --key=lxc_ip1)
lxc_ip2=$(ynh_app_setting_get --app=$app --key=lxc_ip2)
lxc_name1=$(ynh_app_setting_get --app=$app --key=lxc_name1)
lxc_name2=$(ynh_app_setting_get --app=$app --key=lxc_name2)

ynh_print_info --message="Désactive le cron switch."
sed -i "s/.*demo_switch.sh/#&/" /etc/cron.d/demo_switch	# Le cron est commenté durant l'opération de maintenance.

ynh_print_info --message="Suppression des lock et arrêt forcé des conteneurs."
ynh_secure_remove --file="/var/lib/lxd/$lxc_name1.lock_fileS"
ynh_secure_remove --file="/var/lib/lxd/$lxc_name2.lock_fileS"
ynh_secure_remove --file="/var/lib/lxd/$lxc_name1.lock_fileU"
ynh_secure_remove --file="/var/lib/lxd/$lxc_name2.lock_fileU"

ynh_lxc_stop_as_demo --name="$lxc_name1"
ynh_lxc_stop_as_demo --name="$lxc_name2"

# Vérifie l'état des conteneurs.
ynh_lxc_check_container_start --name=$lxc_name1
LXC1_STATUS=$?
ynh_lxc_check_container_start --name=$lxc_name2
LXC2_STATUS=$?

if [ $LXC1_STATUS -eq 1 ]; then
	ynh_print_info --message="> Conteneur $lxc_name1 en défaut."
else
	ynh_print_info --message="> Conteneur $lxc_name1 en état de marche."
fi
if [ $LXC2_STATUS -eq 1 ]; then
	ynh_print_info --message="> Conteneur $lxc_name2 en défaut."
else
	ynh_print_info --message="> Conteneur $lxc_name2 en état de marche."
fi

# Restauration des snapshots
if [ $LXC1_STATUS -eq 1 ]; then
	ynh_lxc_restore_from_snapshot  --name=$lxc_name1
	LXC1_STATUS=$?
fi
if [ $LXC2_STATUS -eq 1 ]; then
	ynh_lxc_restore_from_snapshot  --name=$lxc_name2
	LXC2_STATUS=$?
fi

# Restauration des archives des snapshots
if [ $LXC1_STATUS -eq 1 ]; then
	ynh_lxc_restore_from_archive  --name=$lxc_name1
	LXC1_STATUS=$?
fi
if [ $LXC2_STATUS -eq 1 ]; then
	ynh_lxc_restore_from_archive  --name=$lxc_name2
	LXC2_STATUS=$?
fi

# Si des erreurs persistent, tente de cloner depuis un conteneur sain
if [ $LXC1_STATUS -eq 1 ] && [ $LXC2_STATUS -eq 0 ] ; then
	ynh_lxc_clone --source=$lxc_name2 --destination=$lxc_name1
	LXC1_STATUS=$?
fi
if [ $LXC2_STATUS -eq 1 ] && [ $LXC1_STATUS -eq 0 ]; then
	ynh_lxc_clone --source=$lxc_name1 --destination=$lxc_name2
	LXC2_STATUS=$?
fi

# Résultats finaux
if [ $LXC1_STATUS -eq 1 ] || [ $LXC2_STATUS -eq 1 ]; then
	if [ $LXC1_STATUS -eq 1 ]; then
		ynh_print_info --message="> Le conteneur $lxc_name1 n'a pas pu être réparé..."
	fi
	if [ $LXC2_STATUS -eq 1 ]; then
		ynh_print_info --message="> Le conteneur $lxc_name2 n'a pas pu être réparé..."
	fi
else
	ynh_print_info --message="> Les 2 conteneurs sont sains et fonctionnels."
fi

ynh_print_info --message="Réactive le cron switch."
sed -i "s/#*\*/\*/" /etc/cron.d/demo_switch	# Le cron est décommenté
ynh_print_info --message="Restart la demo."
$final_path/demo_start.sh
