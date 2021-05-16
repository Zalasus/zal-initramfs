#!/bin/bash

set -e

verb="${1}"
device="${2}"

if [[ -z "${verb}" ]] || [[ -z "${device}" ]]; then
    echo "Usage: keytool.sh <command> <device>"
    echo "  Interactively generates Yubikey-based passphrases for cryptsetup"
    exit 1
fi

read -p "Enter passphrase: " -s pp
echo
read -p "Repeat passphrase: " -s ppr
echo

if [[ "${pp}" != "${ppr}" ]]; then
    echo "Passphrases do not match"
    exit 1
fi

unset ppr

if [[ "${USEHASH}" == "n" ]]; then
    echo "Skippping key stretching hash"
    pph="${pp}"
else
    echo "Calculating key stretching hash..."
    pph=$(printf '%s' "${pp}" | sha256sum | cut -f 1 -d ' ')
fi

unset pp

echo "Issuing challenge to Yubikey..."
key=$(ykchalresp "${pph}")
unset pph

[[ "${DEBUG}" ]] && echo "Key: ${key}"

keyfile=$(mktemp)
echo -n $key > $keyfile

command="cryptsetup $verb $device $keyfile"

echo "This is the cryptsetup command that will be issued:"
echo "   ${command}"
echo "Provide a sudo password to confirm."
sudo -k $command

shred -u $keyfile
unset keyfile
unset key
