#!/bin/bash

# Créer les conteneurs Yunohost et les configure

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

source $script_dir/ynh_lxd
source $script_dir/ynh_lxd_demo
source /usr/share/yunohost/helpers

app=${__APP__:-yunohost_demo}
final_path=$(ynh_app_setting_get --app=$app --key=final_path)
domain=$(ynh_app_setting_get --app=$app --key=domain)
path_url=$(ynh_app_setting_get --app=$app --key=path)
lxdbr_demo_name=$(ynh_app_setting_get --app=$app --key=lxdbr_demo_name)
lxdbr_demo_network=$(ynh_app_setting_get --app=$app --key=lxdbr_demo_network)
lxc_ip1=$(ynh_app_setting_get --app=$app --key=lxc_ip1)
lxc_ip2=$(ynh_app_setting_get --app=$app --key=lxc_ip2)
demo_user=$(ynh_app_setting_get --app=$app --key=demo_user)
demo_password=$(ynh_app_setting_get --app=$app --key=demo_password)
demo_package=$(ynh_app_setting_get --app=$app --key=demo_package)
yunohost_password="$demo_password"
lxc_name1=$(ynh_app_setting_get --app=$app --key=lxc_name1)
lxc_name2=$(ynh_app_setting_get --app=$app --key=lxc_name2)
time_to_switch=$(ynh_app_setting_get --app=$app --key=time_to_switch)
DIST=$(ynh_app_setting_get --app=$app --key=DIST)
ARCH=$(ynh_app_setting_get --app=$app --key=ARCH)
YNH_BRANCH=$(ynh_app_setting_get --app=$app --key=YNH_BRANCH)
lxc_base="ynh-dev-$DIST-$ARCH-$YNH_BRANCH-base"

LOG=Build_lxc.log
LOG_BUILD_LXC="$final_path/$LOG"

if $(ynh_lxc_exists --name="$name")
then	# Si le conteneur existe déjà
	ynh_print_info --message="> Suppression du conteneur existant." | tee -a "$LOG_BUILD_LXC"
	/bin/bash "$final_path/demo_lxc_destroy.sh" quiet | tee -a "$LOG_BUILD_LXC"
fi

ynh_print_info --message="> Création d'une machine debian $DIST minimaliste" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_create --image="$lxc_base" --name="$lxc_name1" | tee -a "$LOG_BUILD_LXC" 2>&1

ynh_print_info --message= "> Active le bridge réseau" | tee -a "$LOG_BUILD_LXC"
lxc network attach $lxdbr_demo_name $lxc_name1 eth1 eth1 | tee -a "$LOG_BUILD_LXC" 2>&1

ynh_print_info --message="> Configuration réseau de la machine virtualisée" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="cp /etc/systemd/network/eth0.network /etc/systemd/network/eth1.network"
ynh_lxc_run_inside --name="$lxc_name1" --command="sed -i s/eth0/eth1/g /etc/systemd/network/eth1.network"

ynh_print_info --message="> Update de la machine virtualisée" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="apt-get -y update"
ynh_lxc_run_inside --name="$lxc_name1" --command="apt-get -y full-upgrade"
ynh_lxc_run_inside --name="$lxc_name1" --command="apt-get -y autoremove"
ynh_lxc_run_inside --name="$lxc_name1" --command="apt-get -y clean"

ynh_print_info --message="> Post install Yunohost" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost tools postinstall --domain $domain --password $yunohost_password --force-password" | tee -a "$LOG_BUILD_LXC" 2>&1

ynh_print_info --message="> Disable password strength" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost settings set security.password.user.strength -v -1" | tee -a "$LOG_BUILD_LXC"

ynh_print_info --message="> Ajout de l'utilisateur de demo" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost user create $demo_user --firstname $demo_user --lastname $demo_user --domain $domain --password $demo_password" | tee -a "$LOG_BUILD_LXC"

ynh_print_info --message="> Vérification de l'état de Yunohost" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost -v" | tee -a "$LOG_BUILD_LXC" 2>&1

# ********
ynh_print_info --message="> Modification de Yunohost pour la demo" | tee -a "$LOG_BUILD_LXC"

if [ ! -z "$PACKAGE_CHECK_EXEC" ]
then
# App officielles
ynh_print_info --message="> Installation des applications officielles" | tee -a "$LOG_BUILD_LXC"
# Ampache
ynh_print_info --message="Installation de Ampache" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost app install ampache --force --args \"domain=$domain&path=/ampache&admin=$demo_user&is_public=1&\"" | tee -a "$LOG_BUILD_LXC"
# Baikal
ynh_print_info --message="Installation de baikal" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost app install baikal --force --args \"domain=$domain&path=/baikal&password=$demo_password&\"" | tee -a "$LOG_BUILD_LXC"
# Agendav
ynh_print_info --message="Installation d'agendav" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost app install agendav --force --args \"domain=$domain&path=/agendav&language=en&\"" | tee -a "$LOG_BUILD_LXC"
# Dokuwiki
ynh_print_info --message="Installation de dokuwiki" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost app install dokuwiki --force --args \"domain=$domain&path=/dokuwiki&admin=$demo_user&is_public=1&language=en&\"" | tee -a "$LOG_BUILD_LXC"
# Etherpad
ynh_print_info --message="Installation de etherpad" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost app install etherpad_mypads --force --args \"domain=$domain&path=/etherpad&admin=$demo_user&password=administration&language=en&is_public=1&export=none&mypads=1&useldap=0&\"" | tee -a "$LOG_BUILD_LXC"
# Hextris
ynh_print_info --message="Installation de hextris" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost app install hextris --force --args \"domain=$domain&path=/hextris&is_public=1&\"" | tee -a "$LOG_BUILD_LXC"
# Jirafeau
ynh_print_info --message="Installation de jirafeau" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost app install jirafeau --force --args \"domain=$domain&path=/jirafeau&admin_user=$demo_user&upload_password=$demo_password&is_public=1&\"" | tee -a "$LOG_BUILD_LXC"
# Kanboard
ynh_print_info --message="Installation de kanboard" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost app install kanboard --force --args \"domain=$domain&path=/kanboard&admin=$demo_user&is_public=1&\"" | tee -a "$LOG_BUILD_LXC"
# Nextcloud
ynh_print_info --message="Installation de nextcloud" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost app install nextcloud --force --args \"domain=$domain&path=/nextcloud&admin=$demo_user&user_home=0&is_public=1&\"" | tee -a "$LOG_BUILD_LXC"
# Opensondage
ynh_print_info --message="Installation de opensondage" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost app install opensondage --force --args \"domain=$domain&path=/date&admin=$demo_user&language=en&is_public=1&\"" | tee -a "$LOG_BUILD_LXC"
# Phpmyadmin
ynh_print_info --message="Installation de phpmyadmin" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost app install phpmyadmin --force --args \"domain=$domain&path=/phpmyadmin&admin=$demo_user&\"" | tee -a "$LOG_BUILD_LXC"
# Piwigo
ynh_print_info --message="Installation de piwigo" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost app install piwigo --force --args \"domain=$domain&path=/piwigo&admin=$demo_user&is_public=1&language=en&\"" | tee -a "$LOG_BUILD_LXC"
# Rainloop
ynh_print_info --message="Installation de rainloop" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost app install rainloop --force --args \"domain=$domain&path=/rainloop&is_public=No&password=$demo_password&ldap=Yes&language=en&\""  | tee -a "$LOG_BUILD_LXC"
# Roundcube
ynh_print_info --message="Installation de roundcube" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost app install roundcube --force --args \"domain=$domain&path=/webmail&with_carddav=0&with_enigma=0&language=en_GB&\"" | tee -a "$LOG_BUILD_LXC"
# Searx
ynh_print_info --message="Installation de searx" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost app install searx --force --args \"domain=$domain&path=/searx&is_public=1&\"" | tee -a "$LOG_BUILD_LXC"
# Shellinabox
ynh_print_info --message="Installation de shellinabox" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost app install shellinabox --force --args \"domain=$domain&path=/ssh&\"" | tee -a "$LOG_BUILD_LXC"
# Désactive l'accès à shellinabox
ynh_lxc_run_inside --name="$lxc_name1" --command="rm /etc/nginx/conf.d/$domain.d/shellinabox.conf"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost app setting shellinabox path -d"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost app setting shellinabox domain -d"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost app ssowatconf"
# Strut
ynh_print_info --message="Installation de strut" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost app install strut --force --args \"domain=$domain&path=/strut&is_public=1&\"" | tee -a "$LOG_BUILD_LXC"
# Transmission
ynh_print_info --message="Installation de transmission" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost app install transmission --force --args \"domain=$domain&path=/torrent&\"" | tee -a "$LOG_BUILD_LXC"
# Ttrss
ynh_print_info --message="Installation de ttrss" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost app install ttrss --force --args \"domain=$domain&path=/ttrss&is_public=1&\"" | tee -a "$LOG_BUILD_LXC"
# Wallabag
ynh_print_info --message="Installation de wallabag" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost app install wallabag2 --force --args \"domain=$domain&path=/wallabag&admin=$demo_user&\"" | tee -a "$LOG_BUILD_LXC"
# Wordpress
ynh_print_info --message="Installation de wordpress" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost app install wordpress --force --args \"domain=$domain&path=/blog&admin=$demo_user&language=en_US&multisite=0&is_public=1&\"" | tee -a "$LOG_BUILD_LXC"
# Zerobin
ynh_print_info --message="Installation de zerobin" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_run_inside --name="$lxc_name1" --command="yunohost app install zerobin --force --args \"domain=$domain&path=/zerobin&is_public=1&\"" | tee -a "$LOG_BUILD_LXC"
fi
# ********

ynh_print_info --message="> Création d'un snapshot" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_create_snapshot --name="$lxc_name1" --snapname="snap0"

ynh_print_info --message="> Mise à jour de la machine virtualisée" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_stop --name="$lxc_name1" | tee -a "$LOG_BUILD_LXC" 2>&1
ynh_lxc_upgrade_demo --name=$lxc_name1 --time_to_switch=$time_to_switch

ynh_print_info --message="> Clone la machine" | tee -a "$LOG_BUILD_LXC"
lxc copy "$lxc_name1" "$lxc_name2" | tee -a "$LOG_BUILD_LXC" 2>&1

ynh_print_info --message="> Création d'un snapshot" | tee -a "$LOG_BUILD_LXC"
ynh_lxc_create_snapshot --name="$lxc_name2" --snapname="snap0"

ynh_print_info --message="> Mise en place du cron de switch" | tee -a "$LOG_BUILD_LXC"
ynh_add_config --template="$final_path/conf/cron_demo_switch" --destination="/etc/cron.d/demo_switch"

ynh_print_info --message="> Et du cron d'upgrade" | tee -a "$LOG_BUILD_LXC"
ynh_add_config --template="$final_path/conf/cron_demo_upgrade" --destination="/etc/cron.d/demo_upgrade"

ynh_print_info --message="> Mise en place du service" | tee -a "$LOG_BUILD_LXC"
#ynh_add_systemd_config --template="$final_path/conf/systemd.service"
ynh_add_systemd_config

ynh_print_info --message="> Integrating service in YunoHost..." | tee -a "$LOG_BUILD_LXC"
yunohost service add $app --log="/var/log/$app/$app.log"

ynh_print_info --message="> Starting a systemd service..." | tee -a "$LOG_BUILD_LXC"
ynh_systemd_action --service_name=$app --action="start" --log_path="systemd"
