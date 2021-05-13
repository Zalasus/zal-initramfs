#!/bin/bash

scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

. ${scriptdir}/utils.sh

prefix="/tmp/build-initramfs"

# make initial directory structure
mkdir -p ${prefix}/{bin,dev,etc,lib,lib64,mnt/root,proc,root,sbin,sys,run}

echo "Building initramfs in prefix ${prefix}"

# add required binaries. this will recursively add dependencies

# for some reason, cryptsetup loads this dynamically
add_binary /usr/lib/gcc/x86_64-pc-linux-gnu/10.2.0/libgcc_s.so.1 /lib64/libgcc_s.so.1

add_binary /bin/busybox
add_binary /sbin/lvm
add_binary /sbin/cryptsetup
add_binary /usr/bin/ykchalresp

# copy configs
cp -r ${scriptdir}/etc ${prefix}

# add init script
cp ${scriptdir}/init.sh ${prefix}/init
chmod +x ${prefix}/init

# generate banner text
if [[ -x /usr/bin/figlet ]]; then
    figlet "zal-initramfs" > ${prefix}/etc/banner
else
    echo "====== zal-initramfs ======" > ${prefix}/etc/banner
fi

# generate keymap
keymap="i386/qwertz/de.map.gz"
echo "Generating keymap ${keymap}"
gzip -dc "/usr/share/keymaps/${keymap}" | loadkeys -b - > ${prefix}/keymap.bmap

echo "Done copying to prefix. Packaging..."

# finally, package everything
outputfile=$(pwd)/initramfs.cpio.gz
(
    cd $prefix
    find . -print0 | cpio --null --create --verbose --format=newc --owner root:root | gzip --best > $outputfile
)

echo "Done! Written initramfs image to ${outputfile}"

# the tmp prefix is no longer needed
rm -rf $prefix
