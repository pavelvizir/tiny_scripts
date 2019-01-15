#!/bin/bash
#
#TODO:
#
#Changelog:
#	1. According to https://technet.microsoft.com/en-us/windows-server-docs/compute/hyper-v/best-practices-for-running-linux-on-hyper-v
#		elevator=noop
#	2. Adapt to i686 deprecation (syslinux, build.sh)
#	3. Preseed SSH certificate, escape '/' in SSH certificate
# 4. TEMPORARY changed 'pacman -Syu' to 'pacman -Syu --ignore linux' due to ZFS
#			Also changed 'pacman -Sp' to 'pacman -Spd' for the same reason. 2 occurrences!
main(){
set -x
set -x
#set variables
archiso_dir=archiso
archiso_cache_dir=airootfs/root/pkg
auto_install_script=arch_servers.auto_install.sh
archiso_dest_dir=ISOs
#[[[sensible_var_block_begin]]]
password_to_be_changed=
preseeded_ssh_cert=
#[[[sensible_var_block_end]]]
if [ -z "${password_to_be_changed}" ] || [ -z "${archiso_dest_dir}" ] || [ -z "${preseeded_ssh_cert}" ]
	then echo "Not all required variables defined. Exiting."
	exit 1
fi
if [ "$EUID" -ne 0 ]
	then echo "Please run as root (sudo). Exiting."
	exit 1
fi
#read -n 1 -s -p "Press Y to continue:" continue_var
#if [ "${continue_var}" != "Y" ]
#	then exit
#fi
# 4. pacman -Syu
pacman -Syu --ignore linux
#Creating ISOs dir
[ ! -e ${archiso_dest_dir} ] && mkdir -pv ${archiso_dest_dir}
#Prepare archiso environment
echo "Preparing archiso environment:"
[ -e ${archiso_dir} ] && [ -d ${archiso_dir} ] && rm -rf ${archiso_dir}
if [ $? == 0 ];then echo "rm: deleted directory '${archiso_dir}'"; fi
mkdir -pv ${archiso_dir}
cp -r /usr/share/archiso/configs/releng/* ${archiso_dir}
if [ $? == 0 ];then echo "cp: copied files from '/usr/share/archiso/configs/releng' to '${archiso_dir}'"; fi
echo -e '\tDONE'
#Modify configuration
echo "Starting configuration:"
initial_dir=$PWD
cp -v $0 ${archiso_dir}/airootfs/root
cd ${archiso_dir}
#Configure iso bootloader to autostart and autorun the auto_install script
echo "Configuring bootloader:"
sed -i -e "2iDEFAULT auto_install\nTIMEOUT 200\n" syslinux/archiso_sys.cfg
echo -e "
LABEL auto_install
TEXT HELP
Automatically install Arch Linux (x86_64).
ENDTEXT
MENU LABEL Automatically install Arch Linux (x86_64)
LINUX boot/x86_64/vmlinuz
INITRD boot/intel_ucode.img,boot/x86_64/archiso.img
APPEND archisobasedir=%INSTALL_DIR% archisolabel=%ARCHISO_LABEL% script=${auto_install_script} copytoram=y modprobe.blacklist=i2c_piix4 elevator=noop" >> syslinux/archiso_tail.cfg
echo -e '\tDONE'
#Configure additional packages to archiso:
#We'll need 'expect' for password change.
echo "Configuring packages:"
grep -q expect packages.both
if [ $? != 0 ];then echo expect >> packages.both; fi
echo -e '\tDONE'
#Change the live-cd behaviour.
echo "Configuring live-cd behaviour:"
echo -e "
sed -i 's/^#clientid/clientid/; s/^duid/#duid/; \$aenv force_hostname=YES' /etc/dhcpcd.conf
systemctl enable sshd.service" >> airootfs/root/customize_airootfs.sh
sed -i /mirrorlist/s/\^/\#/ airootfs/root/customize_airootfs.sh
echo -e '\tDONE'
#Create auto_install_script script
echo "Copying and modifying ${auto_install_script}:"
cp -vt airootfs/root ${initial_dir}/${auto_install_script}
sed -i -e "s/^\(password_to_be_changed=\).*/\1${password_to_be_changed}/" airootfs/root/${auto_install_script}
sed -i -e "s/^\(preseeded_ssh_cert=\).*/\1\"${preseeded_ssh_cert//\//\\\/}\"/" airootfs/root/${auto_install_script}
chmod +x airootfs/root/${auto_install_script}
echo -e '\tDONE'
#Copy nftables.conf
echo "Copying nftables.conf:"
cp -vt airootfs/root ${initial_dir}/arch_servers.nftables.conf
echo -e '\tDONE'
#Change build.sh to only create x86_64
echo "Modifying build.sh:"
sed -i\
 -e 's/^\(iso_label="\).*\(_$.*\)/\1ARCH_SERVER\2/'\
 -e 's/^\(iso_name=\).*/\1arch_server/' build.sh
echo -e '\tDONE'
#Create pacman pkg cache
[ -e ${archiso_cache_dir} ] && rm -rf ${archiso_cache_dir}
if [ $? == 0 ];then echo "rm: deleted directory '${archiso_cache_dir}'"; fi
mkdir -pv ${archiso_cache_dir}
pkg_list_initial=$($(sed -n '/pacstrap \/mnt/, /genfstab/ p' airootfs/root/${auto_install_script} | sed -e "1d" -e "\$d" -e 's/\\//g' -e 's/  //g' | tr -d '\n' | sed -e "s/^/pacman -Spd --print-format %n /"))
pkg_list_deps=${pkg_list_initial}
pkg_list_final=
for i in $(seq 1 10); do pkg_list_final=$(echo ${pkg_list_final}" "${pkg_list_deps} | tr ' ' '\n' | sort -u); pkg_list_deps=$(expac -S '%E' -l '\n' ${pkg_list_deps} | sort -u);done > /dev/null 2>&1
pkg_list_links=$(pacman -Spd ${pkg_list_final})
for i in ${pkg_list_links}; do [ -e /var/cache/pacman/pkg/${i##*/} ] && cp -v /var/cache/pacman/pkg/${i##*/} ${archiso_cache_dir} || wget -nv -c -P ${archiso_cache_dir} ${i}; done
repo-add ${archiso_cache_dir}/offline_install.db.tar.gz ${archiso_cache_dir}/*
#Build iso finally
./build.sh -v
#Returning back to where we started
#cd "${0%/*}"
cd ${initial_dir}
#find ${archiso_dir} -type f -newermt 'Jan 11 10:24'
cp -v ${archiso_dir}/out/*.iso ${archiso_dest_dir}
}
script_name=$(basename $0)
case "$1" in
	"log")
		main
		exit
		;;
	*)
		[ -e ${script_name%.*}.log ] && mv -fv ${script_name%.*}.log ${script_name%.*}.log.old
		exec "$0" log 2>&1 | tee ${script_name%.*}.log
		;;
esac
# (2.) sed -i -e 's/^\(INCLUDE .*_sys32.cfg\)/#\1/' syslinux/archiso_sys_both_inc.cfg
# (2.) sed -i -e "1iDEFAULT auto_install\nTIMEOUT 200\n" syslinux/archiso_sys64.cfg
#	(2.) APPEND archisobasedir=%INSTALL_DIR% archisolabel=%ARCHISO_LABEL% script=${auto_install_script} copytoram=y modprobe.blacklist=i2c_piix4 elevator=noop" >> syslinux/archiso_sys64.cfg
#	(2.) sed -i\
#				-e '/^for arch in i686 x86_64; do/a for arch in x86_64; do'\
#				-e 's/^\(for arch in i686 x86_64; do\)/#\1/'\
