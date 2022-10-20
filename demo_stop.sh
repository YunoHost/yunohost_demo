#!/bin/bash

# Stoppe les conteneurs de demo et arrête la config réseau dédiée.

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(ynh_print_info --message=$PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

source $script_dir/ynh_lxd
source /usr/share/yunohost/helpers

app=${__APP__:-yunohost_demo}
final_path=$(ynh_app_setting_get --app=$app --key=final_path)
lxc_name1=$(ynh_app_setting_get --app=$app --key=lxc_name1)
lxc_name2=$(ynh_app_setting_get --app=$app --key=lxc_name2)

date | tee -a "$final_path/demo_boot.log" 2>&1
ynh_print_info --message=">> Stopping demo." | tee -a "$final_path/demo_boot.log" 2>&1

if [ "$#" -eq 1 ] && [ "$1" == "-f" ]
then
	ynh_print_info --message="> Deleting locks and force stopping LXC containers." | tee -a "$final_path/demo_boot.log" 2>&1
	ynh_exec_warn_less ynh_secure_remove --file="/var/lib/lxd/$lxc_name1.lock_fileS"
	ynh_exec_warn_less ynh_secure_remove --file="/var/lib/lxd/$lxc_name2.lock_fileS"
	ynh_exec_warn_less ynh_secure_remove --file="/var/lib/lxd/$lxc_name1.lock_fileU"
	ynh_exec_warn_less ynh_secure_remove --file="/var/lib/lxd/$lxc_name2.lock_fileU"
else
	ynh_print_info --message="> Waiting locks." | tee -a "$final_path/demo_boot.log" 2>&1
	while test -e /var/lib/lxd/$lxc_name1.lock_file* || test -e /var/lib/lxd/$lxc_name2.lock_file*; do
		sleep 5	# Attend que les conteneur soit libérés par les script upgrade ou switch, le cas échéant.
	done
fi

ynh_print_info --message="> Stopping LXC containers" | tee -a "$final_path/demo_boot.log" 2>&1
if ynh_lxc_exists --name=$lxc_name1
then
	if ! ynh_lxc_is_stopped --name=$lxc_name1
	then
		ynh_print_info --message="> Stopping $lxc_name1 LXC container" | tee -a "$final_path/demo_boot.log" 2>&1
		ynh_lxc_stop_as_demo --name=$lxc_name1
	fi
fi
if ynh_lxc_exists --name=$lxc_name2
then
	if ! ynh_lxc_is_stopped --name=$lxc_name2
	then
		ynh_print_info --message="> Stopping $lxc_name2 LXC container"
		ynh_lxc_stop_as_demo --name=$lxc_name2
	fi
fi

date | tee -a "$final_path/demo_boot.log" 2>&1
ynh_print_info --message=">> Finished stopping demo." | tee -a "$final_path/demo_boot.log" 2>&1
