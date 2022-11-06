#!/bin/bash

cd "$(dirname $(realpath $0))"

if (( $# < 3 ))
then
	cat << EOF
Usage: ./demo_lxc_build_init.sh some.domain.tld SecretAdminPasswurzd! Demo_User Demo_Password

1st and 2nd arguments are for yunohost postinstall
  - domain
  - admin password

3rd and 4th argument are used for the demo
  - demo_user
  - demo_password

EOF
	exit 1
fi

domain=$1
yuno_pwd=$2
demo_user=$3
demo_password=$4

echo_bold () {
	echo -e "\e[1m$1\e[0m"
}

# -----------------------------------------------------------------

function install_dependencies() {

	echo_bold "> Installing dependencies..."
	apt-get update
	apt-get install -y curl wget git python3-pip
}

function setup_yunohost() {
	
	echo_bold "> Setting up Yunohost..."
	local DIST="bullseye"
	local INSTALL_SCRIPT="https://install.yunohost.org/$DIST"
	curl $INSTALL_SCRIPT | bash -s -- -a
	
	echo_bold "> Running yunohost postinstall"
	yunohost tools postinstall --domain $domain --password $yuno_pwd

	echo_bold "> Disabling unecessary services to save up RAM"
	for SERVICE in mysql php7.3-fpm metronome rspamd dovecot postfix redis-server postsrsd yunohost-api avahi-daemon
	do
		systemctl stop $SERVICE
		systemctl disable $SERVICE --quiet
	done
}

function setup_yunohost_demo() {
	echo_bold "> Installation of yunohost_demo..."
	if ! yunohost app list --output-as json --quiet | jq -e '.apps[] | select(.id == "yunohost_demo")' >/dev/null
	then
		yunohost app install --force https://github.com/YunoHost-Apps/yunohost_demo_ynh -a "domain=$domain&demo_user=$demo_user&demo_password=$demo_password"
	fi
}

# =========================
#  Main stuff
# =========================

install_dependencies

[ -e /usr/bin/yunohost ] || setup_yunohost

setup_yunohost_demo

echo "Done!"
echo " "
