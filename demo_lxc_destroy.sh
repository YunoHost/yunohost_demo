#!/bin/bash

# Détruit les conteneurs lxc de demo.
# Permet de repartir sur des bases saines avec le script demo_lxc_build.sh

# Récupère le dossier du script
if [ "${0:0:1}" == "/" ]; then script_dir="$(dirname "$0")"; else script_dir="$PWD/$(dirname "$0" | cut -d '.' -f2)"; fi

LXC_NAME1=$(cat "$script_dir/lxc_build.sh" | grep LXC_NAME1= | cut -d '=' -f2)
LXC_NAME2=$(cat "$script_dir/lxc_build.sh" | grep LXC_NAME2= | cut -d '=' -f2)

"$script_dir/demo_stop.sh"

echo "> Suppression des conteneurs et de leur snapshots"
sudo lxc-snapshot -n $LXC_NAME1 -d snap0
sudo rm -f /var/lib/lxcsnaps/$LXC_NAME1/snap0.tar.gz
sudo lxc-destroy -n $LXC_NAME1 -f
sudo lxc-snapshot -n $LXC_NAME2 -d snap0
sudo rm -f /var/lib/lxcsnaps/$LXC_NAME2/snap0.tar.gz
sudo lxc-destroy -n $LXC_NAME2 -f

# Suppression des crons
sudo rm /etc/cron.d/demo_switch
sudo rm /etc/cron.d/demo_upgrade
