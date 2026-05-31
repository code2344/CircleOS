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

In reflection, I am very happy with the progress I made on this OS. It has been a long journey, with many failures, learning moments, and successes, but overall, I am very proud of this work. I will continue to develop this into the future, and to those reading this, please email me for any questions whatsoever at [ ruben@scstudios.tech ]



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

## Journal
### Mar 18, 2026 - 10:11 AM
I got a bootloader working with a few commands! There were many challenges as I had to learn about assembly but it was quite fun!

### Mar 20, 2026 - 8:37 PM
I now have functional file storage and a shell executable, as well as text editing. Download the floppy image at https://cdn.hackclub.com/019d0a9a-f1b1-78ae-8c85-df9fc1714246/circleos.img 
This can be run using [copy.sh](copy.sh/v86), just upload the img as a floppy disk image.

### Mar 23, 2026 - 12:46 PM
I now have a functional work-in-progress file system, and displaying images! Currently fixing my very broken filesystem. Soon I plan to start working on my GUI.

### Mar 24, 2026 - 10:40 AM
I have fixed the filesystem, and also cat and write. I decided to implement an inode-based file system, like most modern OSes (Linux, Windows and MacOS), and it works quite nicely.

### May 27, 2026 - 6:42 PM
I worked more on the readme and commented more files. I also did quite a bit of research into displays, rendering, drivers, and graphics. I'm researching what to improve next. I also had to remember how my ls program worked (which i wrote a month ago) so that was a challenge.

### May 29, 2026 - 2:15 PM
I have begun working on my networking stack. I'm going to do it using ne2k as it is one of the default options in the emulator that I'm using. I had to do quite a bit of research though, and right now all I have is initialising the NIC card. I found it challenging to figure out what to send, but theoretically it should initialise. Next, I'm going to make it send an ARP frame. (also wouldnt it be cool if i pressed ship using my os)

## May 29, 2026 - 5:08 PM
I added a program that gets the date/time from the BIOS and then prints this on the screen. (please note the date in the vm is wrong, thats what it recieves from the bios) This is a program that might be useful on most programs as now they can check the system time! I also did testing and research about networking as it would be really cool to get that implemented!

## May 29, 2026 - 9:31 PM
I did some finishing touches, as well as a lot of testing. As far as I can see, there's just a couple of minor bugs that could be fixed but other than that, it's all done! I am incredibly proud of what I've achieved with this whole project, and will absolutely continue working on this in the future! I'd also like to personally say thank you to every single person behind boot, as you are the reason I learned assembly, and managed to actually finish a project for once!
