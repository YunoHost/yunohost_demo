#!/bin/bash

# Stoppe les conteneurs de demo et arrête la config réseau dédiée.

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(ynh_print_info --message=$PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

source $script_dir/ynh_lxd
source $script_dir/ynh_lxd_demo
source /usr/share/yunohost/helpers

app=${__APP__:-yunohost_demo}
final_path=$(ynh_app_setting_get --app=$app --key=final_path)
lxc_name1=$(ynh_app_setting_get --app=$app --key=lxc_name1)
lxc_name2=$(ynh_app_setting_get --app=$app --key=lxc_name2)

if [ "$#" -eq 1 ] && [ "$1" == "-f" ]
then
	ynh_print_info --message="> Suppression des lock et arrêt forcé des conteneurs."
	ynh_secure_remove --file="/var/lib/lxd/$lxc_name1.lock_fileS"
	ynh_secure_remove --file="/var/lib/lxd/$lxc_name2.lock_fileS"
	ynh_secure_remove --file="/var/lib/lxd/$lxc_name1.lock_fileU"
	ynh_secure_remove --file="/var/lib/lxd/$lxc_name2.lock_fileU"
else
	ynh_print_info --message="> Attend la libération des lock sur les conteneurs."
	while test -e /var/lib/lxd/$lxc_name1.lock_file* || test -e /var/lib/lxd/$lxc_name2.lock_file*; do
		sleep 5	# Attend que les conteneur soit libérés par les script upgrade ou switch, le cas échéant.
	done
fi

ynh_print_info --message="> Arrêt des conteneurs"
if ! ynh_lxc_is_stopped --name=$lxc_name1
then
	ynh_print_info --message="Arrêt du conteneur $lxc_name1"
	ynh_lxc_stop_as_demo --name=$lxc_name1
fi
if ! ynh_lxc_is_stopped --name=$lxc_name2
then
	ynh_print_info --message="Arrêt du conteneur $lxc_name2"
	ynh_lxc_stop_as_demo --name=$lxc_name2
fi
