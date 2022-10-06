#!/bin/bash

# Installe LXC et les paramètres réseaux avant de procéder au build.

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$(echo $PWD/$(dirname "$0" | cut -d '.' -f2) | sed 's@/$@@')"; fi

LOG=$(cat "$script_dir/demo_lxc_build.sh" | grep LOG= | cut -d '=' -f2)
LOG_BUILD_LXC="$script_dir/$LOG"
LXC_NAME1=$(cat "$script_dir/demo_lxc_build.sh" | grep LXC_NAME1= | cut -d '=' -f2)
LXC_NAME2=$(cat "$script_dir/demo_lxc_build.sh" | grep LXC_NAME2= | cut -d '=' -f2)
PLAGE_IP=$(cat "$script_dir/demo_lxc_build.sh" | grep PLAGE_IP= | cut -d '=' -f2)
IP_LXC1=$(cat "$script_dir/demo_lxc_build.sh" | grep IP_LXC1= | cut -d '=' -f2)
IP_LXC2=$(cat "$script_dir/demo_lxc_build.sh" | grep IP_LXC2= | cut -d '=' -f2)
MAIL_ADDR=$(cat "$script_dir/demo_lxc_build.sh" | grep MAIL_ADDR= | cut -d '=' -f2)

# Check user
echo $(whoami) > "$script_dir/setup_user"

read -p "Indiquer le nom de domaine du serveur de demo: " DOMAIN
echo "$DOMAIN" > "$script_dir/domain.ini"

# Créer le dossier de log
sudo mkdir -p $(dirname $LOG_BUILD_LXC)

echo -e "\e[1m> Update et install lxc, lxctl et mailutils\e[0m" | tee "$LOG_BUILD_LXC"
sudo apt-get update >> "$LOG_BUILD_LXC" 2>&1
sudo apt-get install -y lxc lxctl mailutils certbot >> "$LOG_BUILD_LXC" 2>&1

echo -e "\e[1m> Autoriser l'ip forwarding, pour router vers la machine virtuelle.\e[0m" | tee -a "$LOG_BUILD_LXC"
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/lxc_demo.conf >> "$LOG_BUILD_LXC" 2>&1
sudo sysctl -p /etc/sysctl.d/lxc_demo.conf >> "$LOG_BUILD_LXC" 2>&1

echo -e "\e[1m> Ajoute un brige réseau pour la machine virtualisée\e[0m" | tee -a "$LOG_BUILD_LXC"
echo | sudo tee /etc/network/interfaces.d/lxc_demo <<EOF >> "$LOG_BUILD_LXC" 2>&1
auto lxc_demo
iface lxc_demo inet static
        address $PLAGE_IP.1/24
        bridge_ports none
        bridge_fd 0
        bridge_maxwait 0
EOF

echo -e "\e[1m> Active le bridge réseau\e[0m" | tee -a "$LOG_BUILD_LXC"
sudo ifup lxc_demo --interfaces=/etc/network/interfaces.d/lxc_demo >> "$LOG_BUILD_LXC" 2>&1

echo -e "\e[1m> Mise en place de la connexion ssh vers l'invité.\e[0m" | tee -a "$LOG_BUILD_LXC"
if [ -e $HOME/.ssh/$LXC_NAME1 ]; then
	rm -f $HOME/.ssh/$LXC_NAME1 $HOME/.ssh/$LXC_NAME1.pub
	ssh-keygen -f $HOME/.ssh/known_hosts -R $IP_LXC1
	ssh-keygen -f $HOME/.ssh/known_hosts -R $IP_LXC2
fi
ssh-keygen -t rsa -f $HOME/.ssh/$LXC_NAME1 -P '' >> "$LOG_BUILD_LXC" 2>&1

echo | tee -a $HOME/.ssh/config <<EOF >> "$LOG_BUILD_LXC" 2>&1
# ssh $LXC_NAME1
Host $LXC_NAME1
Hostname $IP_LXC1
User ssh_demo
IdentityFile $HOME/.ssh/$LXC_NAME1
Host $LXC_NAME2
Hostname $IP_LXC2
User ssh_demo
IdentityFile $HOME/.ssh/$LXC_NAME1
# End ssh $LXC_NAME1
EOF

echo -e "\e[1m> Mise en place du reverse proxy et du load balancing\e[0m" | tee -a "$LOG_BUILD_LXC"
echo | sudo tee /etc/nginx/conf.d/$DOMAIN.conf <<EOF >> "$LOG_BUILD_LXC" 2>&1
#upstream $DOMAIN  {
#  server $IP_LXC1:443 ;
#  server $IP_LXC2:443 ;
#}

server {
	listen 80;
	listen [::]:80;
	server_name $DOMAIN;

	location '/.well-known/acme-challenge' {
		default_type "text/plain";
		root         /tmp/letsencrypt-auto;
	}

	access_log /var/log/nginx/$DOMAIN-access.log;
	error_log /var/log/nginx/$DOMAIN-error.log;
}

server {
	listen 443 ssl;
	listen [::]:443 ssl;
	server_name $DOMAIN;

#	ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
#	ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
	ssl_session_timeout 5m;
	ssl_session_cache shared:SSL:50m;
	ssl_prefer_server_ciphers on;
	ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
	ssl_ciphers ALL:!aNULL:!eNULL:!LOW:!EXP:!RC4:!3DES:+HIGH:+MEDIUM;
	add_header Strict-Transport-Security "max-age=31536000;";

	location / {
		proxy_pass        https://$DOMAIN;
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

echo -e "\e[1m> Création du certificat SSL.\e[0m" | tee -a "$LOG_BUILD_LXC"
sudo mkdir -p /etc/letsencrypt

# Créer le fichier de config
echo | sudo tee /etc/letsencrypt/conf.ini <<EOF >> "$LOG_BUILD_LXC" 2>&1
#################################
#  Let's encrypt configuration  #
#################################

# Use a 4096 bit RSA key instead of 2048
rsa-key-size = 4096

# Uncomment and update to register with the specified e-mail address
email = $MAIL_ADDR

# Uncomment to use the webroot authenticator. Replace webroot-path with the
# path to the public_html / webroot folder being served by your web server.
# avec le contenu dans /tmp/letsencrypt-auto
authenticator = webroot
webroot-path = /tmp/letsencrypt-auto

# Utiliser l'interface texte
text = True
# Uncomment to automatically agree to the terms of service of the ACME server
agree-tos = true

# (Serveur de test uniquement : si vous l'utilisez,
# votre certificat ne sera pas vraiment valide)
# server = https://acme-staging-v02.api.letsencrypt.org/directory
EOF

mkdir -p /tmp/letsencrypt-auto
# Créer le certificat
sudo certbot certonly --config /etc/letsencrypt/conf.ini -d $DOMAIN --no-eff-email

# Route l'upstream sur le port 443. Le port 80 servait uniquement à let's encrypt
# sudo sed -i "s/server $IP_LXC1:80 ;/server $IP_LXC1:443 ;/" /etc/nginx/conf.d/$DOMAIN.conf
# Décommente les lignes du certificat
# sudo sed -i "s/#\tssl_certificate/\tssl_certificate/g" /etc/nginx/conf.d/$DOMAIN.conf
# Supprime les commentaires dans la conf nginx

sudo sed -i "s/^#//g" /etc/nginx/conf.d/$DOMAIN.conf
sudo service nginx reload

echo -e "\e[1mLe serveur est prêt à déployer les conteneurs de demo.\e[0m"
echo -e "\e[1mExécutez le script demo_lxc_build.sh pour créer les conteneurs et mettre en place la demo.\e[0m"

# Déploie les conteneurs de demo
# "$script_dir/demo_lxc_build.sh"
