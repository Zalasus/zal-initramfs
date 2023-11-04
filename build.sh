#!/bin/bash


if [[ -t 1 ]]; then
    info_color="\x1b[32m"
    error_color="\x1b[31m"
    reset_color="\x1b[39;49m"
else
    info_color=""
    error_color=""
    reset_color=""
fi

die() {
    printf "${error_color}FATAL:${reset_color} %s\n" "$@" 1>&2
    exit 1
}

info() {
    printf "${info_color}---${reset_color} %s\n" "$@"
}

verbose() {
    printf "%s\n" "$@"
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
        verbose "Adding ${bin} and dependencies"

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

add_program() {
    local bin_path=$(which $1 || die "$1 not found")
    add_binary ${bin_path}
}

has_program() {
    [[ -x "$(which $1 2> /dev/null)" ]]
}

usage() {
    echo "Usage: build.sh [options]"
    echo "Options:"
    echo "  -o <path>, --output <path>   Set output filename (default is ${default_outputname})"
}

scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

default_outputname=initramfs.cpio

# parse command line options
outputfile=$(pwd)/${default_outputname}
while [[ -n "$@" ]]; do
    opt=$1
    case $opt in
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

info "Building zal-initramfs"

prefix=$(mktemp -d)

# make initial directory structure
mkdir -p ${prefix}/{bin,dev,etc,lib,lib64,mnt/root,proc,root,sbin,sys,run}

# normally, linux creates these automatically if the initramfs is loaded separately.
# it won't, however, do that if the initramfs is embedded into the kernel. since the
# init script won't have access to the console if these are missing, create them
# manually.
mknod -m 622 ${prefix}/dev/console c 5 1 || die "Failed to create console device node"
mknod -m 622 ${prefix}/dev/tty0 c 4 0 || die "Failed to create vt device node"

# add required binaries. this will recursively add dependencies

# glibc loads this dynamically, so it will not be found as a dependency by add_binary
gccruntimes=( /usr/lib/gcc/$(uname -m)*/*/libgcc_s.so.1 )
[[ -z "$gccruntimes" ]] && die "No GCC runtime lib found"

gccruntime="${gccruntimes[0]}"
gccruntime_dir=$(dirname "${gccruntime}")
add_binary "${gccruntime}" /lib64/libgcc_s.so.1
add_binary "${gccruntime_dir}/libatomic.so.1" /lib64/libatomic.so.1

add_program busybox
add_program lvm
add_program cryptsetup

if has_program ykchalresp; then
    info "Found ykchalresp, adding Yubikey support"
    add_program ykchalresp
    add_program sha256sum
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
info "Generating keymap ${keymap}"
gzip -dc "/usr/share/keymaps/${keymap}" | loadkeys -b - > ${prefix}/keymap.bmap

info "Done copying to prefix. Packing..."

# finally, package everything
(
    cd $prefix
    find . -print0 | cpio --null --create --verbose --format=newc --owner root:root > $outputfile
) || die "Packing failed"

info "Done! Written initramfs image to ${outputfile}"

# the tmp prefix is no longer needed
rm -rf $prefix
