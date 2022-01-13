#!/bin/bash
set -e

wget http://cdimage.ubuntu.com/ubuntu-base/daily/current/jammy-base-amd64.tar.gz
sudo rm -rf 2204/
mkdir 2204/
sudo tar --same-owner -xf jammy-base-amd64.tar.gz -C 2204/
rm jammy-base-amd64.tar.gz

sudo bash -c "cat > 2204/etc/default/locale" << EOT
LC_CTYPE="en_US.UTF-8"
LC_ALL="en_US.UTF-8"
LANG="en_US.UTF-8"
LANGUAGE="en_US.UTF-8"
EOT

sudo bash -c "cat > 2204/etc/hosts" << EOT
127.0.0.1 localhost
EOT

sudo systemd-nspawn --pipe -D 2204/ /bin/bash << EOF
apt-get update
apt-get -y dist-upgrade

#add a regular user (no sudo)
useradd -m -s /bin/bash user

#install basics + timezone + locales
apt-get install -y dialog apt-utils debconf-utils
DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC apt-get install -y tzdata
apt-get install -y locales
locale-gen en_US.UTF-8
DEBIAN_FRONTEND=noninteractive apt-get install -y keyboard-configuration console-setup

#install systemd
apt-get install -y init

#Install kernel + grub
apt-get install -y linux-{headers,image}-generic
apt-get install -y grub-efi
apt-get install -y initramfs
apt-get install -y initramfs-tools btrfs-progs

#Install generic apps
apt-get install -y --no-install-recommends nano vim git wget curl zip ncdu iftop iotop htop \
net-tools locate lm-sensors mtr-tiny openssh-server hddtemp python-is-python3 \
smartmontools linux-tools-common linux-tools-generic fdisk iputils-ping strace

#Install netplan + iptables persistent
DEBIAN_FRONTEND=noninteractive apt-get install -y netplan.io iptables-persistent

cat <<EOT > /etc/netplan/config.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enwild:
      match:
        name: enp*
      dhcp4: true
EOT

#Configure grub
cat <<EOT > /etc/default/grub
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="consoleblank=0 nomodeset transparent_hugepage=never"
GRUB_CMDLINE_LINUX=""
GRUB_GFXPAYLOAD_LINUX="text"
EOT

#install openssh-server
apt-get install -y openssh-server

#Basic config files
cat <<EOT >> /etc/security/limits.conf
root hard nofile 1048576
root soft nofile 1048576
* hard nofile 1048576
* soft nofile 1048576
root hard nproc unlimited
root soft nproc unlimited
* hard nproc unlimited
* soft nproc unlimited
root hard memlock unlimited
root soft memlock unlimited
* hard memlock unlimited
* soft memlock unlimited
EOT
cat <<EOT >> /etc/sysctl.conf
net.ipv4.ip_unprivileged_port_start = 22
EOT
cat <<EOT >> /etc/systemd/user.conf
[Manager]
DefaultTasksMax=infinity
DefaultLimitNOFILE=infinity
DefaultLimitNPROC=infinity
DefaultLimitMEMLOCK=infinity
DefaultLimitLOCKS=infinity
EOT
cat <<EOT >> /etc/systemd/system.conf
[Manager]
DefaultTasksMax=infinity
DefaultLimitNOFILE=infinity
DefaultLimitNPROC=infinity
DefaultLimitMEMLOCK=infinity
DefaultLimitLOCKS=infinity
EOT

#install podman + nvidia
apt-get install -y podman
apt-get install -y --no-install-recommends nvidia-driver-495
wget https://developer.download.nvidia.com/compute/cuda/11.5.1/local_installers/cuda_11.5.1_495.29.05_linux.run
sh cuda_11.5.1_495.29.05_linux.run --silent --toolkit --no-drm --no-man-page
rm cuda_11.5.1_495.29.05_linux.run
echo "PATH=\"\$PATH:/usr/local/cuda-11.5/bin\"" > /etc/environment && \
echo "CUDA_HOME=\"/usr/local/cuda-11.5\"" >> /etc/environment && \
echo "CUDA_PATH=\"/usr/local/cuda-11.5\"" >> /etc/environment

#install nvidia-container-runtime + setup OCI hook
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
mkdir -p /etc/apt/sources.list.d/
cat <<EOT >> /etc/apt/sources.list.d/nvidia-docker.list
deb https://nvidia.github.io/libnvidia-container/experimental/ubuntu18.04/\\\$(ARCH) /
deb https://nvidia.github.io/nvidia-container-runtime/experimental/ubuntu18.04/\\\$(ARCH) /
deb https://nvidia.github.io/nvidia-docker/ubuntu18.04/\\\$(ARCH) /
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

#TODO: remove this once cgroupsV2 support is stable (likely the next major release)
sed -i 's/^#no-cgroups = false/no-cgroups = true/;' /etc/nvidia-container-runtime/config.toml

#allow rootless podman CPU quota
mkdir -p /etc/systemd/system/user@.service.d/
cat <<EOT >> /etc/systemd/system/user@.service.d/delegate.conf
[Service]
Delegate=memory pids io cpu cpuset
EOT

#set podman storage driver as btrfs
#cat <<EOT >> /etc/containers/storage.conf
#[storage]
#driver = "btrfs"
#EOT

#add authorized_keys
mkdir -p /root/.ssh/
touch /root/.ssh/authorized_keys
mkdir -p /home/user/.ssh/
touch /home/user/.ssh/authorized_keys
chown -R user:user /home/user/.ssh/

#remove MOTD unminimize
rm -f /etc/update-motd.d/10-help-text
rm -f /etc/update-motd.d/60-unminimize

 history -c

EOF

sudo cp motd 2204/etc/update-motd.d/10-zod

echo "building ubuntu-22.04-zod-amd64.tar.gz"
sudo tar czC 2204/ . --transform='s,^\./,,' >| ubuntu-22.04-zod-amd64.tar.gz
sudo rm -rf 2204/
