#!/bin/bash

# Installe LXC et les paramètres réseaux avant de procéder au build.

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$PWD/$(dirname "$0" | cut -d '.' -f2)"; fi

LOG_BUILD_LXC="$(cat "$script_dir/demo_lxc_build.sh" | grep LOG_BUILD_LXC= | cut -d '=' -f2)"
LXC_NAME1=$(cat "$script_dir/demo_lxc_build.sh" | grep LXC_NAME1= | cut -d '=' -f2)
LXC_NAME2=$(cat "$script_dir/demo_lxc_build.sh" | grep LXC_NAME2= | cut -d '=' -f2)
PLAGE_IP=$(cat "$script_dir/demo_lxc_build.sh" | grep PLAGE_IP= | cut -d '=' -f2)
IP_LXC=$(cat "$script_dir/demo_lxc_build.sh" | grep IP_LXC= | cut -d '=' -f2)
DOMAIN=$(cat "$script_dir/demo_lxc_build.sh" | grep DOMAIN= | cut -d '=' -f2)

# Créer le dossier de log
sudo mkdir -p $(dirname $LOG_BUILD_LXC)

echo "> Update et install lxc lxctl" | tee "$LOG_BUILD_LXC"
sudo apt-get update >> "$LOG_BUILD_LXC" 2>&1
sudo apt-get install -y lxc lxctl >> "$LOG_BUILD_LXC" 2>&1

echo "> Autoriser l'ip forwarding, pour router vers la machine virtuelle." | tee -a "$LOG_BUILD_LXC"
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/lxc_demo.conf >> "$LOG_BUILD_LXC" 2>&1
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

echo "> Mise en place de la connexion ssh vers l'invité." | tee -a "$LOG_BUILD_LXC"
if [ -e $HOME/.ssh/$LXC_NAME1 ]; then
	rm -f $HOME/.ssh/$LXC_NAME1 $HOME/.ssh/$LXC_NAME1.pub
	ssh-keygen -f $HOME/.ssh/known_hosts -R $IP_LXC
fi
ssh-keygen -t dsa -f $HOME/.ssh/$LXC_NAME1 -P '' >> "$LOG_BUILD_LXC" 2>&1

echo | tee -a $HOME/.ssh/config <<EOF >> "$LOG_BUILD_LXC" 2>&1
# ssh $LXC_NAME1
Host $LXC_NAME1
Host $LXC_NAME2
Hostname $IP_LXC
User ssh_demo
IdentityFile $HOME/.ssh/$LXC_NAME1
EOF

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
		proxy_set_header  Host \$host;
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

# Mise en place de HAProxy
# [...]
# La config de base est à pleurer... Elle est quasi vide...
# Et la doc du site officiel est une encyclopédie en 500 tomes...
# Modify
#         timeout connect 5s  
#         timeout client  30s  
#         timeout server  10s  
# Add
#         maxconn 500 

# Déploie les conteneurs de demo
"$script_dir/demo_lxc_build.sh"
