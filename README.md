<p align="center">
  <img src="archlinux-logo.png" alt="Arch Logo"/>
</p>

<br>

# Arch installation script

> **Warning** ⚠️
> This script **automatically delete existing partitions on disk**. Anyone who wants to use it should adjust according to their use case. This script was initially created for personal use, and i do not take responsibility for any damage or other issues that may arise from its use.

## Steps

1. **User and System Settings Prompt**
   - Prompts for username, user password, root password, LUKS password and hostname.

2. **Check for Existing PV and VG**
   - Checks for existing physical volumes (PV) and volume groups (VG) and removes them if found.

3. **Clean Old Partition Table and Partitioning**
   - Cleans the old partition table and partitions the disk with a GPT partition table, creating EFI and system partitions.

4. **Create LUKS and LVM for System Partition**
   - Sets up LVM on the system partition, including encryption with LUKS.

5. **Format and Mount Partitions**
   - Formats the EFI and system partitions and mounts the latter them with Btrfs subvolumes.

6. **Install Base System**
   - Installs the base Arch Linux system and essential packages.

7. **Generate fstab File**
   - Generates the fstab file for mounting partitions.

8. **Chroot into the System and Configure**
   - Chroots into the new system and performs various configurations, including setting up locale, hostname, and time zone.

9. **Configure Mirrors**
   - Configures the package mirrors using Reflector.

10. **Create User and Set Passwords**
    - Creates a new user and sets passwords for the user and root.

11. **Configure Sudo**
    - Configures sudo to allow the new user to execute commands without a password.

12. **Configure LUKS and LVM in mkinitcpio**
    - Configures LVM and ecrypt hooks in mkinitcpio.

13. **Install GRUB for UEFI**
    - Installs and configures the GRUB bootloader for UEFI systems.

14. **Configure ZRAM**
    - Configures ZRAM for improved memory management.

15. **Install Basic Utilities and Applications**
    - Installs a set of basic utilities and applications.

16. **Install Audio Components**
    - Installs PulseAudio and Pavucontrol.

17. **Install Display Manager and Desktop Environment**
    - Installs the SDDM display manager and KDE Plasma desktop environment.

18. **Install NVIDIA Drivers and 32-bit Compatibility Libraries**
    - Installs NVIDIA drivers and 32-bit compatibility libraries.

19. **Enable Multilib Repository**
    - Enables the Multilib repository in pacman.conf.

20. **Enable Chaotic AUR**
    - Adds and enables the Chaotic AUR repository.

21. **Btrfs Snapshots on GRUB**
    - Configures GRUB to detect Timeshift Btrfs snapshots automatically.

22. **Enable Services**
    - Enables essential services like NetworkManager, SDDM, Cronie, and grub-btrfsd.

23. **Modify SDDM Settings for the Theme**
    - Configures SDDM to use the Breeze theme.

24. **Enable Login with Fish Shell**
    - Sets Fish as the default shell for the new user and root.

25. **Use Fastfetch Custom Theme System-wide**
    - Configures Fastfetch to run at login.

26. **Install Yay**
    - Installs the Yay AUR helper.

27. **Exit Chroot and Reboot**
    - Exits the chroot environment.

## Install

1. **Clone the Repository**
   ```
   git clone https://github.com/am2998/i-use-arch-BTW.git
   ```
2. **Make the script executable**
   ```
   chmod +x install.sh
   ```

3. **Run the script** 🚀

   ```
   ./install.sh
   ```
3. **Reboot and enjoy!** 
<br><br>

> **Warning** ⚠️
> Timeshift and Pika Backup need to be configured after install in order to snapshot and backup your sistem. 
