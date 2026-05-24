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
8. 