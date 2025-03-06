#!/bin/bash


cat <<'EOF'
 ______                                             ______                       __              _______   ________  __       __ 
/      |                                           /      \                     /  |            /       \ /        |/  |  _  /  |
$$$$$$/        __    __   _______   ______        /$$$$$$  |  ______    _______ $$ |____        $$$$$$$  |$$$$$$$$/ $$ | / \ $$ |
  $$ |        /  |  /  | /       | /      \       $$ |__$$ | /      \  /       |$$      \       $$ |__$$ |   $$ |   $$ |/$  \$$ |
  $$ |        $$ |  $$ |/$$$$$$$/ /$$$$$$  |      $$    $$ |/$$$$$$  |/$$$$$$$/ $$$$$$$  |      $$    $$<    $$ |   $$ /$$$  $$ |
  $$ |        $$ |  $$ |$$      \ $$    $$ |      $$$$$$$$ |$$ |  $$/ $$ |      $$ |  $$ |      $$$$$$$  |   $$ |   $$ $$/$$ $$ |
 _$$ |_       $$ \__$$ | $$$$$$  |$$$$$$$$/       $$ |  $$ |$$ |      $$ \_____ $$ |  $$ |      $$ |__$$ |   $$ |   $$$$/  $$$$ |
/ $$   |      $$    $$/ /     $$/ $$       |      $$ |  $$ |$$ |      $$       |$$ |  $$ |      $$    $$/    $$ |   $$$/    $$$ |
$$$$$$/        $$$$$$/  $$$$$$$/   $$$$$$$/       $$/   $$/ $$/        $$$$$$$/ $$/   $$/       $$$$$$$/     $$/    $$/      $$/ 
                                                                                                                                 
EOF


exec > >(tee -a result.log) 2>&1


# --------------------------------------------------------------------------------------------------------------------------
# Prompt for user and system settings                                                                                      
# --------------------------------------------------------------------------------------------------------------------------

get_password() {
    local prompt=$1
    local password_var
    local password_recheck_var

    while true; do
        echo -n "$prompt: "; read -r -s password_var; echo
        echo -n "Re-enter password: "; read -r -s password_recheck_var; echo
        if [ "$password_var" = "$password_recheck_var" ]; then
            eval "$2='$password_var'"
            break
        else
            echo "Passwords do not match. Please enter a new password."
        fi
    done
}

echo -ne "\n\nEnter the username: "; read -r USER
get_password "Enter the password for user $USER" USERPASS
get_password "Enter the password for user root" ROOTPASS
get_password "Enter LUKS volume password" PASSPHRASE
echo -n "Enter the hostname: "; read -r HOSTNAME


echo -e "\n\n# --------------------------------------------------------------------------------------------------------------------------"
echo -e "# Check if there are existing PV and VG"
echo -e "# --------------------------------------------------------------------------------------------------------------------------\n"

umount -R /mnt 2>/dev/null
VG_NAME=$(vgdisplay -c | cut -d: -f1 | xargs)

if [ -z "$VG_NAME" ]; then
    echo -e "No volume group found. Skipping VG removal."
else
    echo -e "Removing volume group ${VG_NAME} and all associated volumes..."
    yes | vgremove "$VG_NAME" 2>/dev/null
    PV_NAME=$(pvs --noheadings -o pv_name | grep -w "$VG_NAME" | xargs)
    yes | pvremove "$PV_NAME" 2>/dev/null
fi


echo -e "\n\n# --------------------------------------------------------------------------------------------------------------------------"
echo -e "# Cleaning old partition table and partitioning"
echo -e "# --------------------------------------------------------------------------------------------------------------------------\n"


DISK="/dev/nvme0n1"
PARTITION_1="p1"
PARTITION_2="p2"

wipefs -a -f $DISK 

(
echo g           # Create a GPT partition table
echo n           # Create the EFI partition
echo             # Default, 1
echo             # Default
echo +1G         # 1GB for the EFI partition
echo t           # Change partition type to EFI
echo 1           # EFI type
echo n           # Create the system partition
echo             # Default, 2
echo             # Default
echo             # Default, use the rest of the space
echo w           # Write the partition table
) | fdisk $DISK



echo -e "\n\n# --------------------------------------------------------------------------------------------------------------------------"
echo -e "# Create LUKS and LVM for the system partition"
echo -e "# --------------------------------------------------------------------------------------------------------------------------\n"

echo "$PASSPHRASE" | cryptsetup luksFormat ${DISK}${PARTITION_2} \
  --type luks2 \
  --hash sha512 \
  --pbkdf argon2id \
  --iter-time 5000 \
  --cipher aes-xts-plain64 \
  --key-size 256 \
  --sector-size 512 \
  --use-urandom

echo "$PASSPHRASE" | cryptsetup open ${DISK}${PARTITION_2} cryptroot

pvcreate --dataalignment 1m /dev/mapper/cryptroot
vgcreate sys /dev/mapper/cryptroot
yes | lvcreate -l 100%FREE -n root sys


echo -e "\n\n# --------------------------------------------------------------------------------------------------------------------------"
echo -e "# Format and mount partitions"
echo -e "# --------------------------------------------------------------------------------------------------------------------------\n"

mkfs.fat -F32 ${DISK}${PARTITION_1}   
mkfs.btrfs /dev/mapper/sys-root   

mount /dev/mapper/sys-root /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
umount /mnt

mount -o noatime,ssd,compress=zstd,space_cache=v2,subvol=@ /dev/mapper/sys-root /mnt
mkdir -p /mnt/{home,var}
mount -o noatime,ssd,compress=zstd,space_cache=v2,subvol=@home /dev/mapper/sys-root /mnt/home
mount -o noatime,ssd,compress=zstd,space_cache=v2,subvol=@var /dev/mapper/sys-root /mnt/var

mkdir -p /mnt/boot && mount ${DISK}${PARTITION_1} /mnt/boot


echo -e "\n\n# --------------------------------------------------------------------------------------------------------------------------"
echo -e "# Install base system"
echo -e "# --------------------------------------------------------------------------------------------------------------------------\n"

pacstrap /mnt base base-devel linux-firmware lvm2 zram-generator btrfs-progs reflector man sudo nano git networkmanager grub efibootmgr grub-btrfs inotify-tools amd-ucode


echo -e "\n\n# --------------------------------------------------------------------------------------------------------------------------"
echo -e "# Generate fstab file"
echo -e "# --------------------------------------------------------------------------------------------------------------------------\n"

genfstab -U /mnt >> /mnt/etc/fstab


echo -e "\n\n# --------------------------------------------------------------------------------------------------------------------------"
echo -e "# Chroot into the system and configure"
echo -e "# --------------------------------------------------------------------------------------------------------------------------\n"

arch-chroot /mnt <<EOF


# --------------------------------------------------------------------------------------------------------------------------
# Basic settings
# --------------------------------------------------------------------------------------------------------------------------

echo "$HOSTNAME" > /etc/hostname

echo "KEYMAP=us" > /etc/vconsole.conf

ln -sf /usr/share/zoneinfo/Europe/Rome /etc/localtime

hwclock --systohc

timedatectl set-ntp true

sed -i '/^#en_US.UTF-8/s/^#//g' /etc/locale.gen && locale-gen

echo -e "127.0.0.1   localhost\n::1         localhost\n127.0.1.1   $HOSTNAME.localdomain   $HOSTNAME" > /etc/hosts


# --------------------------------------------------------------------------------------------------------------------------
# Create user and set passwords
# --------------------------------------------------------------------------------------------------------------------------

useradd -m $USER
echo "$USER:$USERPASS" | chpasswd
echo "root:$ROOTPASS" | chpasswd


# --------------------------------------------------------------------------------------------------------------------------
# Configure sudoers file
# --------------------------------------------------------------------------------------------------------------------------

echo -e "\n\n%$USER ALL=(ALL:ALL) NOPASSWD: ALL" | tee -a /etc/sudoers


# --------------------------------------------------------------------------------------------------------------------------
# Configure mirrors
# --------------------------------------------------------------------------------------------------------------------------

reflector --country "Italy" --latest 10 --sort rate --protocol https --age 7 --save /etc/pacman.d/mirrorlist


# --------------------------------------------------------------------------------------------------------------------------
# Install Yay
# --------------------------------------------------------------------------------------------------------------------------

su -c "cd && git clone https://aur.archlinux.org/yay.git && cd yay && yes | makepkg -si && cd .. && rm -rf yay" $USER


# --------------------------------------------------------------------------------------------------------------------------
# Enable Multilib repository
# --------------------------------------------------------------------------------------------------------------------------

sed -i '/\[multilib\]/,/Include/ s/^#//' /etc/pacman.conf
pacman -Syy


# --------------------------------------------------------------------------------------------------------------------------
# Install CachyOS kernel
# --------------------------------------------------------------------------------------------------------------------------

curl -O https://mirror.cachyos.org/cachyos-repo.tar.xz && tar xvf cachyos-repo.tar.xz && cd cachyos-repo && yes | /bin/bash cachyos-repo.sh
pacman -S --noconfirm cachyos-settings linux-cachyos linux-cachyos-headers proton-cachyos
cd .. && rm -rf cachyos-*


# --------------------------------------------------------------------------------------------------------------------------
# Configure ZRAM
# --------------------------------------------------------------------------------------------------------------------------

bash -c 'cat > /etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-size = min(ram, 16384)
compression-algorithm = zstd
EOF'

echo "vm.swappiness = 180" >> /etc/sysctl.d/99-vm-zram-parameters.conf
echo "vm.watermark_boost_factor = 0" >> /etc/sysctl.d/99-vm-zram-parameters.conf
echo "vm.watermark_scale_factor = 125" >> /etc/sysctl.d/99-vm-zram-parameters.conf
echo "vm.page-cluster = 0" >> /etc/sysctl.d/99-vm-zram-parameters.conf

sysctl --system


# --------------------------------------------------------------------------------------------------------------------------
# Install GRUB for UEFI
# --------------------------------------------------------------------------------------------------------------------------

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub
sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$(blkid -s UUID -o value ${DISK}${PARTITION_2}):cryptroot root=/dev/mapper/sys-root rootfstype=btrfs rootflags=subvol=@\"|" /etc/default/grub
sed -i 's/^#GRUB_ENABLE_CRYPTODISK=.*/GRUB_ENABLE_CRYPTODISK=y/' /etc/default/grub
echo -e "GRUB_DISABLE_SUBMENU=y\nGRUB_SAVEDEFAULT=true" | tee -a /etc/default/grub
sed -i '/^#GRUB_GFXMODE/c\GRUB_GFXMODE=1920x1080' /etc/default/grub
sed -i '/^#GRUB_GFXPAYLOAD_LINUX/c\GRUB_GFXPAYLOAD_LINUX=keep' /etc/default/grub

grub-mkconfig -o /boot/grub/grub.cfg


# --------------------------------------------------------------------------------------------------------------------------
# Btrfs snapshots on GRUB 
# --------------------------------------------------------------------------------------------------------------------------

sed -i 's|ExecStart=/usr/bin/grub-btrfsd --syslog /.snapshots|ExecStart=/usr/bin/grub-btrfsd --syslog --timeshift-auto|' /usr/lib/systemd/system/grub-btrfsd.service


# --------------------------------------------------------------------------------------------------------------------------
# Install utilities and applications
# --------------------------------------------------------------------------------------------------------------------------

pacman -S --noconfirm net-tools timeshift openssh flatpak unzip


# --------------------------------------------------------------------------------------------------------------------------
# Install audio components
# --------------------------------------------------------------------------------------------------------------------------

pacman -S --noconfirm pipewire wireplumber pipewire-pulse alsa-plugins alsa-firmware sof-firmware alsa-card-profiles pavucontrol-qt


# --------------------------------------------------------------------------------------------------------------------------
# Install NVIDIA drivers
# --------------------------------------------------------------------------------------------------------------------------

pacman -S --noconfirm nvidia-open-dkms nvidia-settings nvidia-utils opencl-nvidia libxnvctrl


# --------------------------------------------------------------------------------------------------------------------------
# Install Hyprland and SDDM
# --------------------------------------------------------------------------------------------------------------------------

pacman -Syu --noconfirm sddm 
pacman -Syu --noconfirm qt6-svg qt6-declarative qt5-quickcontrols2
curl -L -o catppuccin-mocha.zip https://github.com/catppuccin/sddm/releases/download/v1.0.0/catppuccin-mocha.zip
rm rf /usr/share/sddm/themes/*
unzip catppuccin-mocha.zip -d /usr/share/sddm/themes/ && rm -rf catppuccin-mocha.zip &&m
sed -i 's/^Current=.*$/Current=catppuccin-mocha/' /usr/lib/sddm/sddm.conf.d/default.conf


pacman -S --noconfirm hyprland wayland xorg-xwayland


su -c "(echo N; echo n; echo i) | bash <(curl -s 'https://end-4.github.io/dots-hyprland-wiki/setup.sh')" $USER
for file in /home/$USER/.config/hypr/*.new; do mv "$file" "${file%.new}"; done

echo -e "[Desktop Entry]\nName=Hyprland\nComment=Hyprland Wayland Session\nExec=hyprland\nType=Application\nDesktopNames=Hyprland" | tee /usr/share/wayland-sessions/hyprland.desktop
sed -i '/^\[X11\]/,/\[.*\]/s/^SessionDir=.*$/SessionDir=/' /usr/lib/sddm/sddm.conf.d/default.conf
find /usr/share/wayland-sessions -type f ! -name 'hyprland.desktop' -exec rm -f {} +


# --------------------------------------------------------------------------------------------------------------------------
# Configure SSH
# --------------------------------------------------------------------------------------------------------------------------

PORT=2222
sed -i "/^\s*#\?Port\s.*$/c\Port $PORT" /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config


# --------------------------------------------------------------------------------------------------------------------------
# Enable services
# --------------------------------------------------------------------------------------------------------------------------

systemctl enable NetworkManager
systemctl enable sddm
systemctl enable cronie 
systemctl enable grub-btrfsd
systemctl enable sshd


EOF


# --------------------------------------------------------------------------------------------------------------------------
# Exit chroot
# --------------------------------------------------------------------------------------------------------------------------

exit
