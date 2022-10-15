#!/bin/bash

# Démarre le premier conteneur de demo

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

source $script_dir/ynh_lxd
source $script_dir/ynh_lxd_demo
source /usr/share/yunohost/helpers

app=${__APP__:-yunohost_demo}
final_path=$(ynh_app_setting_get --app=$app --key=final_path)
lxc_name1=$(ynh_app_setting_get --app=$app --key=lxc_name1)
lxdbr_demo_network=$(ynh_app_setting_get --app=$app --key=lxdbr_demo_network)
lxc_ip1=$(ynh_app_setting_get --app=$app --key=lxc_ip1)

date | tee -a "$final_path/demo_boot.log" 2>&1
ynh_print_info --message=">> Starting demo." | tee -a "$final_path/demo_boot.log" 2>&1

/bin/bash "$final_path/demo_stop.sh" > /dev/null 2>&1

# Démarrage de la machine
ynh_print_info --message="> Démarrage de la machine" | tee -a "$final_path/demo_boot.log" 2>&1
date | tee -a "$final_path/demo_boot.log" 2>&1
ynh_print_info --message="> Starting $lxc_name1" | tee -a "$final_path/demo_boot.log" 2>&1
ynh_lxc_start_as_demo --name=$lxc_name1 --ip="$lxdbr_demo_network$lxc_ip1"  | tee -a "$final_path/demo_boot.log" 2>&1
sleep 3

date | tee -a "$final_path/demo_boot.log" 2>&1
ynh_print_info --message=">> Finished starting demo." | tee -a "$final_path/demo_boot.log" 2>&1
