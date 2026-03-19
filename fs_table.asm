; fs_table.asm
; Tiny CircleOS filesystem table sector (CFS1)
;
; Layout (512 bytes total):
;   +0..+3   magic "CFS1"
;   +4       entry_count
;   +5..+15  reserved
;   +16..    entries (16 bytes each)
;
; Entry format (16 bytes):
;   +0..+7   name[8] (zero-padded)
;   +8       start_sector (1-based CHS sector on cyl0/head0)
;   +9       sector_count
;   +10..11  load_offset
;   +12..13  entry_offset
;   +14..15  reserved

[BITS 16]
[ORG 0]

%ifndef DEMO_SECTOR
DEMO_SECTOR equ 18
%endif

%ifndef DEMO_SECTORS
DEMO_SECTORS equ 1
%endif

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

magic:
    db 'C', 'F', 'S', '1'
    db 10                        ; entry_count (programs + text files)
    times 11 db 0                ; reserved header bytes to offset 16

; Entry 0: demo program
entry_demo:
    db 'd', 'e', 'm', 'o', 0, 0, 0, 0
    db DEMO_SECTOR
    db DEMO_SECTORS
    dw 0xA000                    ; load_offset
    dw 0x0000                    ; entry_offset
    db 1                         ; entry_type = program
    db 0                         ; reserved

; Entry 1: ls program (list programs)
entry_ls:
    db 'l', 's', 0, 0, 0, 0, 0, 0
    db LS_SECTOR
    db LS_SECTORS
    dw 0xA000                    ; load_offset
    dw 0x0000                    ; entry_offset
    db 1                         ; entry_type = program
    db 0                         ; reserved

; Entry 2: info program (system info)
entry_info:
    db 'i', 'n', 'f', 'o', 0, 0, 0, 0
    db INFO_SECTOR
    db INFO_SECTORS
    dw 0xA000                    ; load_offset
    dw 0x0000                    ; entry_offset
    db 1                         ; entry_type = program
    db 0                         ; reserved

; Entry 3: stat program (program statistics)
entry_stat:
    db 's', 't', 'a', 't', 0, 0, 0, 0
    db STAT_SECTOR
    db STAT_SECTORS
    dw 0xA000                    ; load_offset
    dw 0x0000                    ; entry_offset
    db 1                         ; entry_type = program
    db 0                         ; reserved

; Entry 4: greet program (greeting)
entry_greet:
    db 'g', 'r', 'e', 'e', 't', 0, 0, 0
    db GREET_SECTOR
    db GREET_SECTORS
    dw 0xA000                    ; load_offset
    dw 0x0000                    ; entry_offset
    db 1                         ; entry_type = program
    db 0                         ; reserved

; Entry 5: cat program
entry_cat:
    db 'c', 'a', 't', 0, 0, 0, 0, 0
    db CAT_SECTOR
    db CAT_SECTORS
    dw 0xA000                    ; load_offset
    dw 0x0000                    ; entry_offset
    db 1                         ; entry_type = program
    db 0                         ; reserved

; Entry 6: readme text file
; Entry 6: todo text file
entry_todo:
    db 't', 'o', 'd', 'o', 0, 0, 0, 0
    db TODO_SECTOR
    db TODO_SECTORS
    dw 0x0000                    ; not used for text files
    dw 0x0000                    ; not used for text files
    db 2                         ; entry_type = text
    db 0                         ; reserved

; Entry 7: dir alias to ls -v metadata output
entry_dir:
    db 'd', 'i', 'r', 0, 0, 0, 0, 0
    db DIR_SECTOR
    db DIR_SECTORS
    dw 0xA000                    ; load_offset
    dw 0x0000                    ; entry_offset
    db 1                         ; entry_type = program
    db 0                         ; reserved

; Entry 8: write program
entry_write:
    db 'w', 'r', 'i', 't', 'e', 0, 0, 0
    db WRITE_SECTOR
    db WRITE_SECTORS
    dw 0xA000                    ; load_offset
    dw 0x0000                    ; entry_offset
    db 1                         ; entry_type = program
    db 0                         ; reserved

; Entry 9: lsv alias to ls -v metadata output
entry_lsv:
    db 'l', 's', 'v', 0, 0, 0, 0, 0
    db DIR_SECTOR
    db DIR_SECTORS
    dw 0xA000                    ; load_offset
    dw 0x0000                    ; entry_offset
    db 1                         ; entry_type = program
    db 0                         ; reserved

; Remaining entries and padding cleared
times (512 - ($ - $$)) db 0
