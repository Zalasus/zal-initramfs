#!/bin/bash

set -e

new="initramfs.cpio"

if [[ ! -e "${new}" ]]; then
    echo "Not built yet. Use build.sh to generate initramfs image" 1>&2
    exit 1
fi

out="/boot/initramfs-$(uname -r).img"

if [[ -e "${out}" ]]; then
    outold="${out}.old"
    echo "Backing up ${out} as ${outold}"
    mv "${out}" "${outold}"
fi

echo "Installing ${new} as ${out}"
gzip --to-stdout --best "${new}" > "${out}"

echo "Done."
