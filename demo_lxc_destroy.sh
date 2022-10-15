#!/bin/bash

# Détruit les conteneurs lxc de demo.
# Permet de repartir sur des bases saines avec le script demo_lxc_build.sh

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

source $script_dir/ynh_lxd
source /usr/share/yunohost/helpers

app=${__APP__:-yunohost_demo}
final_path=$(ynh_app_setting_get --app=$app --key=final_path)
lxc_name1=$(ynh_app_setting_get --app=$app --key=lxc_name1)
lxc_name2=$(ynh_app_setting_get --app=$app --key=lxc_name2)
lxdbr_demo_network=$(ynh_app_setting_get --app=$app --key=lxdbr_demo_network)
lxc_ip1=$(ynh_app_setting_get --app=$app --key=lxc_ip1)
lxc_ip2=$(ynh_app_setting_get --app=$app --key=lxc_ip2)

ynh_print_info --message=">> Starting demo destroy."

/bin/bash "$final_path/demo_stop.sh" -f

ynh_print_info --message="> Deleting containers and snapshots"
ynh_secure_remove --file="/var/lib/lxd/snapshots/$lxc_name1/snap0.tar.gz"
ynh_lxc_delete --name=$lxc_name1
ynh_secure_remove --file="/var/lib/lxd/snapshots/$lxc_name2/snap0.tar.gz"
ynh_lxc_delete --name=$lxc_name2

ynh_print_info --message="> Deleting crons"
ynh_secure_remove --file=/etc/cron.d/demo_switch
ynh_secure_remove --file=/etc/cron.d/demo_upgrade

ynh_print_info --message="> Deleting service"
if ynh_exec_warn_less yunohost service status $app >/dev/null
then
	ynh_print_info --message="> Removing $app service integration..."
	yunohost service remove $app
fi
ynh_print_info --message="> Stopping and removing the systemd service..."
ynh_remove_systemd_config

ynh_print_info --message=">> Finished demo destroy."
