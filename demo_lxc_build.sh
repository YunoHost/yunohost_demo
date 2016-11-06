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
 # En minutes
MAIL_ADDR=demo@yunohost.org

USER_DEMO=demo
PASSWORD_DEMO=demo

# Check user
if [ "$USER" != "$(cat "$script_dir/setup_user")" ] && test -e "$script_dir/setup_user"; then
	echo -e "\e[91mCe script doit être exécuté avec l'utilisateur $(cat "$script_dir/setup_user")"
	echo -en "\e[0m"
	exit 0
fi

echo "> Création d'une machine debian jessie minimaliste" | tee -a "$LOG_BUILD_LXC"
sudo lxc-create -n $LXC_NAME1 -t debian -- -r jessie >> "$LOG_BUILD_LXC" 2>&1

echo "> Active le bridge réseau" | tee -a "$LOG_BUILD_LXC"
sudo ifup lxc_demo --interfaces=/etc/network/interfaces.d/lxc_demo >> "$LOG_BUILD_LXC" 2>&1

echo "> Configuration réseau du conteneur" | tee -a "$LOG_BUILD_LXC"
sudo sed -i "s/^lxc.network.type = empty$/lxc.network.type = veth\nlxc.network.flags = up\nlxc.network.link = lxc_demo\nlxc.network.name = eth0\nlxc.network.veth.pair = $LXC_NAME1\nlxc.network.hwaddr = 00:FF:AA:00:00:03/" /var/lib/lxc/$LXC_NAME1/config >> "$LOG_BUILD_LXC" 2>&1

echo "> Configuration réseau de la machine virtualisée" | tee -a "$LOG_BUILD_LXC"
sudo sed -i "s@iface eth0 inet dhcp@iface eth0 inet static\n\taddress $IP_LXC1/24\n\tgateway $PLAGE_IP.1@" /var/lib/lxc/$LXC_NAME1/rootfs/etc/network/interfaces >> "$LOG_BUILD_LXC" 2>&1

echo "> Configure le parefeu" | tee -a "$LOG_BUILD_LXC"
sudo iptables -A FORWARD -i lxc_demo -o eth0 -j ACCEPT >> "$LOG_BUILD_LXC" 2>&1
sudo iptables -A FORWARD -i eth0 -o lxc_demo -j ACCEPT >> "$LOG_BUILD_LXC" 2>&1
sudo iptables -t nat -A POSTROUTING -s $PLAGE_IP.0/24 -j MASQUERADE >> "$LOG_BUILD_LXC" 2>&1

echo "> Démarrage de la machine" | tee -a "$LOG_BUILD_LXC"
sudo lxc-start -n $LXC_NAME1 -d >> "$LOG_BUILD_LXC" 2>&1
sleep 3
sudo lxc-ls -f >> "$LOG_BUILD_LXC" 2>&1

echo "> Update et install tasksel sudo git" | tee -a "$LOG_BUILD_LXC"
sudo lxc-attach -n $LXC_NAME1 -- apt-get update
sudo lxc-attach -n $LXC_NAME1 -- apt-get install -y tasksel sudo git
echo "> Installation des paquets standard et ssh-server" | tee -a "$LOG_BUILD_LXC"
tasksell_exit=1
while [ "$tasksell_exit" -ne 0 ]
do
	sudo lxc-attach -n $LXC_NAME1 -- tasksel install standard ssh-server
	tasksell_exit=$?
done
echo "> Renseigne /etc/hosts sur l'invité" | tee -a "$LOG_BUILD_LXC"
echo "127.0.0.1 $LXC_NAME1" | sudo tee -a /var/lib/lxc/$LXC_NAME1/rootfs/etc/hosts >> "$LOG_BUILD_LXC" 2>&1

echo "> Ajoute l'user ssh_demo (avec un mot de passe à revoir...)" | tee -a "$LOG_BUILD_LXC"
sudo lxc-attach -n $LXC_NAME1 -- useradd -m -p ssh_demo ssh_demo >> "$LOG_BUILD_LXC" 2>&1

echo "> Autorise ssh_demo à utiliser sudo sans mot de passe" | tee -a "$LOG_BUILD_LXC"
echo "ssh_demo    ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee -a /var/lib/lxc/$LXC_NAME1/rootfs/etc/sudoers >> "$LOG_BUILD_LXC" 2>&1

echo "> Mise en place de la connexion ssh vers l'invité." | tee -a "$LOG_BUILD_LXC"
sudo mkdir /var/lib/lxc/$LXC_NAME1/rootfs/home/ssh_demo/.ssh >> "$LOG_BUILD_LXC" 2>&1
sudo cp $HOME/.ssh/$LXC_NAME1.pub /var/lib/lxc/$LXC_NAME1/rootfs/home/ssh_demo/.ssh/authorized_keys >> "$LOG_BUILD_LXC" 2>&1
sudo lxc-attach -n $LXC_NAME1 -- chown ssh_demo -R /home/ssh_demo/.ssh >> "$LOG_BUILD_LXC" 2>&1

ssh $ARG_SSH $LXC_NAME1 "exit 0"	# Initie une premier connexion SSH pour valider la clé.
if [ "$?" -ne 0 ]; then	# Si l'utilisateur tarde trop, la connexion sera refusée... ???
	ssh $ARG_SSH $LXC_NAME1 "exit 0"	# Initie une premier connexion SSH pour valider la clé.
fi

ssh $ARG_SSH $LXC_NAME1 "git clone https://github.com/YunoHost/install_script /tmp/install_script" >> "$LOG_BUILD_LXC" 2>&1
echo "> Installation de Yunohost..." | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "cd /tmp/install_script; sudo ./install_yunohost -a" | tee -a "$LOG_BUILD_LXC" 2>&1
echo "> Post install Yunohost" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost tools postinstall --domain $DOMAIN --password $YUNO_PWD" | tee -a "$LOG_BUILD_LXC" 2>&1

USER_DEMO_CLEAN=${USER_DEMO//"_"/""}
echo "> Ajout de l'utilisateur de demo" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost user create --firstname \"$USER_DEMO_CLEAN\" --mail \"$USER_DEMO_CLEAN@$DOMAIN\" --lastname \"$USER_DEMO_CLEAN\" --password \"$PASSWORD_DEMO\" \"$USER_DEMO\" --admin-password=\"$YUNO_PWD\""

echo -e "\n> Vérification de l'état de Yunohost" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost -v" | tee -a "$LOG_BUILD_LXC" 2>&1

# ********
echo ">> Modification de Yunohost pour la demo" | tee -a "$LOG_BUILD_LXC"

# App officielles
echo -e "> Installation des applications officielles" | tee -a "$LOG_BUILD_LXC"
echo -e "Installation de baikal" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install baikal -a \"domain=$DOMAIN&path=/baikal&password=$PASSWORD_DEMO\"" | tee -a "$LOG_BUILD_LXC"
echo -e "Installation d'agendav" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install agendav -a \"domain=$DOMAIN&path=/agendav&language=en\"" | tee -a "$LOG_BUILD_LXC"
echo -e "Installation de dokuwiki" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install dokuwiki -a \"domain=$DOMAIN&path=/dokuwiki&admin=$USER_DEMO&is_public=Yes\"" | tee -a "$LOG_BUILD_LXC"
echo -e "Installation de hextris" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install hextris -a \"domain=$DOMAIN&path=/hextris&is_public=Yes\"" | tee -a "$LOG_BUILD_LXC"
echo -e "Installation de jappix" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install jappix -a \"domain=$DOMAIN&path=/jappix&name=YunoJappix&language=en\"" | tee -a "$LOG_BUILD_LXC"
echo -e "Installation de jirafeau" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install jirafeau -a \"domain=$DOMAIN&path=/jirafeau&admin_user=$USER_DEMO&upload_password=$PASSWORD_DEMO&is_public=Yes\"" | tee -a "$LOG_BUILD_LXC"
echo -e "Installation de kanboard" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install kanboard -a \"domain=$DOMAIN&path=/kanboard&admin=$USER_DEMO&is_public=Yes\"" | tee -a "$LOG_BUILD_LXC"
echo -e "Installation de opensondage" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install opensondage -a \"domain=$DOMAIN&path=/date&admin=$USER_DEMO&language=en_GB&is_public=1\"" | tee -a "$LOG_BUILD_LXC"
echo -e "Installation de owncloud" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install owncloud -a \"domain=$DOMAIN&path=/owncloud&admin=$USER_DEMO&user_home=0\"" | tee -a "$LOG_BUILD_LXC"
echo -e "Installation de phpmyadmin" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install phpmyadmin -a \"domain=$DOMAIN&path=/phpmyadmin&admin=$USER_DEMO\"" | tee -a "$LOG_BUILD_LXC"
echo -e "Installation de roundcube" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install roundcube -a \"domain=$DOMAIN&path=/webmail&with_carddav=0\"" | tee -a "$LOG_BUILD_LXC"
echo -e "Installation de searx" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install searx -a \"domain=$DOMAIN&path=/searx&is_public=Yes\"" | tee -a "$LOG_BUILD_LXC"
echo -e "Installation de shellinabox" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install shellinabox -a \"domain=$DOMAIN&path=/ssh\"" | tee -a "$LOG_BUILD_LXC"
echo -e "Installation de strut" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install strut -a \"domain=$DOMAIN&path=/strut&public_site=Yes\"" | tee -a "$LOG_BUILD_LXC"
echo -e "Installation de transmission" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install transmission -a \"domain=$DOMAIN&path=/torrent\"" | tee -a "$LOG_BUILD_LXC"
echo -e "Installation de ttrss" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install ttrss -a \"domain=$DOMAIN&path=/ttrss\"" | tee -a "$LOG_BUILD_LXC"
echo -e "Installation de wallabag" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install wallabag -a \"domain=$DOMAIN&path=/wallabag\"" | tee -a "$LOG_BUILD_LXC"
echo -e "Installation de wordpress" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install wordpress -a \"domain=$DOMAIN&path=/blog&admin=$USER_DEMO&language=en_EN&multisite=No&is_public=Yes\"" | tee -a "$LOG_BUILD_LXC"
echo -e "Installation de zerobin" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app install zerobin -a \"domain=$DOMAIN&path=/zerobin&is_public=Yes\"" | tee -a "$LOG_BUILD_LXC"

# Désactive l'accès à shellinabox
sudo rm "/var/lib/lxc/$LXC_NAME1/rootfs/etc/nginx/conf.d/$DOMAIN.d/shellinabox.conf"	# Supprime le fichier de conf nginx de shellinabox pour empêcher d'y accéder.
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost app setting shellinabox path -d && sudo yunohost app setting shellinabox domain -d && sudo yunohost app ssowatconf" | tee -a "$LOG_BUILD_LXC"

# Indique le couple login/mot de passe demo/demo
# Et ajoute demo/demo par défaut dans les champs d'identification
sed -i "3i\<center>Login: demo / Password: demo</center>" /var/lib/lxc/yunohost_demo1/rootfs/usr/share/ssowat/portal/login.html # Sur le login du portail
sed -i "s/id=\"user\" type=\"text\" name=\"user\"/id=\"user\" type=\"text\" name=\"user\" value=\"demo\"/" /var/lib/lxc/yunohost_demo1/rootfs/usr/share/ssowat/portal/login.html
sed -i "s/id=\"user\" type=\"text\" name=\"user\"/id=\"user\" type=\"text\" name=\"user\" value=\"demo\"/" /var/lib/lxc/yunohost_demo1/rootfs/usr/share/ssowat/portal/login.html
sed -i "s/id=\"password\" type=\"password\" name=\"password\"/id=\"password\" type=\"password\" name=\"password\" value=\"demo\"/" /var/lib/lxc/yunohost_demo1/rootfs/usr/share/ssowat/portal/login.html

sed -i "17i\&emsp;&emsp;&emsp;Password: demo" /var/lib/lxc/yunohost_demo1/rootfs/usr/share/yunohost/admin/views/login.ms    # Et sur le login admin
sed -i "s/type=\"password\" id=\"password\" name=\"password\"/type=\"password\" id=\"password\" name=\"password\" value=\"demo\"/" /var/lib/lxc/yunohost_demo1/rootfs/usr/share/yunohost/admin/views/login.ms

# Désactive l'installation d'app custom
sed -i "s/<input type=\"submit\" class=\"btn btn-success slide\" value=\"{{t 'install'}}\">/<input type=\"\" class=\"btn btn-success slide\" value=\"{{t 'install'}}\">/g" /var/lib/lxc/yunohost_demo1/rootfs/usr/share/yunohost/admin/views/app/app_list_install.ms

# Désactive l'ajout de domaine, pour éviter surtout les nohost
sed -i "s/<input type=\"submit\" class=\"btn btn-success slide back\" value=\"{{t 'add'}}\">/<input type=\"\" class=\"btn btn-success slide back\" value=\"{{t 'add'}}\">/g" /var/lib/lxc/yunohost_demo1/rootfs/usr/share/yunohost/admin/views/domain/domain_add.ms

# ********

echo "> Arrêt de la machine virtualisée" | tee -a "$LOG_BUILD_LXC"
sudo lxc-stop -n $LXC_NAME1 >> "$LOG_BUILD_LXC" 2>&1

echo "> Suppression des règles de parefeu" | tee -a "$LOG_BUILD_LXC"
sudo iptables -D FORWARD -i lxc_demo -o eth0 -j ACCEPT >> "$LOG_BUILD_LXC" 2>&1
sudo iptables -D FORWARD -i eth0 -o lxc_demo -j ACCEPT >> "$LOG_BUILD_LXC" 2>&1
sudo iptables -t nat -D POSTROUTING -s $PLAGE_IP.0/24 -j MASQUERADE >> "$LOG_BUILD_LXC" 2>&1
sudo ifdown --force lxc_demo >> "$LOG_BUILD_LXC" 2>&1

echo "> Création d'un snapshot" | tee -a "$LOG_BUILD_LXC"
sudo lxc-snapshot -n $LXC_NAME1 >> "$LOG_BUILD_LXC" 2>&1
# Il sera nommé snap0 et stocké dans /var/lib/lxcsnaps/$LXC_NAME1/snap0/

echo "> Clone la machine" | tee -a "$LOG_BUILD_LXC"
sudo sudo lxc-clone -o $LXC_NAME1 -n $LXC_NAME2 >> "$LOG_BUILD_LXC" 2>&1

echo "> Modification de l'ip du clone" | tee -a "$LOG_BUILD_LXC"
sudo sed -i "s@address $IP_LXC1@address $IP_LXC2@" /var/lib/lxc/$LXC_NAME2/rootfs/etc/network/interfaces >> "$LOG_BUILD_LXC" 2>&1
echo "> Et le nom du veth" | tee -a "$LOG_BUILD_LXC"
sudo sed -i "s@^lxc.network.veth.pair = $LXC_NAME1@lxc.network.veth.pair = $LXC_NAME2@" /var/lib/lxc/$LXC_NAME2/config >> "$LOG_BUILD_LXC" 2>&1
echo "> Et enfin renseigne /etc/hosts sur le clone" | tee -a "$LOG_BUILD_LXC"
sudo sed -i "s@^127.0.0.1 $LXC_NAME1@127.0.0.1 $LXC_NAME2@" /var/lib/lxc/$LXC_NAME2/rootfs/etc/hosts >> "$LOG_BUILD_LXC" 2>&1

echo "> Mise en place du cron de switch"
echo | sudo tee /etc/cron.d/demo_switch <<EOF > /dev/null
# Switch des conteneurs toutes les $TIME_TO_SWITCH minutes
*/$TIME_TO_SWITCH * * * * root $script_dir/demo_switch.sh >> "$script_dir/demo_switch.log" 2>&1
EOF
echo "> Et du cron d'upgrade"
echo | sudo tee /etc/cron.d/demo_upgrade <<EOF > /dev/null
# Vérifie les mises à jour des conteneurs de demo, lorsqu'ils ne sont pas utilisés, à partir de 3h2minutes chaque nuit. Attention à rester sur un multiple du temps de switch.
2 3 * * * root $script_dir/demo_upgrade.sh >> "$script_dir/demo_upgrade.log" 2>&1
EOF

echo "> Démarrage de la démo"
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
ExecStop=$script_dir/demo_stop.sh
ExecReload=$script_dir/demo_start.sh

[Install]
WantedBy=multi-user.target
EOF

# Démarrage automatique du service
sudo systemctl enable lxc_demo.service
sudo service lxc_demo start

# Après le démarrage du premier conteneur, fait un snapshot du deuxième.
echo "> Création d'un snapshot pour le 2e conteneur" | tee -a "$LOG_BUILD_LXC"
sudo lxc-snapshot -n $LXC_NAME2 >> "$LOG_BUILD_LXC" 2>&1
# Il sera nommé snap0 et stocké dans /var/lib/lxcsnaps/$LXC_NAME2/snap0/
