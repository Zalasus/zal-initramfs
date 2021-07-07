#!/bin/busybox sh

# this is the init script that runs *inside* the initramfs!

echoerr() {
    echo "$@" 1>&2
    return 1
}

rescueshell() {
    echo "Dropping to rescue shell."
    exec sh
}

# handle unhandled errors and interrupts via the rescue shell
#set -e COMMENTED: wanna try how good this works without the error trap
trap rescueshell EXIT INT QUIT TSTP

# parser for extracting key=value-pair from the kernel commandline
#  make sure not to put special regex chars like '.' in the argument ;)
#  second argument is returned if key is not defined (optional)
cmdline() {
    local value
    value=" $(cat /proc/cmdline) "
    value="${value##* ${1}=}"
    value="${value%% *}"
    if [[ -z "${value}" ]]; then
        if [[ -z "${2}" ]]; then
            return 1
        else
            echo "${2}"
        fi
    else
        echo "${value}"
    fi
}

options() {
    local opt
    while true; do
        echo "Options:"
        echo "    (1) YubiKey Challenge Response"
        echo "    (2) Plain"
        echo "    (3) Drop to rescue shell"
        read -p ">" opt

        case "$opt" in
            1) next=pass_yubi; return;;
            2) next=pass_plain; return;;
            3) rescueshell; return;;
            *) echo "Not a valid option";;
        esac
    done
}

pass_yubi() {
    local challenge
    read -p "YubiKey challenge (leave empty for options): " -s challenge
    echo

    if [[ "${challenge}" ]]; then
        echo "  Calculating key stretching hash..."
        local challengehash=$(printf '%s' "${challenge}" | sha256sum | cut -f 1 -d ' ')
        echo "  Issuing challenge to Yubikey... (touch button pls)"
        local response=$(ykchalresp "${challengehash}" || echoerr "Yubikey challenge failed" || return)
        echo "  Attempting to unlock root partition..."
        if printf '%s' "${response}" | cryptsetup --allow-discards --tries 1 --key-file - open --type luks ${cryptroot} root 
        then
            unset next
        fi
    else
        options
    fi
}

pass_plain() {
    local pass
    read -p "Passphrase (leave empty for options): " -s pass
    echo

    if [[ "${pass}" ]]; then
        echo "  Attempting to unlock root partition..."
        if printf '%s' "${pass}" | cryptsetup --allow-discards --tries 1 --key-file - open --type luks $cryptroot root 
        then
            unset next
        fi
    else
        options
    fi
}

# mount required file systems (temporarily)
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devtmpfs none /dev

# so cryptsetup does not warn about this missing:
mkdir -p /run/cryptsetup

# make kernel less chatty while in this script
loglevel=$(cut -f 1 < /proc/sys/kernel/printk)
dmesg -n 1

cat /etc/banner

# custom keymap (if present)
[[ -e /keymap.bmap ]] && echo "Loading keymap..." && loadkmap < /keymap.bmap

cryptrootarg=$(cmdline cryptroot || echoerr "cryptroot kernel argument missing" || rescueshell)
echo "Looking up cryptroot=${cryptrootarg}"

cryptroot=$(findfs $cryptrootarg || echoerr "Device not found" || rescueshell)
echo "Encrypted root is at ${cryptroot}"

try=0
next=pass_yubi
while true; do
    $next
    [[ "$next" ]] || break
        
    try=$((try+1))
    echo "Retry ${try}"
done

echo "Scanning for LVM partitions..."
lvm vgscan --mknodes
lvm lvchange -a ly vg0/root
lvm vgscan --mknodes

echo "Mounting root..."
mount -o ro /dev/vg0/root /mnt/root || echoerr "Failed to mount root" || rescueshell

# get init from commandline, default is /sbin/init
init=$(cmdline init /sbin/init)

echo "Done! Switching to ${init}"

# cleanup
dmesg -n $loglevel
umount /proc
umount /sys
umount /dev

exec switch_root /mnt/root "${init}"
