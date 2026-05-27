# CircleOS
CircleOS is an operating system written entirely in x86 Assembly. It uses BIOS-backed syscalls, and has a functional filesystem, as well as editing of a text file. This has been made by Ruben Sutton (@ruben) for Hack Club Boot. 

## Installation Guide
I have no idea why you'd want to install this on your computer, considering it's an unfinished and not super useful OS, but if you do:
1. Download the latest version from releases. You can see this in the bar on the side of the screen. 
2. Flash it onto a USB using something like BalenaEtcher or Rufus. 
3. Plug it into your computer
4. Enter your computers bios by holding [DEL]
5. Set boot mode from UEFI to BIOS.
6. Make sure Secure Boot is DISABLED (note: if you're on windows, disabling this will trigger BitLocker, so either make sure that it's off or have your recovery key somewhere safe and EASILY ACCESSIBLE)
7. Change the boot order so that it boots from USB first.
8. Now exit the bios
9. profit

# General Info
CircleOS uses a small initial bootloader to initialise the system memory, then loads the kernel, which runs and handles all syscalls. 

## Journal
### Mar 18, 2026 - 10:11 AM
I got a bootloader working with a few commands! There were many challenges as I had to learn about assembly but it was quite fun!

### Mar 20, 2026 - 8:37 PM
I now have functional file storage and a shell executable, as well as text editing. Download the floppy image at https://cdn.hackclub.com/019d0a9a-f1b1-78ae-8c85-df9fc1714246/circleos.img 
This can be run using copy.sh/v86, just upload the img as a floppy disk image.

### Mar 23, 2026 - 12:46 PM
I now have a functional work-in-progress file system, and displaying images! Currently fixing my very broken filesystem. Soon I plan to start working on my GUI.

### Mar 24, 2026 - 10:40 AM
I have fixed the filesystem, and also cat and write. I decided to implement an inode-based file system, like most modern OSes (Linux, Windows and MacOS), and it 
