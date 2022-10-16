#!/bin/bash

# Install prereqs - Ubuntu
apt-get update && apt-get -y install \
  qemu-utils

# Stop services 
df -TH > mounted_fs
systemctl list-units \
  --type=service \
  --state=running \
  --no-pager \
  --no-legend \
  | awk '!/ssh/ {print $1}' \
  | xargs systemctl stop

# Stop DNS from breaking
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# Copy old root to tmpfs
umount -a
mkdir /tmp/tmproot
mount none /tmp/tmproot -t tmpfs
mkdir /tmp/tmproot/{proc,sys,usr,var,run,dev,tmp,home,oldroot}
cp -ax /{bin,etc,mnt,sbin,lib,lib64} /tmp/tmproot/
cp -ax /usr/{bin,sbin,lib,lib64} /tmp/tmproot/usr/
cp -ax /var/{lib,local,lock,opt,run,spool,tmp} /tmp/tmproot/var/
cp -Rax {/root,/home} /tmp/tmproot/

# Copy new image to tmpfs
wget https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2 \
  -P /tmp/tmproot

# Download Arch Linux cloud image
modprobe nbd max_part=8
qemu-nbd --connect=/dev/nbd0 /tmp/tmproot/Arch-Linux-x86_64-cloudimg.qcow2
sleep 5
mount /dev/nbd0p2 /mnt

# Do stuff on the image
chroot /mnt bash -c "echo \"root:$PASSWORD\" | chpasswd"

# Cleanup
umount /mnt
qemu-nbd --disconnect /dev/nbd0
rmmod nbd

# Switch root to tmpfs
mount --make-rprivate /
pivot_root /tmp/tmproot /tmp/tmproot/oldroot

# Move system mounts to tmpfs
for i in dev proc sys run; do mount --move /oldroot/$i /$i; done

# Restart services within the ramroot
systemctl restart sshd
systemctl list-units \
  --type=service \
  --state=running \
  --no-pager \
  --no-legend \
  | awk '!/ssh/ {print $1}' \
  | xargs systemctl restart
systemctl daemon-reexec

# Moment of truth, umount disk
fuser -vkm /oldroot
umount -l /oldroot/

# Copy image to disk
qemu-img convert -f qcow2 -O raw /Arch-Linux-x86_64-cloudimg.qcow2 /dev/vda
reboot
