
zal's custom initramfs
======================
These are the scripts that I use to generate the initramfs for my Gentoo install.
Since I wanted to use my Yubikey as a second factor in my full disk encryption,
I took the opportunity for a learning experience and built the initramfs myself.

I basically just followed [this guide](https://wiki.gentoo.org/wiki/Custom_Initramfs),
adding my own stuff where needed.

The script `build.sh` copies needed files into a tmp directory, packs everything
and creates the final image called `initramfs.cpio.gz` in the working directory.
Dependencies of included tools are recursively added. No need for statically
linking packages. Building the image should not require superuser access.

To install the generated image, use the `install.sh` script (danger zone!), this
will probable require superuser privileges.

The resulting initramfs' only job is to unlock a LUKS partition and mount the LVM.
My kernel needs no modules to boot, so this does not handle them at all.

Dependencies (probably incomplete)
----------------------------------
- sys-fs/lvm2
- sys-fs/cryptsetup
- sys-apps/busybox
- sys-auth/ykpers
- CONFIG_DEVTMPFS

Disclaimer
----------
I mainly put these scripts on Github so there is no chance of me losing them.
Use them if you want, but be aware that these come *without any warranty*. If
you brick your system, that's on you. If someone hacks your drive because my
my scripts are shit, that's on you as well.
