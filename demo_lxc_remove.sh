#!/bin/bash

# Purge l'ensemble de la config lxc pour les conteneurs de demo.
# Il sera nécessaire de lancer le script demo_lxc_build_init.sh pour réinstaller l'ensemble le cas échéant.

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

source $script_dir/ynh_lxd
source $script_dir/ynh_lxd_demo
source /usr/share/yunohost/helpers

app=${__APP__:-yunohost_demo}
final_path=$(ynh_app_setting_get --app=$app --key=final_path)
lxc_name1=$(ynh_app_setting_get --app=$app --key=lxc_name1)
path_url=$(ynh_app_setting_get --app=$app --key=path)

echo_bold () {
	echo -e "\e[1m$1\e[0m"
}

# -----------------------------------------------------------------

function remove_yunohost_demo() {
	echo_bold "> Installation of yunohost_demo..."
	if yunohost app list --output-as json --quiet | jq -e '.apps[] | select(.id == "yunohost_demo")' >/dev/null
	then
		yunohost app remove yunohost_demo --purge
	fi
}

# =========================
#  Main stuff
# =========================

remove_yunohost_demo

echo "Done!"
echo " "
