#!/bin/bash

# Script d'upgrade des 2 conteneurs de demo.
# Ce script n'a vocation qu'a être dans un cron

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

source $script_dir/ynh_lxd
source $script_dir/ynh_lxd_demo
source /usr/share/yunohost/helpers

app=${__APP__:-yunohost_demo}
final_path=$(ynh_app_setting_get --app=$app --key=final_path)
domain=$(ynh_app_setting_get --app=$app --key=domain)
lxc_name1=$(ynh_app_setting_get --app=$app --key=lxc_name1)
lxc_name2=$(ynh_app_setting_get --app=$app --key=lxc_name2)
time_to_switch=$(ynh_app_setting_get --app=$app --key=time_to_switch)

IP_UPGRADE=$lxdbr_demo_network.150
LOOP=0

log_line=$(wc -l "$final_path/demo_upgrade.log" | cut -d ' ' -f 1)	# Repère la fin du log actuel. Pour récupérer les lignes ajoutées sur cette exécution.
log_line=$(( $log_line + 1 ))	# Ignore la première ligne, reprise de l'ancien log.
date >> "$final_path/demo_upgrade.log"


ynh_print_info --message="Starting upgrade..."
date
ynh_lxc_upgrade_demo  --name=$lxc_name1 --time_to_switch=$time_to_switch
ynh_lxc_upgrade_demo  --name=$lxc_name2 --time_to_switch=$time_to_switch
ynh_print_info --message="Upgrade finished..."
