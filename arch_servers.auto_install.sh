#!/bin/bash
#
#TODO:
#
#Changelog:
#	0. small bug fixes
#	1. According to https://technet.microsoft.com/en-us/windows-server-docs/compute/hyper-v/best-practices-for-running-linux-on-hyper-v
#		elevator=noop, mkfs.ext4 -G 4096
#	2. iptables, ebtables -> nftables (rules, daemons activation, install), change zsh alias "it" etc
#	3. ntp, chrony - remove, as no need on hyper-v (may have changed to LogLevel=notice to /etc/systemd/system.conf)
#	4. made auto_install_script as a separate file
#	5. tmux auto-start and tshark alias in root zshrc, add user to group wireshark
#	6. Removed network / perfomance tools (tshark alias as well)
#	7. SSH tuning
#	8. MOTD and issue
#	9. Preseed with SSH certificate
#	10. SSH socket instead of service
#	11. salt-minion
#	12. lsof, strace packages
#
main(){
set -x
set -x
echo -e '#!/usr/bin/expect
set passwd_username [lindex $argv 0];
set passwd_passwd [lindex $argv 1];
spawn passwd $passwd_username
expect "New password:"
send "$passwd_passwd\\r"
expect "Retype new password:"
send "$passwd_passwd\\r"
interact' >> auto_install_passwd.sh
chmod +x auto_install_passwd.sh
./auto_install_passwd.sh root root-${password_to_be_changed}
parted -s -a optimal /dev/sda mklabel msdos
parted -a optimal /dev/sda mkpart primary ext4 1MiB 100%
parted /dev/sda set 1 boot on
echo "y" | mkfs.ext4 -G 4096 /dev/sda1
mount /dev/sda1 /mnt
sed -i -e "1i$(echo $(grep -m 1 yandex /etc/pacman.d/mirrorlist) | sed -e 's/http:/https:/; s/^#//')" /etc/pacman.d/mirrorlist
echo -e '[offline_install]
SigLevel = Optional
Server = file:///root/pkg' >> /etc/pacman.conf
sed -i -e 's/^\[core\]/#\[core\]/' -e 's/^\[extra\]/#\[extra\]/' -e 's/^\[community\]/#\[community\]/' -e 's/^Include.*$//g' /etc/pacman.conf
pacstrap /mnt \
  base \
  expect \
  grub \
  openssh \
  vim \
  zsh \
  grml-zsh-config \
  zsh-completions \
  terminus-font \
  tmux \
  htop \
	lsof \
	strace \
  ncdu \
  mc \
  mlocate \
  nftables \
  salt
genfstab -U /mnt >> /mnt/etc/fstab
echo 'blacklist i2c_piix4' > /mnt/etc/modprobe.d/modprobe.conf
arch-chroot /mnt mkinitcpio -p linux
arch-chroot /mnt ln -f -s /usr/share/zoneinfo/Europe/Moscow /etc/localtime
arch-chroot /mnt sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/; s/^#ru_RU.UTF-8 UTF-8/ru_RU.UTF-8 UTF-8/' /etc/locale.gen
arch-chroot /mnt locale-gen
echo LANG=en_US.UTF-8 > /mnt/etc/locale.conf
install_hostname=`hostname -s | tr '[:upper:]' '[:lower:]'`
echo ${install_hostname} > /mnt/etc/hostname
arch-chroot /mnt chsh -s $(which zsh)
cp -v /root/*.{sh,conf} /mnt/root/
arch-chroot /mnt /root/auto_install_passwd.sh root root-${password_to_be_changed}
arch-chroot /mnt useradd -m -g users -G wheel -s $(which zsh) ${install_hostname}-user
arch-chroot /mnt /root/auto_install_passwd.sh ${install_hostname}-user ${install_hostname}-user-${password_to_be_changed}
echo -e 'syntax on\nfiletype plugin indent on\nset number' | tee /mnt/root/.vimrc /mnt/home/${install_hostname}-user/.vimrc 2>&1 > /dev/null
arch-chroot /mnt chown ${install_hostname}-user:users /home/${install_hostname}-user/.vimrc
mv -fv /mnt/etc/nftables.conf /mnt/etc/nftables.conf.default
cp -v /mnt/root/arch_servers.nftables.conf /mnt/etc/nftables.conf
echo '#!/usr/bin/nft -f' > /mnt/etc/nftables.tail.conf
echo -e '[ -z "$TMUX" ] && tmux new-session -A -s $USER\nalias tm="tmux new-session -A -s $USER"' >> /mnt/root/.zshrc.local
sed -i -e 's/^#clientid/clientid/; s/^duid/#duid/; $aenv force_hostname=YES' /mnt/etc/dhcpcd.conf
echo -e 'LOCALE="ru_RU.UTF-8"\nKEYMAP="ruwin_ct_sh-UTF-8.map.gz"\nFONT="ter-v16b"\nCONSOLEMAP=""' > /mnt/etc/vconsole.conf
#SSH configuration:
arch-chroot /mnt groupadd ssh-users
arch-chroot /mnt gpasswd -M root,${install_hostname}-user ssh-users
rm -f /mnt/etc/ssh/ssh_host_rsa_key*
arch-chroot /mnt ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N "" < /dev/null
mkdir -pv /mnt/root/.ssh
arch-chroot /mnt chmod 700 /root/.ssh
echo -e ${preseeded_ssh_cert} >> /mnt/root/.ssh/authorized_keys
arch-chroot /mnt chmod 600 /root/.ssh/authorized_keys
sed -e 's/^\(.*sftp.*sftp.*\)/\1 -f AUTHPRIV -l INFO/' /mnt/etc/ssh/sshd_config
echo -e "#++
KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-ripemd160-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256,hmac-ripemd160,umac-128@openssh.com
Protocol 2
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key
#PasswordAuthentication no
#ChallengeResponseAuthentication no
#PubkeyAuthentication yes
#AuthenticationMethods publickey
AllowGroups ssh-users
" >> /mnt/etc/ssh/sshd_config
echo -e "#++
#HashKnownHosts yes
KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-ripemd160-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256,hmac-ripemd160,umac-128@openssh.com
#PasswordAuthentication no
#ChallengeResponseAuthentication no
#PubkeyAuthentication yes
HostKeyAlgorithms ssh-ed25519-cert-v01@openssh.com,ssh-rsa-cert-v01@openssh.com,ssh-ed25519,ssh-rsa
UseRoaming no
" >> /mnt/etc/ssh/ssh_config
echo -e "
###############################################################
#                   Welcome to xxXXxx                         #
#  Disconnect IMMEDIATELY if you are not an authorized user!  #
###############################################################
" > /mnt/etc/issue
echo -e "Banner /etc/issue\n" >> /mnt/etc/ssh/sshd_config
echo -e "                   _       _       _   _            _               _   _
    /\            | |     (_)     | | | |          | |             | | | |
   /  \   _ __ ___| |__    _ ___  | |_| |__   ___  | |__   ___  ___| |_| |
  / /\ \ | '__/ __| '_ \  | / __| | __| '_ \ / _ \ | '_ \ / _ \/ __| __| |
 / ____ \| | | (__| | | | | \__ \ | |_| | | |  __/ | |_) |  __/\__ \ |_|_|
/_/    \_\_|  \___|_| |_| |_|___/  \__|_| |_|\___| |_.__/ \___||___/\__(_)
" >> /mnt/etc/motd
arch-chroot /mnt systemctl enable sshd.socket dhcpcd@eth0.service nftables.service salt-minion
sed -i -e 's/^\(GRUB_CMDLINE_LINUX_DEFAULT=".*\)"/\1 elevator=noop"/' -e 's/^GRUB_TIMEOUT=5/GRUB_TIMEOUT=1/' /mnt/etc/default/grub
arch-chroot /mnt grub-install --target=i386-pc /dev/sda
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
chmod -x /mnt/root/*.sh
mkdir -pv /mnt/root/install
mv -fvt /mnt/root/install /mnt/root/*.{sh,conf}
sed -i -e 's/^#Color/Color/' /mnt/etc/pacman.conf
arch-chroot /mnt pacman -Syy --noconfirm
arch-chroot /mnt pacman -Syu --noconfirm
arch-chroot /mnt updatedb
eject /dev/sr0
}
password_to_be_changed=
preseeded_ssh_cert=
script_name=$(basename $0)
case "$1" in
	"log")
		main
		exec "$0" reboot
		;;
	"reboot")
		[ -e /mnt/root/install ] || mkdir -pv /mnt/root/install
		cp -v /tmp/${script_name%.*}.log /mnt/root/install
		reboot
		;;
	*)
		if [ -z "${password_to_be_changed}" ] || [ -z ${preseeded_ssh_cert} ]
			then echo "Not all required variables defined. Exiting."
			exit 1
		fi
		exec "$0" log 2>&1 | tee /tmp/${script_name%.*}.log
		;;
esac
#install_hostname_fqdn=`hostname -f`
#install_address=$(ip a | grep '192.168.[45][0189]' | cut -d '/' -f 1 | rev | cut -d ' ' -f 1 | rev)
#sed -i "/\:\:1\t\tlocalhost.localdomain\tlocalhost/a ${install_address}\\t${install_hostname_fqdn}\\t${install_hostname}" /mnt/etc/hosts
#echo -e '*filter\n:INPUT DROP\n:FORWARD DROP\n:OUTPUT ACCEPT\n-A INPUT -i lo -j ACCEPT\n-A INPUT -i eth0 -s 192.168.48.0/22 -p tcp -m tcp --dport 22 -m state --state NEW,ESTABLISHED -m comment --comment "ssh" -j ACCEPT\n-A INPUT -i eth0 -s 192.168.48.0/22 -p icmp -m icmp --icmp-type 8 -m state --state NEW,ESTABLISHED -m comment --comment "ping in" -j ACCEPT\n-A INPUT -i eth0 -p icmp -m icmp --icmp-type 0 -m state --state ESTABLISHED -m comment --comment "ping out" -j ACCEPT\n-A INPUT -i eth0 -s 192.168.48.0/22 -p udp -m udp --sport 53 -m state --state ESTABLISHED -m comment --comment "dns" -j ACCEPT\n-A INPUT -i eth0 -s 192.168.48.0/22 -p udp -m udp --sport 123 -m state --state ESTABLISHED -m comment --comment "ntp" -j ACCEPT\n-A INPUT -i eth0 -s 213.180.204.183/32 -p tcp -m tcp --sport 443 -m state --state ESTABLISHED -m comment --comment "yandex arch repo" -j ACCEPT\n-A INPUT -j REJECT --reject-with icmp-port-unreachable\nCOMMIT' > /mnt/etc/iptables/iptables.rules
#echo -e '*filter\n:INPUT DROP\n:FORWARD DROP\n:OUTPUT DROP\n-A INPUT -p IPv4 -j ACCEPT\n-A INPUT -p ARP -j ACCEPT\n-A OUTPUT -p IPv4 -j ACCEPT\n-A OUTPUT -p ARP -j ACCEPT\n' > /mnt/etc/ebtables.conf
#echo -e "ListenAddress ${install_address}\nAllowUsers ${install_hostname}-user@192.168.48.0/22" >> /mnt/etc/ssh/sshd_config
#echo "alias it='iptables -nv --line-numbers'" >> /mnt/etc/zsh/zshrc
#echo -e '# Sample dhcpcd hook script for NTP\n# It will configure either one of NTP, OpenNTP or Chrony (in that order)\n# and will default to NTP if no default config is found.\n\n# Like our resolv.conf hook script, we store a database of ntp.conf files\n# and merge into /etc/ntp.conf\n\n# You can set the env var NTP_CONF to override the derived default on\n# systems with >1 NTP client installed.\n# Here is an example for OpenNTP\n#   dhcpcd -e NTP_CONF=/usr/pkg/etc/ntpd.conf\n# or by adding this to /etc/dhcpcd.conf\n#   env NTP_CONF=/usr/pkg/etc/ntpd.conf\n# or by adding this to /etc/dhcpcd.enter-hook\n#   NTP_CONF=/usr/pkg/etc/ntpd.conf\n# To use Chrony instead, simply change ntpd.conf to chrony.conf in the\n# above examples.\n\n: ${ntp_confs:=ntp.conf ntpd.conf chrony.conf}\n: ${ntp_conf_dirs=/etc /usr/pkg/etc /usr/local/etc}\nntp_conf_dir="$state_dir/ntp.conf"\n\n# If NTP_CONF is not set, work out a good default\nif [ -z "$NTP_CONF" ]; then\nfor d in ${ntp_conf_dirs}; do\nfor f in ${ntp_confs}; do\nif [ -e "$d/$f" ]; then\nNTP_CONF="$d/$f"\nbreak 2\nfi\ndone\ndone\n[ -e "$NTP_CONF" ] || NTP_CONF=/etc/ntp.conf\nfi\n\n# Derive service name from configuration\nif [ -z "$ntp_service" ]; then\ncase "$NTP_CONF" in\n#	*chrony.conf)		ntp_service=chronyd;;\n*chrony.conf)		ntp_service=chrony;;\n*)			ntp_service=ntpd;;\nesac\nfi\n\n# Debian has a seperate file for DHCP config to avoid stamping on\n# the master.\nif [ "$ntp_service" = ntpd ] && type invoke-rc.d >/dev/null 2>&1; then\n[ -e /var/lib/ntp ] || mkdir /var/lib/ntp\n: ${ntp_service:=ntp}\n: ${NTP_DHCP_CONF:=/var/lib/ntp/ntp.conf.dhcp}\nfi\n\n: ${ntp_restart_cmd:=service_condcommand $ntp_service restart}\n\nntp_conf=${NTP_CONF}\nNL="\n"\n\nbuild_ntp_conf()\n{\nlocal cf="$state_dir/ntp.conf.$ifname"\nlocal interfaces= header= srvs= servers= x=\n\n# Build a list of interfaces\ninterfaces=$(list_interfaces "$ntp_conf_dir")\n\nif [ -n "$interfaces" ]; then\n# Build the header\nfor x in ${interfaces}; do\nheader="$header${header:+, }$x"\ndone\n\n# Build a server list\nsrvs=$(cd "$ntp_conf_dir";\nkey_get_value "server " $interfaces)\nif [ -n "$srvs" ]; then\nfor x in $(uniqify $srvs); do\nservers="${servers}server $x$NL"\ndone\nfi\nfi\n\n# Merge our config into ntp.conf\n[ -e "$cf" ] && rm -f "$cf"\n[ -d "$ntp_conf_dir" ] || mkdir -p "$ntp_conf_dir"\n\nif [ -n "$NTP_DHCP_CONF" ]; then\n[ -e "$ntp_conf" ] && cp "$ntp_conf" "$cf"\nntp_conf="$NTP_DHCP_CONF"\nelif [ -e "$ntp_conf" ]; then\nremove_markers "$signature_base" "$signature_base_end" \n"$ntp_conf" > "$cf"\nfi\n\nif [ -n "$servers" ]; then\necho "$signature_base${header:+ $from }$header" >> "$cf"\nprintf %s "$servers" >> "$cf"\necho "$signature_base_end${header:+ $from }$header" >> "$cf"\nelse\n[ -e "$ntp_conf" -a -e "$cf" ] || return\nfi\n\n# If we changed anything, restart ntpd\nif change_file "$ntp_conf" "$cf"; then\n[ -n "$ntp_restart_cmd" ] && eval $ntp_restart_cmd\nfi\n}\n\nadd_ntp_conf()\n{\nlocal cf="$ntp_conf_dir/$ifname" x=\n\n[ -e "$cf" ] && rm "$cf"\n[ -d "$ntp_conf_dir" ] || mkdir -p "$ntp_conf_dir"\nif [ -n "$new_ntp_servers" ]; then\nfor x in $new_ntp_servers; do\necho "server $x" >> "$cf"\ndone\nfi\nbuild_ntp_conf\n}\n\nremove_ntp_conf()\n{\nif [ -e "$ntp_conf_dir/$ifname" ]; then\nrm "$ntp_conf_dir/$ifname"\nfi\nbuild_ntp_conf\n}\n\n# For ease of use, map DHCP6 names onto our DHCP4 names\ncase "$reason" in\nBOUND6|RENEW6|REBIND6|REBOOT6|INFORM6)\nnew_ntp_servers="$new_dhcp6_sntp_servers"\n;;\nesac\n\nif $if_up; then\nadd_ntp_conf\nelif $if_down; then\nremove_ntp_conf\nfi\n'#> /mnt/usr/lib/dhcpcd/dhcpcd-hooks/50-ntp.conf
#sed -i -e 's/^#clientid/clientid/; s/^duid/#duid/; $aenv NTP_CONF=/etc/chrony.conf' -e '$aenv force_hostname=YES' /mnt/etc/dhcpcd.conf
#arch-chroot /mnt systemctl enable sshd.service iptables.service dhcpcd@eth0.service ebtables.service chrony.service
#sed -i s/^GRUB_TIMEOUT\=5/GRUB_TIMEOUT\=1/ /mnt/etc/default/grub
#	(6.)   wireshark-cli \
#	  mtr \
#	  sysstat \
#	  ethtool \
#	  tcpdump \
#	  arp-scan
#	(6.) arch-chroot /mnt gpasswd -a ${install_hostname}-user wireshark
#		echo -e '[ -z "$TMUX" ] && tmux new-session -A -s $USER\ntshark() { su - qarch-test-user -c "tshark $*" }' >> /mnt/root/.zshrc.local
#	(7.) arch-chroot /mnt ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" < /dev/null
#	(7.) echo -e "AllowUsers ${install_hostname}-user@192.168.48.0/22" >> /mnt/etc/ssh/sshd_config
#	(10.) arch-chroot /mnt systemctl enable sshd.service dhcpcd@eth0.service nftables.service
#	(11.) arch-chroot /mnt systemctl enable sshd.socket dhcpcd@eth0.service nftables.service
#	(0.) echo -e '[ -z "$TMUX" ] && tmux new-session -A -s $USER\n' >> /mnt/root/.zshrc.local
