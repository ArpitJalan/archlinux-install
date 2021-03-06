#!/bin/sh
# 031-configure.sh: Configure the new system in chroot before booting into it.
#
#   Copyright 2013 Sudaraka Wijesinghe <sudaraka.org/contact>
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#


echo '';
echo '031-configure Copyright 2013 Sudaraka Wijesinghe';
echo 'This program comes with ABSOLUTELY NO WARRANTY;';
echo 'This is free software, and you are welcome to redistribute it';
echo 'under certain conditions under GNU GPLv3 or later.';
echo '';

HOSTNAME=$1;
shift
LAN_SERVER=$1;
shift
NET_DEV=$1
shift
USER=$1

SWAP_PARTITION=`swapon -s|grep '/dev/'|cut -d' ' -f1`;
HOME_PARTITION=`mount|grep 'on /home'|cut -d' ' -f1`;
DSK2_PARTITION=`mount|grep 'on /disk2'|cut -d' ' -f1`;

echo "Hostname          : $HOSTNAME";
echo "Server IP         : $LAN_SERVER";
echo "Network interface : $NET_DEV";
echo "Username          : $USER";
echo "Swap Partition    : $SWAP_PARTITION";
echo "Home Partition    : $HOME_PARTITION";
echo -n 'Extra Partition   : ';
if [ -z $DSK2_PARTITION ]; then
    echo 'n/a';
else
    echo $DSK2_PARTITION;
fi;
echo '';

read -n1 -s -p 'Press any key to continue';
echo '';
echo '';

# Create fstab
echo 'Creating /etc/fstab...';

cat >> /etc/fstab << EOF

/dev/sda1 / ext4 defaults,noatime,nodiratime,discard,errors=remount-ro 0 1
$HOME_PARTITION /home ext4 defaults,noatime,nodiratime,discard,errors=remount-ro 0 1
$SWAP_PARTITION swap swap sw,noatime,nodiratime 0 0
EOF

# Mount disk2
if [ ! -z $DSK2_PARTITION ]; then
    cat >> /etc/fstab << EOF

$DSK2_PARTITION /disk2 ext4 noauto,x-systemd.automount,defaults,noatime,nodiratime,errors=remount-ro 0 2
EOF
fi;

# Mount pacman cache on NFS
cat >> /etc/fstab << EOF

$LAN_SERVER:/home/pacman/cache/`uname -m` /var/cache/pacman/pkg nfs noauto,x-systemd.automount,noexec,nolock,noatime,nodiratime,rsize=32768,wsize=32768,timeo=14,intr 0 0
$LAN_SERVER:/home/pacman/sync /var/lib/pacman/sync nfs noauto,x-systemd.automount,noexec,nolock,noatime,nodiratime,rsize=32768,wsize=32768,timeo=14,intr 0 0
EOF

# Hostname
echo 'Set hostname...';
echo $HOSTNAME > /etc/hostname;
sed "s/\(localhost\)$/\1 $HOSTNAME/g" -i /etc/hosts;

# Timezone and system time
echo 'Asia/Colombo' > /etc/timezone;
ln -s /usr/share/zoneinfo/Asia/Colombo /etc/localtime;
hwclock --hctosys --utc;

# NTP setup
ln -s /usr/lib/systemd/system/ntpd.service \
    /etc/systemd/system/multi-user.target.wants/;
sed 's/\(server\s\+.\+\)/#\1/' -i /etc/ntp.conf;
echo "server $LAN_SERVER" >> /etc/ntp.conf;

# Generate locale
echo 'Generating locale...';
cat >> /etc/locale.gen << EOF

en_US.UTF-8 UTF-8
en_US ISO-8859-1
si_LK.UTF-8 UTF-8
EOF

locale-gen >/dev/null 2>&1;

# Systemd adjustments
echo 'Configuring systemd...';

# Stop console clearing at login prompt
sed 's/\(TTYVTDisallocate=\)yes/\1no/' \
    /usr/lib/systemd/system/getty\@.service \
    > /etc/systemd/system/getty\@.service;
rm /etc/systemd/system/getty.target.wants/getty\@tty1.service >/dev/null 2>&1;
ln -s ../getty\@.service \
    /etc/systemd/system/getty.target.wants/getty\@tty1.service;

# Limit number of TTYs
sed 's/#\(NAutoVTs=\).\+/\12/' -i /etc/systemd/logind.conf >/dev/null 2>&1;

# Limit journal disk usage
sed 's/#\(SystemMaxUse=\).*/\116M/' -i /etc/systemd/journald.conf \
    >/dev/null 2>&1;

# Make wireless connection on boot
sed 's/\(Type=\).\+/\1idle/' /usr/lib/systemd/system/dhcpcd\@.service |\
    sed 's/\(Before=.\+\)/\1 var-cache-pacman-pkg.mount var-lib-pacman-sync.mount/' |\
    sed "/Before=/i After=wpa_supplicant@$NET_DEV.service" \
    > /etc/systemd/system/dhcpcd\@.service;

ln -s ../dhcpcd\@.service \
    /etc/systemd/system/multi-user.target.wants/dhcpcd\@$NET_DEV.service \
    >/dev/null 2>&1;

mkdir -p /etc/systemd/system/dhcpcd\@$NET_DEV.service.wants >/dev/null 2>&1;
ln -s /usr/lib/systemd/system/wpa_supplicant\@.service \
    /etc/systemd/system/dhcpcd\@$NET_DEV.service.wants/wpa_supplicant\@$NET_DEV.service \
    >/dev/null 2>&1;

ln -s wifi.conf /etc/wpa_supplicant/wpa_supplicant-$NET_DEV.conf \
    >/dev/null 2>&1;

# Unmount pacman cache before shutdown/reboot
mkdir -pv /etc/systemd/system/var-cache-pacman-pkg.mount.wants >/dev/null 2>&1;
ln -s ../dhcpcd\@.service \
    /etc/systemd/system/var-cache-pacman-pkg.mount.wants/dhcpcd\@$NET_DEV.service \
    >/dev/null 2>&1;
ln -s usr/lib/systemd/system/rpc-gssd.service \
    /etc/systemd/system/var-cache-pacman-pkg.mount.wants \
    >/dev/null 2>&1;

mkdir -pv /etc/systemd/system/var-lib-pacman-sync.mount.wants >/dev/null 2>&1;
ln -s ../dhcpcd\@.service \
    /etc/systemd/system/var-lib-pacman-sync.mount.wants/dhcpcd\@$NET_DEV.service \
    >/dev/null 2>&1;
ln -s usr/lib/systemd/system/rpc-gssd.service \
    /etc/systemd/system/var-lib-pacman-sync.mount.wants \
    >/dev/null 2>&1;

# Create configuration and install syslinux bootloader
echo 'Creating syslinux configuration...';

rm -fr /boot/syslinux >/dev/null 2>&1;

cat > /boot/syslinux.cfg << EOF
default linux
prompt 0
timeout 60

label linux
    menu label Arch Linux (Custom Kernel Configuration)
    linux kernel
    append root=/dev/sda1 ro quiet
EOF

echo 'Installing bootloader...';
extlinux -i /boot >/dev/null 2>&1;
dd if=/usr/lib/syslinux/mbr.bin of=/dev/sda bs=440 count=1 >/dev/null 2>&1;

# Create user and disable root login
echo "Creating user $USER...";
useradd -m -s /bin/bash \
    -G audio,network,power,scanner,storage,systemd-journal,video,wheel \
    -U $USER >/dev/null 2>&1;
passwd $USER;

# enable sudo and truecrypt mounting for user
cat >> /etc/sudoers << EOF

$USER ALL=(ALL) ALL
$USER ALL=(root) NOPASSWD:/usr/bin/truecrypt
EOF

echo 'Disabling root login...';
rm /etc/securetty >/dev/null 2>&1;
sed 's#\(root:x:0:0:root:/root:/bin/\).\+#\1false#' -i /etc/passwd \
    >/dev/null 2>&1;
sed 's/\(root:\)[^:]\+\(:.\+\)/\1x\2/' -i /etc/shadow >/dev/null 2>&1;

# Disable web cam driver from starting automatically
echo 'Disabling web cam...';
cat >> /etc/modprobe.d/modprobe.conf << EOF
blacklist uvcvideo
EOF

echo '';
