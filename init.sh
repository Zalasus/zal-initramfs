#!/bin/busybox sh

# this is the init script that runs *inside* the initramfs!

echoerr() {
    echo "$@" 1>&2
    return 1
}

rescue_shell() {
    echo "Dropping to rescue shell."
    exec sh
}

# handle unhandled errors and interrupts via the rescue shell
set -e
trap rescue_shell EXIT INT QUIT TSTP

# parser for extracting key=value-pair from the kernel commandline
#  make sure not to put special regex chars like '.' in the argument ;)
cmdline() {
    local value
    value=" $(cat /proc/cmdline) "
    value="${value##* ${1}=}"
    value="${value%% *}"
    [ "${value}" != "" ] && echo "${value}"
}

# mount required file systems (temporarily)
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev
mount -t tmpfs -o rw none /run

# so cryptsetup does not warn about this missing:
mkdir /run/cryptsetup

# make kernel less chatty while in this script
loglevel=$(cut -f 1 < /proc/sys/kernel/printk)
dmesg -n 1

cat /etc/banner

# custom keymap (if present)
[[ -e /etc/keymap ]] && echo "Loading keymap..." && loadkmap < /etc/keymap

cryptrootarg=$(cmdline cryptroot || echoerr "cryptroot kernel argument missing")
echo "Looking up cryptroot=${cryptrootarg}"

cryptroot=$(findfs $cryptrootarg || echoerr "Device not found")
echo "Encrypted root is at ${cryptroot}"

try=0
maxtries=3
until [[ $try -ge $maxtries ]]
do
    read -p "Passphrase challenge (leave empty for non-yk prompt): " -s challenge
    echo

    if [[ $challenge ]]; then
        echo "  Issuing challenge to Yubikey... (touch button pls)"
        response=$(ykchalresp "$challenge" || echoerr "Yubikey challenge failed")
        echo "  Attempting to unlock root partition..."
        printf "%s" $response | cryptsetup --allow-discards --tries 1 --key-file - open --type luks $cryptroot root && break
    else
        cryptsetup --allow-discards --tries 1 open --type luks $cryptroot root && break
    fi

    try=$((try+1))
    echo "Retry ${try}/${maxtries}"
done

echo "Scanning for LVM partitions..."
lvm vgscan --mknodes
lvm lvchange -a ly vg0/root
lvm vgscan --mknodes

echo "Mounting root..."
mount -o ro /dev/vg0/root /mnt/root

echo "Done! Switching to real init"

# cleanup
dmesg -n $loglevel
umount /proc
umount /sys
umount /dev
umount /run

exec switch_root /mnt/root /sbin/init
