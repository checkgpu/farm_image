#!/bin/bash
set -e

sudo parted -s /dev/sda mklabel gpt
sudo parted -s -a optimal /dev/sda mkpart primary 0% 128Mib
sudo parted -s -a optimal /dev/sda mkpart primary 128Mib 100%
sudo parted -s /dev/sda set 1 esp on
sudo parted -s /dev/sda set 1 boot on

sudo mkfs.vfat /dev/sda1
sudo mkfs.btrfs -f -R free-space-tree /dev/sda2

#mount partition
sudo mount -o discard=async,space_cache=v2,compress-force=zstd:2,ssd,noatime /dev/sda2 /mnt
sudo tar --same-owner -C /mnt -xpf ubuntu-22.04-zod-amd64.tar.gz

#set fstab
sudo touch /mnt/etc/fstab
echo -e "UUID=$(sudo blkid -s UUID -o value /dev/sda2) / btrfs defaults,discard=async,space_cache=v2,compress-force=zstd:2,ssd,noatime 0 1" | sudo tee -a /mnt/etc/fstab
echo -e "UUID=$(sudo blkid -s UUID -o value /dev/sda1) /boot/efi vfat umask=0077 0 1" | sudo tee -a /mnt/etc/fstab

#generate new machine-id
echo $(dbus-uuidgen) | sudo tee /mnt/etc/machine-id
sudo cp /mnt/etc/machine-id /mnt/var/lib/dbus/machine-id

#build initramfs for efi
sudo mkdir /mnt/boot/efi
sudo mount -o umask=0077 /dev/sda1 /mnt/boot/efi
for i in /dev /dev/pts /proc /sys /run; do sudo mount -B $i /mnt$i; done

sudo chroot /mnt /bin/bash -c "grub-install --removable --target=x86_64-efi --recheck"
sudo chroot /mnt /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"
sudo chroot /mnt /bin/bash -c "source /etc/default/locale && update-initramfs -c -u -k all"

sudo umount /mnt/boot/efi
for i in /dev/pts /dev /proc /sys /run; do sudo umount /mnt$i; done
sudo umount /mnt