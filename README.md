# farm_image
Disk Image for bootstrapping your farm

## Versions
 - [ ] Ubuntu 22.04
 - [ ] Kernel 5.15
 - [ ] NVIDIA Driver 495
 - [ ] CUDA 11.6
 - [ ] podman 3.4.4
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
wget -O /mnt/home/user/farm https://github.com/zodtv/farm/releases/download/v0.0.5/farm
chown user:user /mnt/home/user/farm

#setup root password (optional)
sudo chroot /mnt passwd

#firewall private network ipv4
#https://datatracker.ietf.org/doc/html/rfc1918
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
cat <<EOT > /etc/iptables/rules.v4
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A OUTPUT -m state --state ESTABLISHED -j ACCEPT
-A OUTPUT -d 10.0.0.0/8 -j DROP
-A OUTPUT -d 172.16.0.0/12 -j DROP
-A OUTPUT -d 192.168.0.0/16 -j DROP
COMMIT
EOT

sudo umount /mnt
```

## Running on Windows
You an run farm on windows using WSL2. Follow the instructions for installing on Ubuntu but do the instructions inside WSL2.

## Installing ontop of existing Ubuntu

If you cannot bootstrap a fresh image or its out of scope, you can install the deps to run farm on existing ubuntu based distros.  
Arch, Fedora, Centos will run farm as well but your on your own in bootstraping.  

Make sure you have atleast ubuntu 21.04, I recommend the daily of 22.04 LTS which will release April 2022.  
  
Make sure your linux kernel is >= 5.11 for rootless support. `uname -a` 

Install Nvidia driver + CUDA (older Ubuntu might not have nvidia-driver-495, try lower version)
```
//Tesla drivers
//wget https://us.download.nvidia.com/tesla/510.47.03/NVIDIA-Linux-x86_64-510.47.03.run
//wget https://developer.download.nvidia.com/compute/cuda/11.6.0/local_installers/cuda_11.6.0_510.39.01_linux.run
//sh cuda_11.6.0_510.39.01_linux.run --silent --toolkit --no-drm --no-man-page
//rm cuda_11.6.0_510.39.01_linux.run
//Or upstream repos
apt-get install -y --no-install-recommends nvidia-driver-495
wget https://developer.download.nvidia.com/compute/cuda/11.5.1/local_installers/cuda_11.5.1_495.29.05_linux.run
sh cuda_11.5.1_495.29.05_linux.run --silent --toolkit --no-drm --no-man-page
rm cuda_11.5.1_495.29.05_linux.run

#Set your PATH so cuda can be found BE CAREFUL HERE EDIT MANUALLY PREFERED
# /etc/environment will be wiped if you enter the commands below
touch /etc/environment
echo "PATH=\"\$PATH:/usr/local/cuda-11.5/bin\"" > /etc/environment
echo "CUDA_HOME=\"/usr/local/cuda-11.5\"" >> /etc/environment
echo "CUDA_PATH=\"/usr/local/cuda-11.5\"" >> /etc/environment
```

Install IPFS + Setup service (optional but recommended)
```
wget -c https://github.com/ipfs/go-ipfs/releases/download/v0.12.0/go-ipfs_v0.12.0_linux-amd64.tar.gz -O - | tar -xz --strip-components 1 go-ipfs/ipfs
#add IPFS to system path (required)
cp ipfs /usr/local/bin

#Dedicated/Baremetal server in Datacenter
#the profile is needed to prevent triggering abuse complaints
#as the IPFS dameon would portscan the network looking for peers
./ipfs init --profile server

#Your at home behind a router or in a vnet in the cloud (where public ip != internal ip)
./ipfs init

#Enable hole punching to reach nodes behind routers
#Bump storage from 10GB to 100GB
./ipfs config Swarm.EnableHolePunching --bool true
./ipfs config Swarm.RelayClient.Enabled --bool true
./ipfs config Experimental.AcceleratedDHTClient --bool true
./ipfs config Ipns.UsePubsub --bool true
./ipfs config Datastore.StorageMax "100GB"
```
```
cat <<EOT > /etc/systemd/system/ipfs.service
[Unit]
Description=IPFS
After=network.target local-fs.target

[Service]
Type=forking
LimitNOFILE=1048576
KillMode=control-group
User=user
ExecStart=/usr/bin/screen -UdmS ipfs bash -c "GOMAXPROC=8 ./ipfs daemon --enable-gc"
WorkingDirectory=/home/user/
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
EOT

#allow this user to start on boot
loginctl enable-linger user

systemctl enable ipfs
systemctl start ipfs

#disable by
#systemctl disable ipfs

#inpect REPL by
screen -r ipfs
```

Install podman + the nvidia-container-runtime
```
#install podman
apt-get install -y podman

#install nvidia-container-runtime + setup OCI hook
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
mkdir -p /etc/apt/sources.list.d/
cat <<EOT >> /etc/apt/sources.list.d/nvidia-docker.list
deb https://nvidia.github.io/libnvidia-container/experimental/ubuntu18.04/\$(ARCH) /
deb https://nvidia.github.io/nvidia-container-runtime/experimental/ubuntu18.04/\$(ARCH) /
deb https://nvidia.github.io/nvidia-docker/ubuntu18.04/\$(ARCH) /
EOT

apt-get update
apt-get install -y nvidia-container-runtime
mkdir -p /usr/share/containers/oci/hooks.d
cat <<EOT >> /usr/share/containers/oci/hooks.d/oci-nvidia-hook.json
{
    "version": "1.0.0",
    "hook": {
        "path": "/usr/bin/nvidia-container-toolkit",
        "args": ["nvidia-container-toolkit", "prestart"],
        "env": [
            "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        ]
    },
    "when": {
        "always": true,
        "commands": [".*"]
    },
    "stages": ["prestart"]
}
EOT

#set no-cgroups for nvidia-container-runtime
#TODO: remove this stage once cgroupsV2 support is stable (likely the next major release)
sed -i 's/^#no-cgroups = false/no-cgroups = true/;' /etc/nvidia-container-runtime/config.toml

#allow rootless podman CPU quotas
mkdir -p /etc/systemd/system/user@.service.d/
cat <<EOT >> /etc/systemd/system/user@.service.d/delegate.conf
[Service]
Delegate=memory pids io cpu cpuset
EOT

#lower unprivileged ports for non-root
echo "net.ipv4.ip_unprivileged_port_start = 22" >> /etc/sysctl.conf
#IPFS QUIC allow high bandwidth recv
echo "net.core.rmem_max = 2621440" >> /etc/sysctl.conf
```

## SystemD service
```
cat <<EOT > /etc/systemd/system/farm.service
[Unit]
Description=Farm
After=network.target local-fs.target

[Service]
Type=forking
LimitNOFILE=1048576
KillMode=control-group
User=user
ExecStart=/usr/bin/screen -UdmS farm bash -c " NEAR_PKEY=<snip> NEAR_ACCOUNT=<snip> ETHADDR=0x8A14A2a7BA2f96576DB9e7f70EbB4606e2710eC7 UPDATE=exit ./farm"
WorkingDirectory=/home/user/
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
EOT

#allow this user to start on boot
loginctl enable-linger user

systemctl enable farm
systemctl start farm

#disable by
#systemctl disable farm

#inpect REPL by
screen -r farm
```

## Known Issues

 - [ ] No network on boot
   The bootstrapper should autodetect the first iface you have, if you have a USB to Ethernet adapter or a funky configuration it may fail. In this case boot into the system and login with your password. Check `ip addr` for the interface name. Edit `/etc/netplan/config.yaml` to include the interface name instead of the default catch all.
