# Installation and management scripts for YunoHost demo servers using LXD

## Requirements
* A debian server
* Register a dns name to your demo server and make you demo server available from internet for TCP/80 and TCP/443

## demo_lxc_build_init
This script will install YunoHost and the app yunohost_demo_ynh

## demo_lxc_build
This script will build the demo containers.
It also install crons and start the first container.
After executing this script, YunoHost demo is working.

## demo_lxc_destroy
This script stop the containers and destroy them.
It is usually used for rebuilding containers with new parameters. And should therefore be followed by the demo_lxc_build script.

## demo_lxc_remove
This script will remove yunohost_demo_ynh.
It should only be used when the host server is changed.

## demo_start
Simply allows a clean start of the first container. With network bridge and firewall rules in place.

## demo_stop
Cleanly shuts down containers and disables the specific network config.

## demo_switch
It will alternate every 30 minutes (by default) the 2 containers and restore the snapshot of the container after it is shut down.

## demo_upgrade
It checks every night for updates on the containers, and applies them if necessary. If necessary, it also takes care of redoing the snapshot.

## demo_restore_crash
Attempts to repair containers that do not boot from previous snapshots or snapshot archives.

To make permanent changes to the containers, it is possible to add scripts to the upgrade.d folder. These scripts will be executed after the upgrade of the packages in each container.
In case of execution failure, the script will be put aside until it is corrected. Otherwise, it will be archived.
