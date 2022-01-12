# farm_image
Disk Image for bootstrapping your farm

## Versions
 - [ ] Ubuntu 22.04
 - [ ] Kernel 5.13
 - [ ] NVIDIA Driver 495
 - [ ] CUDA 11.5.1
 - [ ] podman 3.2.1
 - [ ] zod_farm 0.0.4

## Basic Bootstraping

Assuming your plugged in drive you wish to image is /dev/sda.

WARNING: IF YOU ARE USING A HDD or SSD YOU CAN ERASE ALL YOUR DATA.  
WARNING: DOUBLECHECK /dev/sda IS NOT YOUR MAIN DISK.  
CRITICAL: IF YOU DO NOT UNDERSTAND /dev/sda DO NOT PROCEED.  

Build + provision the image. (Recommended, follow the commands step by step inside the .sh)
```
#Build the image
sudo ./build.sh

#Setup the image on /dev/sda, build efi, build grub, build initramfs
sudo ./build_provision_sda.sh
```

Mount the provisioned image and setup hostname + SSH keys.
```
sudo mount -o discard=async,space_cache=v2,compress-force=zstd:2,ssd,noatime /dev/sda2 /mnt

#Set hostname
echo -e "video2" | sudo tee /mnt/etc/hostname
echo -e "127.0.0.1 video2" | sudo tee -a /mnt/etc/hosts

#Copy SSH keys
cat ~/.ssh/id_rsa.pub | sudo tee -a /mnt/root/.ssh/authorized_keys
cat ~/.ssh/id_rsa.pub >> /mnt/home/user/.ssh/authorized_keys

#Download Zod Farm
wget -O /mnt/home/user/farm https://github.com/zodtv/farm/releases/download/v0.0.4/farm

#setup root password (optional)
sudo chroot /mnt passwd

sudo umount /mnt
```

## Known Issues

 - [ ] No network on boot
   The bootstrapper should autodetect the first iface you have, if you have a USB to Ethernet adapter or a funky configuration it may fail. In this case boot into the system and login with your password. Check `ip addr` for the interface name. Edit `/etc/netplan/config.yaml` to include the interface name instead of the default catch all.