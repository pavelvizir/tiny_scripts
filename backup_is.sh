#!/bin/bash
#
#TODO:
#	1. implement "cleaning" of sensible information. Not all files modified yet.
#	2. systemd timers user service for scheduled backup
backup_is=backup_is
backup_is_d=${backup_is}/daily/${backup_is}_$(date -I)
backup_is_e=${backup_is}/enc
backup_is_c=${backup_is}/is_clean
backup_is_exclude_dir=archiso
backup_is_exclude_dir2=ISOs
#[[[sensible_var_block_begin]]]
backup_is_e_mp=
backup_is_mount_string="sudo mount -o iocharset=utf8,codepage=866,gid=users,fmask=117,dmask=
#[[[sensible_var_block_end]]]
backup_is_e_mp_dir=${backup_is_e_mp}/${backup_is_e}
if [ -z "${backup_is_e_mp}" ]
	then echo "Not all required variables defined. Exiting."
	exit 1
fi
if [ "$2" == "b" ]; then
	backup_is_d=${backup_is_d}_auto_by_buildiso
	backup_is_c=${backup_is_c}_auto_by_buildiso
fi
[ ! -e ${backup_is} ] && mkdir -pv ${backup_is}
#daily
echo -e "\nStarted making daily backup.\n"
[ ! -e ${backup_is_d} ] && mkdir -pv ${backup_is_d}
cp -vt ${backup_is_d} * 2>/dev/null
#clean
echo -e "\nStarted making clean backup.\n"
[ ! -e ${backup_is_c} ] && mkdir -pv ${backup_is_c}
rm -rf ${backup_is_c}/*
cp -t ${backup_is_c} * 2>/dev/null
find ${backup_is_c} -maxdepth 1 -type f ! -iname "*.xz" -exec sed -i -e '/^#\[\[\[sensible_var_block_begin\]\]\]$/,/^#\[\[\[sensible_var_block_end\]\]\]/{s/\(^.*\)=.*/\1=/g}' {} \;
rm -fv ${backup_is_c}/*.log*
if [ -e "${backup_is_c}.tar.xz" ]; then rm -f ${backup_is_c}.tar.xz; fi
tar -cvJf ${backup_is_c}.tar.xz -C ${backup_is_c} ../${backup_is_c##*/}
#encrypt
if [ "$1" == "e" ]; then
	echo -e "\nStarted making encrypted archive.\n"
	[ ! -e ${backup_is_e} ] && mkdir -pv ${backup_is_e}
	backup_is_e_file=${backup_is}_$(date +"%Y-%m-%d_%0H-%0M-%0S").tar.xz.pgp
	if [ "$2" == "b" ]; then
		backup_is_e_file=${backup_is}_$(date +"%Y-%m-%d_%0H-%0M-%0S")_auto_by_buildiso.tar.xz.pgp
	fi
	tar --exclude=${backup_is} --exclude=${backup_is_exclude_dir} --exclude=${backup_is_exclude_dir2} -cJv ../$(basename ${PWD}) | gpg -c --s2k-cipher-algo AES256 --s2k-digest-algo SHA512 --s2k-count 65536 -o ${backup_is_e}/${backup_is_e_file} && \
	echo -e "\nTo unpack run command like:\n\tgpg -d ${backup_is_e_file} | tar -xvJ\n" || \
	echo -e "\nERROR: Try running with \"--batch --passphrase\":\n\t[space]tar --exclude=${backup_is} --exclude=${backup_is_exclude_dir} --exclude=${backup_is_exclude_dir2} -cJv ../${backup_is} | gpg --batch --passphrase {password} -c --s2k-cipher-algo AES256 --s2k-digest-algo SHA512 --s2k-count 65536 -o ${backup_is_e}/${backup_is_e_file}\n\n\tDo not forget to make your shell to not save commands prepended with space in history:\n\t\t[zsh]:\techo setopt HIST_IGNORE_SPACE >> .zshrc\n\t\t[bash]:\techo HISTCONTROL=ignorespace >> .bashrc || .bash_profile"
	if [ -e ${backup_is_e}/${backup_is_e_file} ]; then
		if [[ ${backup_is_mount_string} ]]; then
			if ! mount | grep "$backup_is_e_mp" > /dev/null; then
				eval ${backup_is_mount_string}
			fi
		fi
		if mount | grep "$backup_is_e_mp" > /dev/null; then
			[ ! -e ${backup_is_e_mp_dir} ] && mkdir -pv ${backup_is_e_mp_dir}
			if [ "$2" == "a" ]; then
				cp -vt ${backup_is_e_mp_dir} ${backup_is_e}/*
			else
				cp -vt ${backup_is_e_mp_dir} ${backup_is_e}/${backup_is_e_file}
			fi
		else
			echo -e "\nERROR: Device not mounted into ${backup_is_e_mp}.\nTry running something like:\n\tsudo mount -o iocharset=utf8,codepage=866,gid=users,fmask=117,dmask=007 /dev/sd{XN} ${backup_is_e_mp}\n"
		fi
	else
		echo -e "\nERROR: File creation failed.\n"
	fi
fi
