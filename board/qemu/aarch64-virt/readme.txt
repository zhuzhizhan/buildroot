Run the emulation with:

  qemu-system-aarch64 -M virt -cpu cortex-a53 -nographic -smp 1 -kernel output/images/Image -append "rootwait root=/dev/vda console=ttyAMA0" -netdev user,id=eth0 -device virtio-net-device,netdev=eth0 -virtfs local,path=output/images/../../linux-app,mount_tag=hostshare,security_model=none -drive file=output/images/rootfs.ext4,if=none,format=raw,id=hd0 -device virtio-blk-device,drive=hd0 # qemu_aarch64_virt_defconfig

The host linux-app/ directory is shared through virtio-9p and mounted at
/mnt/linux-app in the guest. The guest uses QEMU user-mode networking (DHCP),
reachable from the host through 10.0.2.2.

The guest also includes a native aarch64 GCC toolchain, make, binutils,
git and vim.  For example, after logging in as root:

  gcc /mnt/linux-app/hello.c -o /mnt/linux-app/hello
  /mnt/linux-app/hello

An apt/dpkg userland from Ubuntu 24.04 is provided as well.  Run
"apt update" once, then packages can be installed with "apt install".
apt is meant for additional user-space packages: the base system and its
C library are still provided by Buildroot and are pinned against upgrades.

The login prompt will appear in the terminal that started Qemu.
