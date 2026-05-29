# CircleOS
CircleOS is an operating system written entirely in x86 Assembly. It uses BIOS-backed syscalls, and has a functional filesystem, as well as editing of a text file. This has been made by Ruben Sutton (@ruben) for Hack Club Boot.

The original goals of the project were: 
1. Shell-as-executable: Shell as custom executable rather than hardcoded commands in the kernel.
2. Run DOOM 1993: pretty self explanatory, it’s not a true OS if it can’t run doom
3. Functional GUI: Display manager etc
4. Text editors and word processing: A Word alternative and a text editor

I was inspired to do this entirely in assembly because I have tried learning C in the past and found it too hard, and since most modern OSes are made in C, I wanted to try to prove they can be done in other ways. The interface is inspire by Linux/Unix, with a shell executable and a TUI.

Throughout the project, I learned many new skills, but the main (and obvious) thing I learned was x86 assembly.

The system boots directly from BIOS using a custom made bootloader. This bootloader initialises ram before jumping to 16 bit mode, and then launching the kernel.

I decided to stay in 16 bit mode after 32 bit gave me too many issues (I spent quite a while on it) because of the advantages of using BIOS syscalls directly without having to make drivers and hardware descriptions, but it came with advantages and disadvantages. 

The advantages are that it is much simpler to implement and manage things like RAM and program memory as well as storage. However, this limits the amount of ram that is actually accessible meaning it's hard to run big programs.

The filesystem is entirely custom (just like all the other parts of this project) and inode based. The filesystem (before being built) is stored in a hardcoded asm file. 





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
This can be run using [copy.sh](copy.sh/v86), just upload the img as a floppy disk image.

### Mar 23, 2026 - 12:46 PM
I now have a functional work-in-progress file system, and displaying images! Currently fixing my very broken filesystem. Soon I plan to start working on my GUI.

### Mar 24, 2026 - 10:40 AM
I have fixed the filesystem, and also cat and write. I decided to implement an inode-based file system, like most modern OSes (Linux, Windows and MacOS), and it 
