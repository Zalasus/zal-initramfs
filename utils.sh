
# adds a binary (executable or library) to the initramfs. second argument is the
#  target filename. if omitted, will be the same as source filename.
#  recursively adds dependencies.
add_binary() {

    local bin=$1

    local target="${prefix}${2}"
    [[ -z $2 ]] && target="${prefix}${bin}"

    # only add file if it not already exists or has been changed
    if [[ $bin -nt $target ]]; then
        echo "Adding ${bin} and dependencies"

        # make parent directories of file
        mkdir -p "${target%/*}"

        cp -L $bin $target
        chmod +x $target

        local deps=$(ldd $bin | sed 's/^[ \t]*//g; s/ /\;/g')

        for o in $deps; do
            local name=$(echo $o | cut -d ';' -f 1)

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
                echo "Dependency ${name} not found"
            fi

        done

    fi
}

