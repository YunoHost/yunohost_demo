#!/bin/bash

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$PWD/$(dirname "$0" | cut -d '.' -f2)"; fi

LOG_BUILD_LXC="$script_dir/Build_lxc.log"
PLAGE_IP="10.1.5"
IP_LXC=$PLAGE_IP.3
ARG_SSH="-t"
DOMAIN=demotest1.nohost.me
YUNO_PWD=admin
LXC_NAME1=yunohost_demo1
LXC_NAME2=yunohost_demo2
TIME_TO_SWITCH=30	# En minutes

USER_DEMO=demo
PASSWORD_DEMO=demo


# Check root
CHECK_ROOT=$EUID
if [ -z "$CHECK_ROOT" ];then CHECK_ROOT=0;fi
if [ $CHECK_ROOT -eq 0 ]
then	# $EUID est vide sur une exécution avec sudo. Et vaut 0 pour root
   echo "Le script ne doit pas être exécuté avec les droits root"
   exit 1
fi

echo "> Update et install lxc lxctl" | tee "$LOG_BUILD_LXC"
sudo apt-get update >> "$LOG_BUILD_LXC" 2>&1
sudo apt-get install -y lxc lxctl >> "$LOG_BUILD_LXC" 2>&1

echo "> Création d'une machine debian jessie minimaliste" | tee -a "$LOG_BUILD_LXC"
sudo lxc-create -n $LXC_NAME1 -t debian -- -r jessie >> "$LOG_BUILD_LXC" 2>&1

echo "> Autoriser l'ip forwarding, pour router vers la machine virtuelle." | tee -a "$LOG_BUILD_LXC"
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/lxc_pchecker.conf >> "$LOG_BUILD_LXC" 2>&1
sudo sysctl -p /etc/sysctl.d/lxc_demo.conf >> "$LOG_BUILD_LXC" 2>&1

echo "> Ajoute un brige réseau pour la machine virtualisée" | tee -a "$LOG_BUILD_LXC"
echo | sudo tee /etc/network/interfaces.d/lxc_demo <<EOF >> "$LOG_BUILD_LXC" 2>&1
auto lxc_demo
iface lxc_demo inet static
        address $PLAGE_IP.1/24
        bridge_ports none
        bridge_fd 0
        bridge_maxwait 0
EOF

echo "> Active le bridge réseau" | tee -a "$LOG_BUILD_LXC"
sudo ifup lxc_demo --interfaces=/etc/network/interfaces.d/lxc_demo >> "$LOG_BUILD_LXC" 2>&1

echo "> Configuration réseau du conteneur" | tee -a "$LOG_BUILD_LXC"
sudo sed -i "s/^lxc.network.type = empty$/lxc.network.type = veth\nlxc.network.flags = up\nlxc.network.link = lxc_demo\nlxc.network.name = eth0\nlxc.network.veth.pair = $LXC_NAME1\nlxc.network.hwaddr = 00:FF:AA:00:00:03/" /var/lib/lxc/$LXC_NAME1/config >> "$LOG_BUILD_LXC" 2>&1

echo "> Configuration réseau de la machine virtualisée" | tee -a "$LOG_BUILD_LXC"
sudo sed -i "s@iface eth0 inet dhcp@iface eth0 inet static\n\taddress $IP_LXC/24\n\tgateway $PLAGE_IP.1@" /var/lib/lxc/$LXC_NAME1/rootfs/etc/network/interfaces >> "$LOG_BUILD_LXC" 2>&1

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

echo "> Autorise pchecker à utiliser sudo sans mot de passe" | tee -a "$LOG_BUILD_LXC"
echo "pchecker    ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee -a /var/lib/lxc/$LXC_NAME1/rootfs/etc/sudoers >> "$LOG_BUILD_LXC" 2>&1

echo "> Mise en place de la connexion ssh vers l'invité." | tee -a "$LOG_BUILD_LXC"
if [ -e $HOME/.ssh/$LXC_NAME1 ]; then
	rm -f $HOME/.ssh/$LXC_NAME1 $HOME/.ssh/$LXC_NAME1.pub
	ssh-keygen -f $HOME/.ssh/known_hosts -R $IP_LXC
fi
ssh-keygen -t dsa -f $HOME/.ssh/$LXC_NAME1 -P '' >> "$LOG_BUILD_LXC" 2>&1
sudo mkdir /var/lib/lxc/$LXC_NAME1/rootfs/home/ssh_demo/.ssh >> "$LOG_BUILD_LXC" 2>&1
sudo cp $HOME/.ssh/$LXC_NAME1.pub /var/lib/lxc/$LXC_NAME1/rootfs/home/ssh_demo/.ssh/authorized_keys >> "$LOG_BUILD_LXC" 2>&1
sudo lxc-attach -n $LXC_NAME1 -- chown ssh_demo -R /home/ssh_demo/.ssh >> "$LOG_BUILD_LXC" 2>&1

echo | tee -a $HOME/.ssh/config <<EOF >> "$LOG_BUILD_LXC" 2>&1
# ssh $LXC_NAME1
Host $LXC_NAME1
Hostname $IP_LXC
User ssh_demo
IdentityFile $HOME/.ssh/$LXC_NAME1
EOF

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
echo "> Ajout de l'utilisateur de test" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost user create --firstname \"$USER_DEMO_CLEAN\" --mail \"$USER_DEMO_CLEAN@$DOMAIN\" --lastname \"$USER_DEMO_CLEAN\" --password \"$PASSWORD_DEMO\" \"$USER_DEMO\" --admin-password=\"$YUNO_PWD\""

echo -e "\n> Vérification de l'état de Yunohost" | tee -a "$LOG_BUILD_LXC"
ssh $ARG_SSH $LXC_NAME1 "sudo yunohost -v" | tee -a "$LOG_BUILD_LXC" 2>&1


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

echo "> Mise en place du reverse proxy" | tee -a "$LOG_BUILD_LXC"
echo | sudo tee /etc/nginx/conf.d/$DOMAIN.conf <<EOF
server {
	listen 80;
	listen [::]:80;
	server_name $DOMAIN;

	if (\$scheme = http) {
		rewrite ^ https://\$server_name\$request_uri? permanent;
	}

	access_log /var/log/nginx/$DOMAIN-access.log;
	error_log /var/log/nginx/$DOMAIN-error.log;
}

server {
	listen 443 ssl;
	listen [::]:443 ssl;
	server_name $DOMAIN;

	location / {
		proxy_pass        https://$IP_LXC;
		proxy_redirect    off;
		proxy_set_header  Host \$host;c
		proxy_set_header  X-Real-IP \$remote_addr;
		proxy_set_header  X-Forwarded-Proto \$scheme;
		proxy_set_header  X-Forwarded-For \$proxy_add_x_forwarded_for;
		proxy_set_header  X-Forwarded-Host \$server_name;
	}

	access_log /var/log/nginx/$DOMAIN-access.log;
	error_log /var/log/nginx/$DOMAIN-error.log;
}
EOF

sudo service nginx reload

# Mise en place du cron de switch
echo | sudo tee /etc/cron.d/demo_switch <<EOF
# Switch des conteneurs toutes les $TIME_TO_SWITCH minutes
*/$TIME_TO_SWITCH * * * * root $script_dir/demo_switch.sh > /dev/null 2>&1
EOF

# Mise en place de HAProxy
# [...]

# Démarrage de la démo
"./$script_dir/demo_start.sh"
