#!/bin/bash

# Créer les conteneurs Yunohost et les configure

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

LOG=Build_lxc.log
LOG_BUILD_LXC="$script_dir/$LOG"
PLAGE_IP=10.1.5
IP_LXC1=10.1.5.3
IP_LXC2=10.1.5.4
ARG_SSH=-t
DOMAIN=$(cat "$script_dir/domain.ini")
YUNO_PWD=demo
LXC_NAME1=yunohost_demo1
LXC_NAME2=yunohost_demo2
TIME_TO_SWITCH=30
DIST="bullseye"
 # En minutes
MAIL_ADDR=demo@yunohost.org
dnsforce=0
main_iface=
dns=

lxc_current_version=$(lxc-info --version)

if $(dpkg --compare-versions "$lxc_current_version" "gt" "3.0.0"); then new_lxc=1; else new_lxc=0; fi

USER_DEMO=demo
PASSWORD_DEMO=demo

# Tente de définir l'interface réseau principale
if [ -z $main_iface ]	# Si main_iface est vide, tente de le trouver.
then
# 	main_iface=$(sudo route | grep default.*0.0.0.0 -m1 | awk '{print $8;}')	# Prend l'interface réseau défini par default
	main_iface=$(sudo ip route | grep default | awk '{print $5;}')	# Prend l'interface réseau défini par default
	if [ -z $main_iface ]; then
		echo -e "\e[91mImpossible de déterminer le nom de l'interface réseau de l'hôte.\e[0m"
		exit 1
	fi
fi

if [ -z $dns ]	# Si l'adresse du dns est vide, tente de le déterminer à partir de la passerelle par défaut.
then
# 	dns=$(sudo route -n | grep ^0.0.0.0.*$main_iface | awk '{print $2;}')
	dns=$(sudo ip route | grep default | awk '{print $3;}')
	if [ -z $dns ]; then
		echo -e "\e[91mImpossible de déterminer l'adresse de la passerelle.\e[0m"
		exit 1
	fi
fi

# Check user
if [ "$USER" != "$(cat "$script_dir/setup_user")" ] && test -e "$script_dir/setup_user"; then
	echo -e "\e[91mCe script doit être exécuté avec l'utilisateur $(cat "$script_dir/setup_user")"
	echo -en "\e[0m"
	exit 0
fi

sudo mkdir -p /var/lib/lxcsnaps	# Créer le dossier lxcsnaps, pour s'assurer que lxc utilisera ce dossier, même avec lxc 2.

if sudo lxc-info -n $LXC_NAME1 > /dev/null 2>&1
then	# Si le conteneur existe déjà
	echo -e "\e[1m> Suppression du conteneur existant.\e[0m" | tee -a "$LOG_BUILD_LXC"
	"$script_dir/demo_lxc_destroy.sh" quiet | tee -a "$LOG_BUILD_LXC"
fi

echo -e "\e[1m> Création d'une machine debian $DIST minimaliste\e[0m" | tee -a "$LOG_BUILD_LXC"
sudo lxc-create -n $LXC_NAME1 -t debian -- -r $DIST >> "$LOG_BUILD_LXC" 2>&1

echo -e "\e[1m> Active le bridge réseau\e[0m" | tee -a "$LOG_BUILD_LXC"
sudo ifup lxc_demo --interfaces=/etc/network/interfaces.d/lxc_demo >> "$LOG_BUILD_LXC" 2>&1

echo -e "\e[1m> Configuration réseau du conteneur\e[0m" | tee -a "$LOG_BUILD_LXC"
if [ $new_lxc -eq 1 ]; then
	sudo sed -i "s/^lxc.net.0.link = lxcbr0$/lxc.net.0.link = lxc_demo\nlxc.net.0.name = eth0\nlxc.net.0.veth.pair = $LXC_NAME1/" /var/lib/lxc/$LXC_NAME1/config >> "$LOG_BUILD_LXC" 2>&1
else
	sudo sed -i "s/^lxc.net.0.type = empty$/lxc.net.0.type = veth\nlxc.net.0.flags = up\nlxc.net.0.link = lxc_demo\nlxc.net.0.name = eth0\nlxc.net.0.veth.pair = $LXC_NAME1\nlxc.net.0.hwaddr = 00:FF:AA:00:00:03/" /var/lib/lxc/$LXC_NAME1/config >> "$LOG_BUILD_LXC" 2>&1
fi

echo -e "\e[1m> Configuration réseau de la machine virtualisée\e[0m" | tee -a "$LOG_BUILD_LXC"
sudo sed -i "s@iface eth0 inet dhcp@iface eth0 inet static\n\taddress $IP_LXC1/24\n\tgateway $PLAGE_IP.1@" /var/lib/lxc/$LXC_NAME1/rootfs/etc/network/interfaces >> "$LOG_BUILD_LXC" 2>&1

echo -e "\e[1m> Configure le parefeu\e[0m" | tee -a "$LOG_BUILD_LXC"
sudo iptables -A FORWARD -i lxc_demo -o eth0 -j ACCEPT >> "$LOG_BUILD_LXC" 2>&1
sudo iptables -A FORWARD -i eth0 -o lxc_demo -j ACCEPT >> "$LOG_BUILD_LXC" 2>&1
sudo iptables -t nat -A POSTROUTING -s $PLAGE_IP.0/24 -j MASQUERADE >> "$LOG_BUILD_LXC" 2>&1

echo -e "\e[1m> Vérification du contenu du resolv.conf\e[0m" | tee -a "$LOG_BUILD_LXC"
if ! sudo cat /var/lib/lxc/$LXC_NAME1/rootfs/etc/resolv.conf | grep -q nameserver; then
	dnsforce=1	# Le resolv.conf est vide, on force l'ajout d'un dns.
fi
if [ $dnsforce -eq 1 ]; then	# Force la réécriture du resolv.conf
	echo "nameserver $dns" | sudo tee /var/lib/lxc/$LXC_NAME1/rootfs/etc/resolv.conf
fi

# Fix an issue with apparmor when the container start.
if [ $new_lxc -eq 1 ]; then
	sudo sed -i "s/^lxc.apparmor.profile = generated$/lxc.apparmor.profile = unconfined/" /var/lib/lxc/$LXC_NAME1/config >> "$LOG_BUILD_LXC" 2>&1
else
	echo -e "\n# Fix apparmor issues\nlxc.aa_profile = unconfined" | sudo tee -a /var/lib/lxc/$LXC_NAME1/config >> "$LOG_BUILD_LXC" 2>&1
fi

echo -e "\e[1m> Démarrage de la machine\e[0m" | tee -a "$LOG_BUILD_LXC"
sudo lxc-start -n $LXC_NAME1 -d --logfile "$script_dir/lxc_boot.log" >> "$LOG_BUILD_LXC" 2>&1
sleep 3
sudo lxc-ls -f >> "$LOG_BUILD_LXC" 2>&1

echo -e "\e[1m> Update et install aptitude sudo aptitude sudo ssh openssh-server curl\e[0m" | tee -a "$LOG_BUILD_LXC"
sudo lxc-attach -n $LXC_NAME1 -- apt-get update
sudo lxc-attach -n $LXC_NAME1 -- apt-get install -y aptitude sudo ssh openssh-server curl
echo -e "\e[1m> Installation des paquets standard et ssh-server\e[0m" | tee -a "$LOG_BUILD_LXC"
sudo lxc-attach -n $LXC_NAME1 -- aptitude install -y ~pstandard ~prequired ~pimportant

echo -e "\e[1m> Renseigne /etc/hosts sur l'invité\e[0m" | tee -a "$LOG_BUILD_LXC"
echo "127.0.0.1 $LXC_NAME1" | sudo tee -a /var/lib/lxc/$LXC_NAME1/rootfs/etc/hosts >> "$LOG_BUILD_LXC" 2>&1

echo -e "\e[1m> Ajoute l'user ssh_demo (avec un mot de passe à revoir...)\e[0m" | tee -a "$LOG_BUILD_LXC"
sudo lxc-attach -n $LXC_NAME1 -- useradd -m -p ssh_demo ssh_demo >> "$LOG_BUILD_LXC" 2>&1

echo -e "\e[1m> Autorise ssh_demo à utiliser sudo sans mot de passe\e[0m" | tee -a "$LOG_BUILD_LXC"
echo "ssh_demo    ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee -a /var/lib/lxc/$LXC_NAME1/rootfs/etc/sudoers >> "$LOG_BUILD_LXC" 2>&1

echo -e "\e[1m> Mise en place de la connexion ssh vers l'invité.\e[0m" | tee -a "$LOG_BUILD_LXC"
sudo mkdir /var/lib/lxc/$LXC_NAME1/rootfs/home/ssh_demo/.ssh >> "$LOG_BUILD_LXC" 2>&1
sudo cp $HOME/.ssh/$LXC_NAME1.pub /var/lib/lxc/$LXC_NAME1/rootfs/home/ssh_demo/.ssh/authorized_keys >> "$LOG_BUILD_LXC" 2>&1
sudo lxc-attach -n $LXC_NAME1 -- chown ssh_demo -R /home/ssh_demo/.ssh >> "$LOG_BUILD_LXC" 2>&1

ssh -o StrictHostKeyChecking=no $ARG_SSH $LXC_NAME1 "exit 0"	# Initie une première connexion SSH pour valider la clé.
if [ "$?" -ne 0 ]; then	# Si l'utilisateur tarde trop, la connexion sera refusée... ???
	ssh $ARG_SSH $LXC_NAME1 "exit 0"	# Initie une premier connexion SSH pour valider la clé.
fi

# Fix ssh common issues with stretch "No supported key exchange algorithms"
sudo lxc-attach -n $LXC_NAME1 -- dpkg-reconfigure openssh-server  >> "$LOG_BUILD_LXC" 2>&1

# Fix locales issue
sudo lxc-attach -n $LXC_NAME1 -- locale-gen en_US.UTF-8 >> "$LOG_BUILD_LXC" 2>&1
sudo lxc-attach -n $LXC_NAME1 -- localedef -i en_US -f UTF-8 en_US.UTF-8 >> "$LOG_BUILD_LXC" 2>&1

echo -e "\e[1m> Installation de Yunohost...\e[0m" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo /bin/bash -c \"curl https://install.yunohost.org/$DIST | bash -s -- -a -d stable\"" | tee -a "$LOG_BUILD_LXC" 2>&1
echo -e "\e[1m> Disable password strength\e[0m" | tee -a "$LOG_BUILD_LXC"
sudo lxc-attach -n $LXC_NAME1 -- bash -c 'echo "admin_strength: -1" >> /etc/yunohost/settings.yml'
sudo lxc-attach -n $LXC_NAME1 -- bash -c 'echo "user_strength: -1" >> /etc/yunohost/settings.yml'
echo -e "\e[1m> Post install Yunohost\e[0m" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo systemctl start dbus.service" | tee -a "$LOG_BUILD_LXC" 2>&1
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost tools postinstall --domain $DOMAIN --username $USER_DEMO --fullname $USER_DEMO --password $YUNO_PWD" | tee -a "$LOG_BUILD_LXC" 2>&1

echo -e "\e[1m> Fix SSH access\e[0m" | tee -a "$LOG_BUILD_LXC"
sudo lxc-attach -n $LXC_NAME1 -- sed -i "s/AllowGroups ssh.main sftp.main ssh.app sftp.app admins root/AllowGroups ssh.main sftp.main ssh.app sftp.app admins root ssh_demo/" /etc/ssh/sshd_config >> "$LOG_BUILD_LXC" 2>&1
sudo lxc-attach -n $LXC_NAME1 -- service sshd restart >> "$LOG_BUILD_LXC" 2>&1

echo -e "\e[1m\n> Vérification de l'état de Yunohost\e[0m" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost --version" | tee -a "$LOG_BUILD_LXC" 2>&1

# ********
echo -e "\e[1m>> Modification de Yunohost pour la demo\e[0m" | tee -a "$LOG_BUILD_LXC"

# App officielles
echo -e "\e[1m> Installation des applications officielles\e[0m" | tee -a "$LOG_BUILD_LXC"
# Ampache
echo -e "\e[36mInstallation de Ampache\e[0m" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install ampache --force --args \"domain=$DOMAIN&path=/ampache&admin=$USER_DEMO&init_main_permission=visitors\"" | tee -a "$LOG_BUILD_LXC"
# Baikal
echo -e "\e[36mInstallation de baikal\e[0m" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install baikal --force --args \"domain=$DOMAIN&path=/baikal&password=$PASSWORD_DEMO\"" | tee -a "$LOG_BUILD_LXC"
# Agendav
echo -e "\e[36mInstallation d'agendav\e[0m" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install agendav --force --args \"domain=$DOMAIN&path=/agendav&language=en&init_main_permission=all_users\"" | tee -a "$LOG_BUILD_LXC"
# Dokuwiki
echo -e "\e[36mInstallation de dokuwiki\e[0m" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install dokuwiki --force --args \"domain=$DOMAIN&path=/dokuwiki&admin=$USER_DEMO&init_main_permission=visitors&language=en\"" | tee -a "$LOG_BUILD_LXC"
# Etherpad
echo -e "\e[36mInstallation de etherpad\e[0m" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install etherpad_mypads --force --args \"domain=$DOMAIN&path=/etherpad&admin=$USER_DEMO&password=administration&language=en&init_main_permission=visitors&export=none&mypads=1&useldap=0\"" | tee -a "$LOG_BUILD_LXC"
# Hextris
echo -e "\e[36mInstallation de hextris\e[0m" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install hextris --force --args \"domain=$DOMAIN&path=/hextris&init_main_permission=visitors\"" | tee -a "$LOG_BUILD_LXC"
# Jirafeau
echo -e "\e[36mInstallation de jirafeau\e[0m" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install jirafeau --force --args \"domain=$DOMAIN&path=/jirafeau&admin_user=$USER_DEMO&upload_password=$PASSWORD_DEMO&init_main_permission=visitors\"" | tee -a "$LOG_BUILD_LXC"
# Kanboard
echo -e "\e[36mInstallation de kanboard\e[0m" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install kanboard --force --args \"domain=$DOMAIN&path=/kanboard&admin=$USER_DEMO&init_main_permission=visitors\"" | tee -a "$LOG_BUILD_LXC"
# Nextcloud
echo -e "\e[36mInstallation de nextcloud\e[0m" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install nextcloud --force --args \"domain=$DOMAIN&path=/nextcloud&admin=$USER_DEMO&user_home=0&init_main_permission=visitors&system_addressbook_exposed=yes\"" | tee -a "$LOG_BUILD_LXC"
# Opensondage
echo -e "\e[36mInstallation de opensondage\e[0m" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install opensondage --force --args \"domain=$DOMAIN&path=/date&admin=$USER_DEMO&language=en&init_main_permission=visitors\"" | tee -a "$LOG_BUILD_LXC"
# Phpmyadmin
echo -e "\e[36mInstallation de phpmyadmin\e[0m" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install phpmyadmin --force --args \"domain=$DOMAIN&path=/phpmyadmin&admin=$USER_DEMO\"" | tee -a "$LOG_BUILD_LXC"
# Piwigo
echo -e "\e[36mInstallation de piwigo\e[0m" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install piwigo --force --args \"domain=$DOMAIN&path=/piwigo&admin=$USER_DEMO&password=$PASSWORD_DEMO&init_main_permission=visitors&language=en_UK\"" | tee -a "$LOG_BUILD_LXC"
# Roundcube
echo -e "\e[36mInstallation de roundcube\e[0m" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install roundcube --force --args \"domain=$DOMAIN&path=/webmail&with_carddav=0&with_enigma=0&language=en_GB&init_main_permission=visitors\"" | tee -a "$LOG_BUILD_LXC"
# Searx
echo -e "\e[36mInstallation de searx\e[0m" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install searx --force --args \"domain=$DOMAIN&path=/searx&init_main_permission=visitors\"" | tee -a "$LOG_BUILD_LXC"
# Shellinabox
echo -e "\e[36mInstallation de shellinabox\e[0m" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install shellinabox --force --args \"domain=$DOMAIN&path=/ssh\"" | tee -a "$LOG_BUILD_LXC"
# Strut
echo -e "\e[36mInstallation de strut\e[0m" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install strut --force --args \"domain=$DOMAIN&path=/strut&init_main_permission=visitors\"" | tee -a "$LOG_BUILD_LXC"
# Transmission
echo -e "\e[36mInstallation de transmission\e[0m" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install transmission --force --args \"domain=$DOMAIN&path=/torrent&init_main_permission=visitors\"" | tee -a "$LOG_BUILD_LXC"
# Ttrss
echo -e "\e[36mInstallation de ttrss\e[0m" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install ttrss --force --args \"domain=$DOMAIN&path=/ttrss&init_main_permission=visitors\"" | tee -a "$LOG_BUILD_LXC"
# Wallabag
echo -e "\e[36mInstallation de wallabag\e[0m" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install wallabag2 --force --args \"domain=$DOMAIN&path=/wallabag&admin=$USER_DEMO&init_main_permission=all_users\"" | tee -a "$LOG_BUILD_LXC"
# Wordpress
echo -e "\e[36mInstallation de wordpress\e[0m" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install wordpress --force --args \"domain=$DOMAIN&path=/blog&admin=$USER_DEMO&language=en_US&multisite=0&init_main_permission=visitors\"" | tee -a "$LOG_BUILD_LXC"
# Zerobin
echo -e "\e[36mInstallation de zerobin\e[0m" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install zerobin --force --args \"domain=$DOMAIN&path=/zerobin&init_main_permission=visitors\"" | tee -a "$LOG_BUILD_LXC"

# Désactive l'accès à shellinabox
sudo rm "/var/lib/lxc/$LXC_NAME1/rootfs/etc/nginx/conf.d/$DOMAIN.d/shellinabox.conf"	# Supprime le fichier de conf nginx de shellinabox pour empêcher d'y accéder.
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app setting shellinabox path -d && sudo yunohost app setting shellinabox domain -d && sudo yunohost app ssowatconf" | tee -a "$LOG_BUILD_LXC"

# Indique le couple login/mot de passe demo/demo
# Et ajoute demo/demo par défaut dans les champs d'identification
sed -i "3i\<center>Login: $USER_DEMO / Password: $PASSWORD_DEMO</center>" /var/lib/lxc/yunohost_demo1/rootfs/usr/share/ssowat/portal/login.html # Sur le login du portail
sed -i "s/id=\"user\" type=\"text\" name=\"user\"/id=\"user\" type=\"text\" name=\"user\" value=\"$USER_DEMO\"/" /var/lib/lxc/yunohost_demo1/rootfs/usr/share/ssowat/portal/login.html
sed -i "s/id=\"password\" type=\"password\" name=\"password\"/id=\"password\" type=\"password\" name=\"password\" value=\"$PASSWORD_DEMO\"/" /var/lib/lxc/yunohost_demo1/rootfs/usr/share/ssowat/portal/login.html

#sed -i "17i\&emsp;&emsp;&emsp;Password: $YUNO_PWD" /var/lib/lxc/yunohost_demo1/rootfs/usr/share/yunohost/admin/views/login.ms    # Et sur le login admin
#sed -i "s/type=\"password\" id=\"password\" name=\"password\"/type=\"password\" id=\"password\" name=\"password\" value=\"$YUNO_PWD\"/" /var/lib/lxc/yunohost_demo1/rootfs/usr/share/yunohost/admin/views/login.ms

# Désactive l'installation d'app custom
sed -i "s@<a role=\"button\" class=\"btn btn-success slide\">{{t 'install'}}</a>@<a role=\"\" class=\"btn btn-success slide\">{{t 'install'}}</a>@g" /var/lib/lxc/yunohost_demo1/rootfs/usr/share/yunohost/admin/views/app/app_catalog_category.ms

# Désactive l'ajout de domaine, pour éviter surtout les nohost
sed -i "s@<input type=\"submit\" role=\"button\" class=\"btn btn-success slide back\" value=\"{{t 'add'}}\">@<input type=\"\" role=\"\" class=\"btn btn-success slide back\" value=\"{{t 'add'}}\">@g" /var/lib/lxc/yunohost_demo1/rootfs/usr/share/yunohost/admin/views/domain/domain_add.ms

# ********

echo -e "\e[1m> Arrêt de la machine virtualisée\e[0m" | tee -a "$LOG_BUILD_LXC"
sudo lxc-stop -n $LXC_NAME1 >> "$LOG_BUILD_LXC" 2>&1

echo -e "\e[1m> Suppression des règles de parefeu\e[0m" | tee -a "$LOG_BUILD_LXC"
sudo iptables -D FORWARD -i lxc_demo -o eth0 -j ACCEPT >> "$LOG_BUILD_LXC" 2>&1
sudo iptables -D FORWARD -i eth0 -o lxc_demo -j ACCEPT >> "$LOG_BUILD_LXC" 2>&1
sudo iptables -t nat -D POSTROUTING -s $PLAGE_IP.0/24 -j MASQUERADE >> "$LOG_BUILD_LXC" 2>&1
sudo ifdown --force lxc_demo >> "$LOG_BUILD_LXC" 2>&1

echo -e "\e[1m> Création d'un snapshot\e[0m" | tee -a "$LOG_BUILD_LXC"
sudo lxc-snapshot -n $LXC_NAME1 >> "$LOG_BUILD_LXC" 2>&1
# Il sera nommé snap0 et stocké dans /var/lib/lxcsnaps/$LXC_NAME1/snap0/

echo -e "\e[1m> Clone la machine\e[0m" | tee -a "$LOG_BUILD_LXC"
sudo lxc-copy --name=$LXC_NAME1 --newname=$LXC_NAME2 >> "$LOG_BUILD_LXC" 2>&1

echo -e "\e[1m> Modification de l'ip du clone\e[0m" | tee -a "$LOG_BUILD_LXC"
sudo sed -i "s@address $IP_LXC1@address $IP_LXC2@" /var/lib/lxc/$LXC_NAME2/rootfs/etc/network/interfaces >> "$LOG_BUILD_LXC" 2>&1
echo -e "\e[1m> Et le nom du veth\e[0m" | tee -a "$LOG_BUILD_LXC"
sudo sed -i "s@^lxc.net.0.veth.pair = $LXC_NAME1@lxc.net.0.veth.pair = $LXC_NAME2@" /var/lib/lxc/$LXC_NAME2/config >> "$LOG_BUILD_LXC" 2>&1
echo -e "\e[1m> Et enfin renseigne /etc/hosts sur le clone\e[0m" | tee -a "$LOG_BUILD_LXC"
sudo sed -i "s@^127.0.0.1 $LXC_NAME1@127.0.0.1 $LXC_NAME2@" /var/lib/lxc/$LXC_NAME2/rootfs/etc/hosts >> "$LOG_BUILD_LXC" 2>&1

echo -e "\e[1m> Mise en place du cron de switch\e[0m"
echo | sudo tee /etc/cron.d/demo_switch <<EOF > /dev/null
# Switch des conteneurs toutes les $TIME_TO_SWITCH minutes
*/$TIME_TO_SWITCH * * * * root $script_dir/demo_switch.sh >> "$script_dir/demo_switch.log" 2>&1
EOF
echo -e "\e[1m> Et du cron d'upgrade\e[0m"
echo | sudo tee /etc/cron.d/demo_upgrade <<EOF > /dev/null
# Vérifie les mises à jour des conteneurs de demo, lorsqu'ils ne sont pas utilisés, à partir de 3h2minutes chaque nuit. Attention à rester sur un multiple du temps de switch.
2 3 * * * root $script_dir/demo_upgrade.sh >> "$script_dir/demo_upgrade.log" 2>&1
EOF

echo -e "\e[1m> Démarrage de la démo\e[0m"
"$script_dir/demo_start.sh"

# echo "> Mise en place du service"
echo | sudo tee /etc/systemd/system/lxc_demo.service <<EOF > /dev/null
[Unit]
Description=Start and stop script for lxc demo container
Requires=network.target
After=network.target

[Service]
Type=forking
ExecStart=$script_dir/demo_start.sh
RemainAfterExit=true
ExecStop=$script_dir/demo_stop.sh
ExecReload=$script_dir/demo_start.sh

[Install]
WantedBy=multi-user.target
EOF

# Démarrage automatique du service
sudo systemctl enable lxc_demo.service
sudo service lxc_demo start

# Après le démarrage du premier conteneur, fait un snapshot du deuxième.
echo -e "\e[1m> Création d'un snapshot pour le 2e conteneur\e[0m" | tee -a "$LOG_BUILD_LXC"
sudo lxc-snapshot -n $LXC_NAME2 >> "$LOG_BUILD_LXC" 2>&1
# Il sera nommé snap0 et stocké dans /var/lib/lxcsnaps/$LXC_NAME2/snap0/
