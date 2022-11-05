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

/bin/bash "$final_path/demo_lxc_destroy.sh"

# Suppression du reverse proxy
echo -e "> Suppression de la config nginx"
sudo rm /etc/nginx/conf.d/$DOMAIN.conf
sudo service nginx reload

# Suppression du certificat Let's encrypt
echo -e "> Suppression de Let's encrypt"
sudo rm -r /etc/letsencrypt
sudo rm -r ~/.local/share/letsencrypt
sudo rm -r ~/letsencrypt
sudo rm -r /var/lib/letsencrypt
# Supprime la tache cron
sudo rm /etc/cron.weekly/Certificate_Renewer
