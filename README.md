<p align="center">
  <img src="archlinux-logo.png" alt="Arch Logo"/>
</p>

<br>

# Arch installation script

> **Warning** ⚠️
> This script **automatically delete existing partitions on disk**. Anyone who wants to use it should adjust according to their use case. This script was initially created for personal use, and i do not take responsibility for any damage or other issues that may arise from its use.


This script automates the installation of Arch Linux with a custom configuration. It includes setting up LUKS encryption, LVM, Btrfs, and various system configurations.

## Features

- LUKS encryption for the system partition
- LVM setup
- Btrfs with subvolumes
- CachyOS kernel
- Configuration of ZRAM
- KDE with SDDM
- Installation of GRUB for UEFI
- Installation of NVIDIA drivers
- Installation of essential packages and utilities
- Configuration of mirrors, users, and system settings
- Enabling services like NetworkManager, SDDM, and more

## Usage

1. **Clone the repository:**

    ```bash
    git clone https://github.com/yourusername/i-use-arch-BTW.git
    cd i-use-arch-BTW
    ```

2. **Make the script executable:**

    ```bash
    chmod +x install.sh
    ```

3. **Run the script:** 🚀

    ```bash
     ./install.sh
    ```
4. **Reboot and enjoy!** 
<br><br>

> **Note**
> The script generates an install log file named `result.log` in the current directory.

> **Note** ⚠️
> Timeshift and Pika Backup need to be configured after install in order to snapshot and backup your sistem. 

## Script Details

### Prompt for User and System Settings

The script will prompt you to enter the following details:

- Username
- Password for the user
- Password for the root user
- LUKS volume passphrase
- Hostname

### Partitioning and Formatting

The script will:

- Unmount any mounted partitions
- Check for existing volume groups and physical volumes and remove them if found
- Clean the old partition table and create new partitions
- Set up LUKS encryption and LVM
- Format and mount the partitions

### Base System Installation

The script will install the base system and essential packages using `pacstrap`.

### System Configuration

The script will:

- Generate the `fstab` file
- Chroot into the new system and configure basic settings
- Configure mirrors using `reflector`
- Enable Multilib repo
- Install CachyOS kernel
- Configure ZRAM
- Create a user and set passwords
- Configure the `sudoers` file
- Install and configure GRUB for UEFI


### Additional Packages and Services

The script will install additional packages and enable necessary services:

- Install basic utilities and applications
- Install audio components
- Install SDDM and KDE
- Install NVIDIA drivers
- Configure SSH
- Modify SDDM settings for the theme
- Use Fastfetch custom theme system-wide

### Enabling Services

The script will enable the following services:

- NetworkManager
- SDDM
- Cronie
- Grub-btrfsd
- SSHD

### Exit Chroot

The script will exit the chroot environment and complete the installation.

## Notes

- Ensure you have a stable internet connection during the installation.
- The script is designed for a specific disk layout and may need adjustments for different setups.

## License

This project is licensed under the MIT License. See the [LICENSE](http://_vscodecontentref_/2) file for details.



