#!/bin/bash
#
#TODO:
#
#Changelog:
#	1. escape '/' in SSH certificate
#
main(){
set -x
set -x
#set variables
arch_servers_install_keys_dir=arch_servers_install_keys
user_ssh_keys_dir=~/.ssh
ssh_key_name=arch_servers_install_key_ed25519_$(date -I)
ssh_key_comment=arch_servers_install_key_$(date -I)
#[[[sensible_var_block_begin]]]
password_to_be_changed=
#[[[sensible_var_block_end]]]
if [ -z "${password_to_be_changed}" ]
	then echo "Not all required variables defined. Exiting."
	exit 1
fi
[ ! -e ${arch_servers_install_keys_dir} ] && mkdir -pv ${arch_servers_install_keys_dir}
[ ! -e ${arch_servers_install_keys_dir}/${ssh_key_name} ] && ssh-keygen -t ed25519 -o -a 100 -C "${ssh_key_comment}" -f ${arch_servers_install_keys_dir}/${ssh_key_name}
cp -vt ${user_ssh_keys_dir} ${arch_servers_install_keys_dir}/${ssh_key_name}*
sed -i -e "s/^\(preseeded_ssh_cert=\).*/\1\"$(cat ${arch_servers_install_keys_dir}/${ssh_key_name}.pub | sed -e 's/\//\\\//g')\"/" ${archiso_script}
sed -i -e "s/^\(password_to_be_changed=\).*/\1${password_to_be_changed}/" ${archiso_script}
#			ssh-keygen -t ed25519 -o -a 100 -C "arch_servers_install_key_$(whoami)@$(hostname)_$(date -I)" -f .ssh/arch_servers_install_key_ed25519_$(date -I)
./backup_is.sh e b
}
archiso_script=arch_servers.archiso.sh
script_name=$(basename $0)
case "$1" in
	"log")
		main
		sudo ./arch_servers.archiso.sh
		exit
		;;
	*)
		[ -e ${script_name%.*}.log ] && mv -fv ${script_name%.*}.log ${script_name%.*}.log.old
		if [ -z "${archiso_script}" ]
			then echo "Not all required variables defined. Exiting."
			exit 1
		fi
		if [ ! -e ${archiso_script} ]
			then echo "File "${archiso_script}" not found. Exiting."
			exit 2
		fi
		exec "$0" log 2>&1 | tee ${script_name%.*}.log
		;;
esac
