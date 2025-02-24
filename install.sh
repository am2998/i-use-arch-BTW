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


# --------------------------------------------------------------------------------------------------------------------------
# Prompt for user and system settings
# --------------------------------------------------------------------------------------------------------------------------

echo -ne "Enter the username: "; read -r USERNAME
echo -n "Enter the password for user $USERNAME: "; read -r -s USERPASS; echo
echo -n "Enter the password for root user: "; read -r -s ROOTPASS; echo
echo -n "Enter LUKS volume passphrase: "; read -r -s PASSPHRASE; echo
echo -n "Enter the hostname: "; read -r HOSTNAME

DISK="nvme0n1"
PARTITION_1="p1"
PARTITION_2="p2"


echo -e "\n\n# --------------------------------------------------------------------------------------------------------------------------"
echo -e "# Check if there are existing PV and VG"
echo -e "# --------------------------------------------------------------------------------------------------------------------------\n"

umount -R /mnt
VG_NAME=$(vgdisplay -c | cut -d: -f1 | xargs)

if [ -z "$VG_NAME" ]; then
    echo -e "\nNo volume group found. Skipping VG removal."
else
    echo -e "\nRemoving volume group ${VG_NAME} and all associated logical volumes..."
    yes | vgremove "$VG_NAME"
fi


echo -e "\n\n# --------------------------------------------------------------------------------------------------------------------------"
echo -e "# Removing the associated physical volumes"
echo -e "# --------------------------------------------------------------------------------------------------------------------------\n"

PV_NAME=$(pvs --noheadings -o pv_name | grep -w "$VG_NAME" | xargs)

if [ -z "$PV_NAME" ]; then
    echo -e "\nNo physical volume found for ${VG_NAME}. Skipping PV removal."
else
    echo -e "\nRemoving physical volume ${PV_NAME}..."
    yes | pvremove "$PV_NAME"
fi


echo -e "\n\n# --------------------------------------------------------------------------------------------------------------------------"
echo -e "# Cleaning old partition table and partitioning"
echo -e "# --------------------------------------------------------------------------------------------------------------------------\n"

wipefs -a $DISK

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

echo "$PASSPHRASE" | cryptsetup luksFormat ${DISK}${PARTITION_2}
echo "$PASSPHRASE" | cryptsetup open ${DISK}${PARTITION_2} cryptroot

pvcreate /dev/mapper/cryptroot
vgcreate sys /dev/mapper/cryptroot
yes | lvcreate -l 100%FREE -n root sys

modprobe dm-mod
vgchange -ay


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

pacstrap /mnt base base-devel linux linux-headers linux-firmware lvm2 zram-generator btrfs-progs reflector man sudo vim nano networkmanager iw wpa_supplicant grub efibootmgr os-prober 


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
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=it" > /etc/vconsole.conf
ln -sf /usr/share/zoneinfo/Europe/Rome /etc/localtime
hwclock --systohc
timedatectl set-ntp true
sed -i '/^#it_IT.UTF-8/s/^#//g' /etc/locale.gen && locale-gen
echo -e "127.0.0.1   localhost\n::1         localhost\n127.0.1.1   $HOSTNAME.localdomain   $HOSTNAME" > /etc/hosts


# --------------------------------------------------------------------------------------------------------------------------
# Configure mirrors
# --------------------------------------------------------------------------------------------------------------------------

reflector --country "Italy" --latest 10 --sort rate --protocol https --age 7 --save /etc/pacman.d/mirrorlist


# --------------------------------------------------------------------------------------------------------------------------
# Create user and set passwords
# --------------------------------------------------------------------------------------------------------------------------

useradd -m -G wheel $USERNAME
echo "$USERNAME:$USERPASS" | chpasswd
echo "root:$ROOTPASS" | chpasswd


# --------------------------------------------------------------------------------------------------------------------------
# Configure sudoers file
# --------------------------------------------------------------------------------------------------------------------------

echo -e "\n\n%$USERNAME ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee -a /etc/sudoers


# --------------------------------------------------------------------------------------------------------------------------
# Configure LVM
# --------------------------------------------------------------------------------------------------------------------------

sed -i '/^HOOKS=/s/ filesystems/ encrypt lvm2 filesystems/' /etc/mkinitcpio.conf && mkinitcpio -P


# --------------------------------------------------------------------------------------------------------------------------
# Install GRUB for UEFI
# --------------------------------------------------------------------------------------------------------------------------

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=3/' /etc/default/grub
sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
sudo sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$(blkid -s UUID -o value ${DISK}${PARTITION_2}):cryptroot root=/dev/mapper/sys-root rootfstype=btrfs rootflags=subvol=@\"|" /etc/default/grub
sudo sed -i 's/^#GRUB_ENABLE_CRYPTODISK=.*/GRUB_ENABLE_CRYPTODISK=y/' /etc/default/grub
echo -e "GRUB_DISABLE_SUBMENU=y\nGRUB_SAVEDEFAULT=true" | sudo tee -a /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg


# --------------------------------------------------------------------------------------------------------------------------
# Configure zram
# --------------------------------------------------------------------------------------------------------------------------

bash -c 'cat > /etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-size = min(ram, 8192)
compression-algorithm = zstd
EOF'


# --------------------------------------------------------------------------------------------------------------------------
# Install basic utilities and applications
# --------------------------------------------------------------------------------------------------------------------------

pacman -S --noconfirm firefox konsole okular dolphin kate net-tools timeshift fish git fastfetch bitwarden pika-backup htop rsync tree python openssh grub-btrfs inotify-tools


# --------------------------------------------------------------------------------------------------------------------------
# Install audio components
# --------------------------------------------------------------------------------------------------------------------------

pacman -S --noconfirm pulseaudio pavucontrol-qt


# --------------------------------------------------------------------------------------------------------------------------
# Install display manager and desktop environment
# --------------------------------------------------------------------------------------------------------------------------

pacman -S --noconfirm sddm-kcm plasma sddm


# --------------------------------------------------------------------------------------------------------------------------
# Install NVIDIA drivers and 32-bit compatibility libraries
# --------------------------------------------------------------------------------------------------------------------------

pacman -S --noconfirm nvidia-open nvidia-utils nvidia-settings amd-ucode


# --------------------------------------------------------------------------------------------------------------------------
# Enable Multilib repository
# --------------------------------------------------------------------------------------------------------------------------

sed -i '/^\[multilib\]/,/^$/s/^#//g' /etc/pacman.conf


# --------------------------------------------------------------------------------------------------------------------------
# Enable Chaotic AUR
# --------------------------------------------------------------------------------------------------------------------------

pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
pacman-key --lsign-key 3056513887B78AEB
pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
echo -e "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" | tee -a /etc/pacman.conf
pacman -Syu --noconfirm


# --------------------------------------------------------------------------------------------------------------------------
# Btrfs snapshots on GRUB 
# --------------------------------------------------------------------------------------------------------------------------

sed -i 's|ExecStart=/usr/bin/grub-btrfsd --syslog /.snapshots|ExecStart=/usr/bin/grub-btrfsd --syslog --timeshift-auto|' /usr/lib/systemd/system/grub-btrfsd.service


# --------------------------------------------------------------------------------------------------------------------------
# Enable services
# --------------------------------------------------------------------------------------------------------------------------

systemctl enable NetworkManager
systemctl enable sddm
systemctl enable cronie 
systemctl enable grub-btrfsd
systemctl enable sshd


# --------------------------------------------------------------------------------------------------------------------------
# Modify SDDM settings for the theme
# --------------------------------------------------------------------------------------------------------------------------

sed -i 's/^Current=.*$/Current=breeze/' /usr/lib/sddm/sddm.conf.d/default.conf


# --------------------------------------------------------------------------------------------------------------------------
# Enable login with fish shell
# --------------------------------------------------------------------------------------------------------------------------

chsh -s /usr/bin/fish $USERNAME
chsh -s /usr/bin/fish


# --------------------------------------------------------------------------------------------------------------------------
# Use Fastfetch custom theme system-wide
# --------------------------------------------------------------------------------------------------------------------------

su -c "fastfetch >/dev/null" $USERNAME
mkdir -p /home/$USERNAME/.config/fish/functions
echo -e "function fish_greeting\n    fastfetch\nend" > /home/$USERNAME/.config/fish/functions/fish_greeting.fish


# --------------------------------------------------------------------------------------------------------------------------
# Install Yay
# --------------------------------------------------------------------------------------------------------------------------

su -c "cd /home/$USERNAME/ && git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si --noconfirm" $USERNAME




🟢 Arch has been installed successfully!
🚀 Reboot the system and login with the user $USERNAME


EOF


# --------------------------------------------------------------------------------------------------------------------------
# Exit chroot
# --------------------------------------------------------------------------------------------------------------------------

exit