; fs_table.asm - CircleOS Program Table (CFS1 format)
; Purpose: Hardcoded directory of loadable executables and static text files
; Location: Sector 20 on the boot disk (1 sector = 512 bytes total)
; Usage: Kernel loads this at 0x0600, shell/programs reference programs by name
;
; FILE FORMAT - CFS1 (Circle File System v1) Program Table:
;   HEADER (16 bytes):
;   +0..+3   Magic signature: 'C', 'F', 'S', '1' (identifies table format)
;   +4       entry_count (number of programs/files defined, 0-10 typically)
;   +5..+15  reserved (padding to 16-byte boundary)
;
;   ENTRIES (10 max, 16 bytes each):
;   Each program/file is described by a 16-byte entry at offset 16 + (index * 16)
;
; ENTRY STRUCTURE (16 bytes per entry):
;   Offset  Size  Field Name         Description
;   ------  ----  ----------         -----------
;   +0      8     name[8]            Null-padded program name (max 8 chars)
;   +8      1     start_sector       Where program is stored on disk (1-based sector #)
;   +9      1     sector_count       How many sectors occupy program data (1-256 sectors)
;   +10     2     load_offset        Physical memory address msword (load_addr = offset*256)
;   +12     2     entry_offset       Entry point offset within program (not always used)
;   +14     1     entry_type         Type of entry: 1=program, 2=text file, 3=ARC script
;   +15     1     reserved           Padding
;
; TOTAL: 16 (header) + 160 (10 max entries) = 176 bytes, rest = padding to 512 bytes
;
; TYPE CODES:
;   1 = Executable program (loaded at load_offset, executed)
;   2 = Text file (cat.asm reads these)
;   3 = ARC script (csh.asm executes line-by-line)
;   0 = Empty/unused entry slot
;
; BUILD-TIME CONFIGURATION:
;   Each program's sector location is calculated at build time by build.sh
;   Build script reads assembly files and assigns sector numbers
;   %ifndef directives allow overriding defaults if needed
;
; SECTOR LAYOUT ON DISK:
;   Sector 0-1:   Boot loader (512 bytes)
;   Sector 2-19:  Kernel code (18+ sectors)
;   Sector 20:    this file (fs_table.asm, program table header)
;   Sector 21+:   Individual programs/text files
;   Sector 200+:  InodeFS filesystem (writable, replaces static files)
;
; PROGRAM LOADING FLOW:
; 1. Kernel loads fs_table at 0x0600
; 2. User/shell searches table by name (str_eq)
; 3. Kernel calls disk_read_chs to load program's sectors into memory
; 4. Program execution happens at load_offset
; 5. User can write new files to InodeFS (sectors 200+), which takes precedence

[BITS 16]           ; 16-bit assembly (real mode)
[ORG 0]             ; This file produces no code, only data (offset 0 is arbitrary)

%ifndef LS_SECTOR
LS_SECTOR equ 19
%endif

%ifndef LS_SECTORS
LS_SECTORS equ 1
%endif

%ifndef INFO_SECTOR
INFO_SECTOR equ 20
%endif

%ifndef INFO_SECTORS
INFO_SECTORS equ 1
%endif

%ifndef STAT_SECTOR
STAT_SECTOR equ 21
%endif

%ifndef STAT_SECTORS
STAT_SECTORS equ 1
%endif

%ifndef GREET_SECTOR
GREET_SECTOR equ 22
%endif

%ifndef GREET_SECTORS
GREET_SECTORS equ 1
%endif

%ifndef CAT_SECTOR
CAT_SECTOR equ 23
%endif

%ifndef CAT_SECTORS
CAT_SECTORS equ 1
%endif

%ifndef TODO_SECTOR
TODO_SECTOR equ 25
%endif

%ifndef TODO_SECTORS
TODO_SECTORS equ 1
%endif

%ifndef DIR_SECTOR
DIR_SECTOR equ 19
%endif

%ifndef DIR_SECTORS
DIR_SECTORS equ 1
%endif

%ifndef WRITE_SECTOR
WRITE_SECTOR equ 26
%endif

%ifndef WRITE_SECTORS
WRITE_SECTORS equ 1
%endif

%ifndef IMG_SECTOR
IMG_SECTOR equ 27
%endif

%ifndef IMG_SECTORS
IMG_SECTORS equ 1
%endif

%ifndef SPHERE_SECTOR
SPHERE_SECTOR equ 28
%endif

%ifndef SPHERE_SECTORS
SPHERE_SECTORS equ 1
%endif

magic:
    db 'C', 'F', 'S', '1'           ; CFS1 signature identifies program table format
    db 11                            ; entry_count: 11 programs defined in this table
    times 11 db 0                    ; reserved padding (11 bytes to reach 16-byte header total)

; ================== PROGRAM ENTRIES ==================
; Each entry describes one loadable program or text file
; Kernel searches this table in response to "run <name>" commands
; Entries are exactly 16 bytes: name(8) | sector(1) | count(1) | offset(2) | entry(2) | type(1) | reserved(1)

; Entry 0: "ls" program - list files in InodeFS
entry_ls:
    db 'l', 's', 0, 0, 0, 0, 0, 0  ; name: "ls" (null-padded to 8 bytes)
    db LS_SECTOR                     ; starting sector on disk
    db LS_SECTORS                    ; number of sectors
    dw 0xA000                        ; load address for program (0xA000:0000)
    dw 0x0000                        ; entry point offset (0x0000)
    db 1                             ; type: 1 = executable program
    db 0                             ; reserved padding

; Entry 1: "info" program - display boot information
entry_info:
    db 'i', 'n', 'f', 'o', 0, 0, 0, 0  ; name: "info"
    db INFO_SECTOR
    db INFO_SECTORS
    dw 0xA000                        ; load address
    dw 0x0000                        ; entry point offset
    db 1                             ; type: program
    db 0

; Entry 2: "stat" program - show program table statistics
entry_stat:
    db 's', 't', 'a', 't', 0, 0, 0, 0  ; name: "stat"
    db STAT_SECTOR
    db STAT_SECTORS
    dw 0xA000
    dw 0x0000
    db 1                             ; type: program
    db 0

; Entry 3: "greet" program - show welcome message
entry_greet:
    db 'g', 'r', 'e', 'e', 't', 0, 0, 0  ; name: "greet"
    db GREET_SECTOR
    db GREET_SECTORS
    dw 0xA000
    dw 0x0000
    db 1                             ; type: program
    db 0

; Entry 4: "cat" program - display file contents
entry_cat:
    db 'c', 'a', 't', 0, 0, 0, 0, 0  ; name: "cat"
    db CAT_SECTOR
    db CAT_SECTORS
    dw 0xA000
    dw 0x0000
    db 1                             ; type: program
    db 0

; Entry 5: "todo" text file - static todo list
entry_todo:
    db 't', 'o', 'd', 'o', 0, 0, 0, 0  ; name: "todo" (text file, not executable)
    db TODO_SECTOR
    db TODO_SECTORS
    dw 0x0000                        ; not used for text files
    dw 0x0000                        ; not used
    db 2                             ; type: 2 = text file (cat.asm reads these)
    db 0

; Entry 6: "dir" program - directory listing (alias ls)
entry_dir:
    db 'd', 'i', 'r', 0, 0, 0, 0, 0  ; name: "dir"
    db DIR_SECTOR                    ; points to same program as ls
    db DIR_SECTORS
    dw 0xA000
    dw 0x0000
    db 1                             ; type: program
    db 0

; Entry 7: "write" program - append to files
entry_write:
    db 'w', 'r', 'i', 't', 'e', 0, 0, 0  ; name: "write"
    db WRITE_SECTOR
    db WRITE_SECTORS
    dw 0xA000
    dw 0x0000
    db 1                             ; type: program
    db 0

; Entry 8: "lsv" program - verbose ls (alias ls)
entry_lsv:
    db 'l', 's', 'v', 0, 0, 0, 0, 0  ; name: "lsv" (verbose listing)
    db DIR_SECTOR                    ; points to ls program
    db DIR_SECTORS
    dw 0xA000
    dw 0x0000
    db 1                             ; type: program
    db 0

; Entry 9: "img" program - VGA graphics image viewer
entry_img:
    db 'i', 'm', 'g', 0, 0, 0, 0, 0  ; name: "img"
    db IMG_SECTOR                    ; sector where img.asm is stored
    db IMG_SECTORS
    dw 0xA000                        ; load at 0xA000 (user program space)
    dw 0x0000
    db 1                             ; type: program
    db 0

; Entry 10: "sphere" program - Sphere GUI launcher scaffold
entry_sphere:
    db 's', 'p', 'h', 'e', 'r', 'e', 0, 0  ; name: "sphere"
    db SPHERE_SECTOR
    db SPHERE_SECTORS
    dw 0xA000
    dw 0x0000
    db 1                             ; type: program
    db 0

; Remaining padding to fill 512 bytes
; Total used: 16 (header) + 160 (10*16 bytes entries) = 176 bytes
; Padding: 512 - 176 = 336 bytes of zeros
times (512 - ($ - $$)) db 0
