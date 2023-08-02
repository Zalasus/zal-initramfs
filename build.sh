#!/bin/bash

die() {
    echo $@ 1>&2
    exit 1
}

# adds a binary (executable or library) to the initramfs. second argument is the
#  target filename. if omitted, will be the same as source filename.
#  recursively adds dependencies.
add_binary() {
    local bin=$1
    [[ ! -e "$bin" ]] && die "Binary $bin not found"

    local target="${prefix}${2}"
    [[ -z $2 ]] && target="${prefix}${bin}"

    # only add file if it not already exists or has been changed
    if [[ $bin -nt $target ]]; then
        echo "Adding ${bin} and dependencies"

        # make parent directories of file
        mkdir -p "${target%/*}"

        cp -L $bin $target
        chmod +x $target

        local deps=$(ldd $target | sed 's/^[ \t]*//g; s/ /\;/g')

        for o in $deps; do
            local name=$(echo $o | cut -d ';' -f 1)

            # ignore the "statically linked" message and any vdso that might show up
            if [[ $name == "statically" ]] || [[ $name =~ linux-vdso.* ]]; then
                continue
            fi

            local dep=$name
            if [[ ! -e $name ]]; then
                dep=$(echo $o | cut -d ';' -f 3)
            fi

            if [[ -e $dep ]]; then
                add_binary $dep
            else
                die "Dependency ${name} not found"
            fi

        done

    fi
}

usage() {
    echo "Usage: build.sh [options]"
    echo "Options:"
    echo "  -y, --yubi                   Include Yubikey challenge-response based unlocking"
    echo "  -o <path>, --output <path>   Set output filename (default is ${default_outputname})"
}

scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

default_outputname=initramfs.cpio.gz

# parse command line options
yubi=no
outputfile=$(pwd)/${default_outputname}
while [[ -n "$@" ]]; do
    opt=$1
    case $opt in
        --yubi | -y)
            yubi=yes;;
        --output | -o)
            shift
            case $1 in
                "")
                    die "Option $opt needs a path parameter";;
                /*)
                    outputfile=$1;;
                *)
                    outputfile=$(pwd)/$1;;
            esac;;
        *)
            echo "Unknown option $1"
            usage
            exit 1;;
    esac
    shift
done

echo "Building zal-initramfs"
echo "  with Yubikey challenge-response: ${yubi}"

prefix=$(mktemp -d)

# make initial directory structure
mkdir -p ${prefix}/{bin,dev,etc,lib,lib64,mnt/root,proc,root,sbin,sys,run}

# add required binaries. this will recursively add dependencies

# glibc loads this dynamically, so it will not be found as a dependency by add_binary
gccruntimes=( /usr/lib/gcc/$(uname -m)*/*/libgcc_s.so.1 )
[[ -z "$gccruntimes" ]] && die "No GCC runtime lib found"
add_binary "${gccruntimes[0]}" /lib64/libgcc_s.so.1

add_binary /bin/busybox
add_binary /sbin/lvm
add_binary /sbin/cryptsetup

if [[ $yubi == "yes" ]]; then
    add_binary /usr/bin/ykchalresp
    add_binary /usr/bin/sha256sum
fi

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

echo "Done copying to prefix. Packing..."

# finally, package everything
(
    cd $prefix
    find . -print0 | cpio --null --create --verbose --format=newc --owner root:root | gzip --best > $outputfile
) || die "Packing failed"

echo "Done! Written initramfs image to ${outputfile}"

# the tmp prefix is no longer needed
rm -rf $prefix
