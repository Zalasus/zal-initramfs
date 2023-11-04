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

# handle uncaught interrupts via the rescue shell
trap rescueshell EXIT INT QUIT TSTP

# if set to true, drops to rescueshell after successfully mounting root
PAUSE_BOOT=false

options() {
    local opt
    while true; do
        echo "Options:"
        echo "    (1) YubiKey Challenge Response"
        echo "    (2) Plain"
        echo "    (3) Drop to rescue shell"
        echo "    (4) Toggle pause-boot"
        read -p ">" opt

        case "$opt" in
            1) next=pass_yubi; return;;
            2) next=pass_plain; return;;
            3) rescueshell; return;;
            4) toggle_pause_boot; return;;
            *) echo "Not a valid option";;
        esac
    done
}

pass_yubi() {
    local challenge
    read -p "YubiKey challenge (leave empty for options): " -s challenge
    echo

    if [[ "${challenge}" ]]; then
        echo "  Calculating key stretching hash"
        local challengehash=$(printf '%s' "${challenge}" | sha256sum | cut -f 1 -d ' ')
        echo "  Issuing challenge to Yubikey... (touch button pls)"
        local response=$(ykchalresp "${challengehash}" || echoerr "Yubikey challenge failed" || return)
        echo "  Attempting to unlock root partition"
        if printf '%s' "${response}" | cryptsetup --allow-discards --tries 1 --key-file - open --type luks ${cryptrootdev} root
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
        echo "  Attempting to unlock root partition"
        if printf '%s' "${pass}" | cryptsetup --allow-discards --tries 1 --key-file - open --type luks $cryptrootdev root
        then
            unset next
        fi
    else
        options
    fi
}

toggle_pause_boot() {
    if [[ "${PAUSE_BOOT}" == "true" ]]; then
        PAUSE_BOOT=false
        echo "Pause-boot now OFF"
    else
        PAUSE_BOOT=true
        echo "Pause-boot now ON"
    fi
}

find_cryptroot() {
    local dev
    for block_dev in /sys/class/block/*; do
        dev=/dev/$(basename "${block_dev}")
        echo "Trying ${block_dev} -> ${dev}"
        if cryptsetup isLuks "${dev}"; then
            echo "  Is a LUKS device. Using this."
            cryptrootdev="${dev}"
            return
        fi
    done
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
[[ -e /keymap.bmap ]] && echo "Loading keymap" && loadkmap < /keymap.bmap

if [[ "${cryptroot}" ]]; then
    echo "Looking up cryptroot=${cryptroot}"
    cryptrootdev=$(findfs $cryptroot || echoerr "Device not found" || rescueshell)
else
    echo "cryptroot=... kernel argument not provided. Trying to pick an encrypted root device"
    find_cryptroot
fi

if [[ "${cryptrootdev}" ]]; then
    echo "Encrypted root is at ${cryptrootdev}"
else
    echoerr "No encrypted root device found!"
    rescueshell
fi

next=pass_yubi
while true; do
    $next
    [[ "$next" ]] || break
done

echo "Scanning for LVM partitions..."
lvm vgscan --mknodes
lvm lvchange -a ly vg0/root
lvm vgscan --mknodes

echo "Mounting root..."
mount -o ro /dev/vg0/root /mnt/root || echoerr "Failed to mount root" || rescueshell

if [[ ${PAUSE_BOOT} == "true" ]]; then
    echo "Done! Dropping to rescueshell due to enabled pause-boot"
    rescueshell
fi

# get init from environment, default is /sbin/init
init=${init:-/sbin/init}

echo "Done! Switching to ${init}"

# cleanup
dmesg -n $loglevel
umount /proc
umount /sys
umount /dev

exec switch_root /mnt/root "${init}"
