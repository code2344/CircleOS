; kernel.asm
; CircleOS kernel - a simple shell with basic commands.

[BITS 16]           ; assemble these instructions for 16-bit mode
[ORG 0x7E00]        ; this code lives at 0x7e00

BOOT_INFO_ADDR equ 0x0500
BOOT_SIG0_OFF equ BOOT_INFO_ADDR + 0
BOOT_SIG1_OFF equ BOOT_INFO_ADDR + 1
BOOT_VER_OFF equ BOOT_INFO_ADDR + 2
BOOT_DRIVE_OFF equ BOOT_INFO_ADDR + 3
BOOT_KSECT_OFF equ BOOT_INFO_ADDR + 4

SYSCALL_INT equ 0x80
SYS_PUTC equ 0x01
SYS_PUTS equ 0x02
SYS_NEWLINE equ 0x03
SYS_GETC equ 0x04
SYS_CLEAR equ 0x05
SYS_RUN equ 0x06
SYS_READ_RAW equ 0x07
SYS_WRITE_RAW equ 0x08
SYS_FS_READ equ 0x09
SYS_FS_WRITE equ 0x0A
SYS_FS_LIST equ 0x0B
SYS_FS_DELETE equ 0x0C
SYS_FS_MKDIR equ 0x0D
SYS_FS_CHDIR equ 0x0E

%ifndef DEBUG
%define DEBUG 0
%endif

%ifndef FS_TABLE_SECTOR
FS_TABLE_SECTOR equ 20
%endif

%ifndef SHELL_SECTORS
SHELL_SECTORS equ 2
%endif

PROG_TABLE_ADDR equ 0x0600
PROG_TABLE_MAX_ENTRIES equ 16

; -----------------------------
; InodeFS (flat root directory)
; -----------------------------
INFS_SUPER_SECTOR equ 200
INFS_INODE_SECTOR equ 201
INFS_BITMAP_SECTOR equ 202
INFS_DATA_START_SECTOR equ 203

INFS_MAX_INODES equ 32
INFS_MAX_BLOCKS equ 128
INFS_INODE_SIZE equ 16
INFS_NAME_LEN equ 8
INFS_ROOT_INODE equ 0

INFS_TYPE_FILE equ 1
INFS_TYPE_DIR equ 2
INFS_TYPE_ARC equ 3

INFS_OFF_USED equ 0
INFS_OFF_TYPE equ 1
INFS_OFF_SIZE equ 2
INFS_OFF_START equ 4
INFS_OFF_COUNT equ 5
INFS_OFF_PARENT equ 6
INFS_OFF_NAME equ 8

INFS_SUPER_BUF equ 0x1200
INFS_INODE_BUF equ 0x1400
INFS_BITMAP_BUF equ 0x1600

start:
    mov ax, 0               ; DS and ES point to absolute memory for boot info
    mov ds, ax
    mov es, ax

    ; Verify boot sector signature (bootloader must write it)
    cmp byte [BOOT_SIG0_OFF], 'C'
    jne .boot_info_bad      ; bootloader didn't initialize boot info
    cmp byte [BOOT_SIG1_OFF], 'B'
    jne .boot_info_bad

    ; Retrieve boot drive from bootloader
    mov al, [BOOT_DRIVE_OFF]
    mov [kernel_boot_drive], al

    call enable_a20         ; enable A20 gate for full memory access
    call load_boot_gdt      ; load minimal GDT (prepared for later protected mode)
    call install_syscall_vector ; set up INT 0x80 handler

    ; Display boot banner
    call console_clear
    call show_boot_logo
    call delay_5s
    call console_clear

    ; Load program table from disk (contains executable names/boot locations)
    call load_program_table
    cmp ah, 0               ; AH=0 success, else error
    jne .prog_table_bad

    ; Mount or format InodeFS (writable filesystem at sectors 200+)
    call fs_mount_or_format

    ; Launch user shell at 0x9000 (csh.asm entry point)
    call launch_shell
    jmp .shell_loop         ; kernel command loop if shell returns


.boot_info_bad:
    mov si, boot_info_bad_msg
    call console_puts
    jmp halt

.prog_table_bad:
    mov si, prog_table_bad_msg
    call console_puts
    call console_newline
    jmp halt
.shell_loop:
    mov si, prompt      ; move prompt (arcsh >)
    call console_puts   ; print prompt

    ; read command from keyboard
    xor cx, cx          ; cx=0, start at first byte
    mov bx, command_buf ; bx points to command buffer start

.read_loop:
    ; mov ah, 0x00        ; bios wait for key press and return 
    ; int 0x16            ; bios interrupt to return key press
    call kbd_getc
    
    ; check for enter key
    cmp al, 13          ; key press goes into AL for the ascii code, ascii code of carriage return is 13 or 0D
    je .command_ready   ; enter means command is finished, so jump to command execution

    cmp al, 8           ; check for backspace character
    je .backspace      

    ; print character via BIOS TTY by running int 10 and setting AH to 0E
    ; mov ah, 0x0E
    ; int 0x10
    call console_putc

    ; store typed character in command buffer at [BX+CX], bx is base and cx is index
    mov si, cx
    mov byte [bx + si], al
    inc cx

    ; limit input length to 32 bytes
    cmp cx, 32
    jl .read_loop

    ; if at or over 32 keep reading but ignore storage
    jmp .read_loop ; jump unconditionally

.backspace:
    cmp cx, 0           ; is the cursor already at the start?
    je .read_loop       ; if yes, exit backspace loop and go to read loop

    mov ah, 0x0E
    mov al, 8           ; ASCII backspace
    int 0x10
    mov al, ' '         ; print ' ' to cover/erase old character
    int 0x10
    mov al, 8           ; backspace again :)
    int 0x10

    dec cx
    jmp .read_loop ; jump unconditionally

.command_ready:
    mov si, cx
    mov byte [bx + si], 0       ;null terminate the command so routines know where it ends

    call console_newline

    ; Exact command dispatch
    cmp byte [command_buf], 0
    je .shell_loop ; jump if equal/zero

    ; help
    mov si, command_buf
    mov di, cmd_help_str
    call str_eq
    cmp al, 1
    je .cmd_help ; jump if equal/zero

    ; csh
    mov si, command_buf
    mov di, cmd_csh_str
    call str_eq
    cmp al, 1
    je .cmd_csh ; jump if equal/zero

    ; Unknown command
    mov si, unknown_msg
    call console_puts
    call console_newline
    jmp .shell_loop ; jump unconditionally

.cmd_help:
    mov si, help_msg
    call console_puts
    call console_newline
    jmp .shell_loop ; jump unconditionally
.cmd_csh:
    call launch_shell
    jmp .shell_loop ; jump unconditionally

kernel_boot_drive:
    db 0

halt:
    hlt                 ; halt the cpu
    jmp halt            ; infinite loop just in case
; ----------------------------------
; Kernel service wrappers for routines
;-----------------------------------
; input al = character
; clobbers: ah
console_putc:
    mov ah, 0x0E
    int 0x10
    ret

; Input: ds:si = null terminated string
; clobbers: AL, AH, SI
console_puts:
.loop:
    lodsb ; load byte from DS:SI into AL
    cmp al, 0
    je .done ; jump if equal/zero
    call console_putc
    jmp .loop ; jump unconditionally
.done:
    ret

; prints CRLF
; clobbers: al, ah
console_newline:
    mov al, 13
    call console_putc
    mov al, 10
    call console_putc
    ret

; clears text mode screen and moves cursor to top-left
console_clear:
    mov ah, 0x06
    mov al, 0
    mov bh, 0x07
    mov cx, 0
    mov dx, 0x184F
    int 0x10

    mov ah, 0x02
    mov bh, 0
    mov dx, 0
    int 0x10
    ret

; wait for keypress and return it
; output al = ascii, ah = scan code
; clobbers ah and al
kbd_getc:
    mov ah, 0x00
    int 0x16
    ret

; enable_a20
; Enables A20 line using port 0x92 fast A20 gate.
; This is required before moving to protected mode memory layouts.
enable_a20:
    in al, 0x92
    or al, 0x02
    out 0x92, al
    ret

; load_boot_gdt
; Loads a minimal flat GDT used for a future protected-mode switch.
load_boot_gdt:
    lgdt [gdt_descriptor]
    ret

show_boot_logo:
    mov si, logo_line_01
    call console_puts_logo
    call console_newline
    mov si, logo_line_02
    call console_puts_logo
    call console_newline
    mov si, logo_line_03
    call console_puts_logo
    call console_newline
    mov si, logo_line_04
    call console_puts_logo
    call console_newline
    mov si, logo_line_05
    call console_puts_logo
    call console_newline
    mov si, logo_line_06
    call console_puts_logo
    call console_newline
    mov si, logo_line_07
    call console_puts_logo
    call console_newline
    mov si, logo_line_08
    call console_puts_logo
    call console_newline
    mov si, logo_line_09
    call console_puts_logo
    call console_newline
    mov si, logo_line_10
    call console_puts_logo
    call console_newline
    mov si, logo_line_11
    call console_puts_logo
    call console_newline
    mov si, logo_line_12
    call console_puts_logo
    call console_newline
    mov si, logo_line_13
    call console_puts_logo
    call console_newline
    mov si, logo_line_14
    call console_puts_logo
    call console_newline
    mov si, logo_line_15
    call console_puts_logo
    call console_newline
    call console_newline
    ret

; console_puts_logo
; Input: DS:SI = null-terminated logo row with '#'(on) and ' '(off)
; Renders '#' as CP437 full block (0xDB)
console_puts_logo:
.logo_loop:
    lodsb ; load byte from DS:SI into AL
    cmp al, 0
    je .logo_done ; jump if equal/zero
    cmp al, '#'
    jne .logo_emit ; jump if not equal/non-zero
    mov al, 0xDB
.logo_emit:
    call console_putc
    jmp .logo_loop ; jump unconditionally
.logo_done:
    ret

; delay_5s
; BIOS wait: CX:DX microseconds = 5,000,000 (0x004C4B40)
delay_5s:
    mov ah, 0x86
    mov cx, 0x004C
    mov dx, 0x4B40
    int 0x15
    ret

install_syscall_vector:
    cli                     ; disable interrupts during vector setup
    mov word [SYSCALL_INT * 4], syscall_handler ; IVT entry for INT 0x80
    mov word [SYSCALL_INT * 4 + 2], 0 ; code segment (CS) = 0
    sti                     ; re-enable interrupts
    ret

; ================== SYSCALL DISPATCHER ==================
; Kernel's main entry point for all user syscalls (INT 0x80)
; Every program request (I/O, filesystem, execution) routes through here
;
; Syscall Interface:
; - User code: mov ah, SYS_XXX / mov [other regs] = args / int 0x80
; - Kernel receives INT 0x80, dispatches based on AH value
; - Syscall returns with AH = status, other regs = results
; - All registers preserved except: AH (status), CX (byte count for some calls)
;
; Status codes are syscall-specific:
; - 0x00: Success
; - 0x01: Not found / File error
; - 0x02: I/O error / Already exists
; - 0xFF: Unknown syscall
syscall_handler:
    push bx                 ; preserve working registers (kernel-side save)
    push cx                 ; save CX for file size returns
    push dx                 ; save DX for multi-word results
    push si                 ; save SI (used for addressing)
    push di                 ; save DI (used for addressing)
    push bp                 ; save BP (frame pointer)
    push ds                 ; save DS (segment register)
    push es                 ; save ES (segment register)

    ; ================== DISPATCH TABLE (14 SYSCALLS) ==================
    ; Each syscall code maps to a handler function
    
    cmp ah, SYS_PUTC        ; 0x01: output single character
    je .sys_putc

    cmp ah, SYS_PUTS        ; 0x02: output null-terminated string
    je .sys_puts

    cmp ah, SYS_NEWLINE     ; 0x03: output CR+LF
    je .sys_newline

    cmp ah, SYS_GETC        ; 0x04: read single keystroke
    je .sys_getc

    cmp ah, SYS_CLEAR       ; 0x05: clear screen
    je .sys_clear

    cmp ah, SYS_RUN         ; 0x06: load and execute program
    je .sys_run

    cmp ah, SYS_READ_RAW    ; 0x07: read sectors from disk directly
    je .sys_read_raw

    cmp ah, SYS_WRITE_RAW   ; 0x08: write sectors to disk directly
    je .sys_write_raw

    cmp ah, SYS_FS_READ     ; 0x09: read file from InodeFS
    je .sys_fs_read

    cmp ah, SYS_FS_WRITE    ; 0x0A: write/append file to InodeFS
    je .sys_fs_write

    cmp ah, SYS_FS_LIST     ; 0x0B: list files in directory
    je .sys_fs_list

    cmp ah, SYS_FS_DELETE   ; 0x0C: delete file/directory from InodeFS
    je .sys_fs_delete

    cmp ah, SYS_FS_MKDIR    ; 0x0D: create directory in InodeFS
    je .sys_fs_mkdir

    cmp ah, SYS_FS_CHDIR    ; 0x0E: change current working directory
    je .sys_fs_chdir

    ; Unknown or unsupported syscall code
    mov ah, 0xFF            ; return error: unknown syscall
    jmp .done

; ================== SYSCALL HANDLERS ==================
; Each handler implements one service
; On exit to .done: restore registers and iret to caller

.sys_putc:
    call console_putc       ; print character in AL to video memory
    xor ah, ah              ; AH = 0: success
    jmp .done

.sys_puts:
    call console_puts       ; print string at DS:SI to video memory
    xor ah, ah              ; AH = 0: success
    jmp .done

.sys_newline:
    call console_newline    ; print CR+LF (0x0D, 0x0A)
    xor ah, ah              ; AH = 0: success
    jmp .done

.sys_getc:
    call kbd_getc           ; wait for keystroke, return ASCII in AL
    jmp .done                ; AH set by kbd_getc (usually 0)

.sys_clear:
    call console_clear      ; clear video memory, reset cursor
    xor ah, ah              ; AH = 0: success
    jmp .done

.sys_run:
    call run_named_program  ; search program table, load, execute (DS:SI = name)
    jmp .done                ; AH = status from run_named_program (0=success, 1=not found, 2=load error, 3=unavailable)

.sys_read_raw:
    call disk_read_chs      ; read sectors via BIOS INT 0x13 (AL=count, CL=sector, ES:BX=buffer)
    jc .sys_read_raw_fail   ; CF=1 on error
    xor ah, ah              ; CF=0: success, AH=0
    jmp .done

.sys_read_raw_fail:
    mov ah, 2               ; return error code 2 (I/O error)
    jmp .done

.sys_write_raw:
    call disk_write_chs     ; write sectors via BIOS INT 0x13
    jc .sys_write_raw_fail  ; CF=1 on error
    xor ah, ah              ; CF=0: success, AH=0
    jmp .done

.sys_write_raw_fail:
    mov ah, 2               ; return error code 2 (I/O error)
    jmp .done

.sys_fs_read:
    ; Read entire file from InodeFS by pathname
    ; Input: DS:SI = file path, ES:BX = output buffer
    ; Output: AH = status (0=success, 1=not found, 2=error), CX = bytes read
    call fs_read_file_by_name
    jmp .done

.sys_fs_write:
    ; Write/append to file in InodeFS
    ; Input: DS:SI = file path, ES:BX = data buffer, CX = bytes to write
    ; Output: AH = status (0=success, 1=error, 2=full)
    call fs_write_file_by_name
    jmp .done

.sys_fs_list:
    ; List files in current directory
    ; Input: CX = which entry to return (0, 1, 2, ...)
    ; Output: AH = status, CX = byte count, ES:BX = entry info
    call fs_list_file_by_ordinal
    jmp .done

.sys_fs_delete:
    ; Delete file or directory from InodeFS
    ; Input: DS:SI = file path
    ; Output: AH = status (0=success, 1=not found, 2=error)
    call fs_delete_by_path
    jmp .done

.sys_fs_mkdir:
    ; Create new directory in InodeFS
    ; Input: DS:SI = directory path
    ; Output: AH = status (0=success, 1=already exists, 2=error)
    call fs_mkdir_by_path
    jmp .done

.sys_fs_chdir:
    ; Change current working directory
    ; Input: DS:SI = directory path
    ; Output: AH = status (0=success, 1=not found, 2=error)
    call fs_chdir_by_path
    jmp .done

.done:
    ; Restore all registers and return to caller
    ; By this point, AH contains the syscall result/status
    pop es                  ; restore ES
    pop ds                  ; restore DS
    pop bp                  ; restore BP
    pop di                  ; restore DI
    pop si                  ; restore SI
    pop dx                  ; restore DX
    pop cx                  ; restore CX
    pop bx                  ; restore BX
    iret                    ; return to caller (restores IP, CS, and flags)

; ==================== DISK I/O (BIOS-BACKED) ====================
; Uses BIOS INT 0x13 to read/write sectors
; Handles CHS (Cylinder-Head-Sector) addressing on floppy/hard disk

; disk_read_chs - Read sectors from disk into memory
; Input:
;   AL = sector count (how many sectors to read)
;   CL = starting sector number (1-based, 1-63)
;   ES:BX = destination buffer address
;   DL = drive number (from kernel_boot_drive)
; Output:
;   CF clear on success
;   CF set on error, AH = BIOS error code
; Reliability: one retry after disk reset
disk_read_chs:
    mov [dr_count], al      ; save count for potential retry
    mov [dr_lba], cl        ; save start sector for retry
    mov [dr_dest], bx       ; save dest buffer for retry

    mov byte [dr_retries], 1 ; allow one retry after disk reset

.read_try:
    ; Restore saved parameters for this attempt
    mov cl, [dr_lba]        ; sector number
    call lba_to_chs         ; converts to CHS: CH=cylinder, DH=head
    mov al, [dr_count]      ; sector count
    mov bx, [dr_dest]       ; buffer address
    mov dl, [kernel_boot_drive] ; drive number

    mov ah, 0x02            ; BIOS INT 0x13 function 02H: read sectors
    int 0x13                ; call BIOS disk interrupt
    jnc .ok                 ; CF=0: success, exit

    ; Read failed - BIOS set CF and error code in AH
    mov [dr_last_status], ah

    ; Check if we have retries left
    cmp byte [dr_retries], 0
    je .fail                ; no more retries, return failure

    ; Try again: reset disk and retry
    dec byte [dr_retries]   ; consume one retry
    xor ah, ah              ; BIOS INT 0x13 function 00H: reset disk
    mov dl, [kernel_boot_drive]
    int 0x13
    jmp .read_try

.ok:
    clc                     ; CF=0 indicates success
    ret

.fail:
    mov ah, [dr_last_status]          ; return last BIOS error in AH
    stc                               ; explicit failure
    ret


; disk_write_chs
; Inputs:
;   AL = sector count
;   CL = logical sector number (1-based)
;   ES:BX = source buffer
; Returns:
;   CF clear on success
;   CF set on error, AH = BIOS status
disk_write_chs:
    mov [dr_count], al
    mov [dr_lba], cl
    mov [dr_dest], bx

    mov byte [dr_retries], 1

.write_try:
    mov cl, [dr_lba]
    call lba_to_chs
    mov al, [dr_count]
    mov bx, [dr_dest]
    mov dl, [kernel_boot_drive]

    mov ah, 0x03                      ; BIOS write sectors
    int 0x13
    jnc .write_ok

    mov [dr_last_status], ah
    cmp byte [dr_retries], 0
    je .write_fail ; jump if equal/zero

    dec byte [dr_retries]
    mov ah, 0x00
    mov dl, [kernel_boot_drive]
    int 0x13
    jmp .write_try ; jump unconditionally

.write_ok:
    clc
    ret

.write_fail:
    mov ah, [dr_last_status]
    stc
    ret


; lba_to_chs
; Input: CL = logical sector (1-based)
; Output: CH = cylinder, DH = head, CL = sector (1-based)
; Uses: AX, DX
lba_to_chs:
    xor ax, ax
    mov al, cl
    dec al                          ; convert to zero-based LBA

    xor ah, ah
    mov dl, 36                      ; sectors per cylinder (18*2)
    div dl                          ; AL=cylinder, AH=remainder in cylinder
    mov ch, al

    mov al, ah
    xor ah, ah
    mov dl, 18                      ; sectors per head/track
    div dl                          ; AL=head, AH=sector index
    mov dh, al
    mov cl, ah
    inc cl                          ; back to 1-based sector
    ret


; str_eq
; Input:  DS:SI = string A, DS:DI = string B
; Output: AL = 1 if equal, 0 if not
; Clobbers: AL, BL
str_eq:
.eq_loop:
    mov al, [si]
    mov bl, [di]
    cmp al, bl
    jne .no ; jump if not equal/non-zero
    cmp al, 0
    je .yes ; jump if equal/zero
    inc si
    inc di
    jmp .eq_loop ; jump unconditionally
.yes:
    mov al, 1
    ret
.no:
    mov al, 0
    ret


; str_startswith
; Input:  DS:SI = full string, DS:DI = prefix
; Output: AL = 1 if SI starts with DI, else 0
; Clobbers: AL, BL
str_startswith:
.sw_loop:
    mov al, [di]
    cmp al, 0
    je .yes ; jump if equal/zero
    mov bl, [si]
    cmp bl, al
    jne .no ; jump if not equal/non-zero
    inc si
    inc di
    jmp .sw_loop ; jump unconditionally
.yes:
    mov al, 1
    ret
.no:
    mov al, 0
    ret


launch_shell:
    ; Load csh to 0000:9000
    mov ax, 0
    mov es, ax
    mov bx, 0x9000

    mov al, SHELL_SECTORS      ; shell sector count from build
    mov ch, 0                 ; cylinder 0
    mov cl, [BOOT_KSECT_OFF]  ; kernel sectors from boot info
    add cl, 2                 ; shell starts after boot(1) + kernel
    mov dh, 0                 ; head 0

    call disk_read_chs
    jc .load_fail

    call 0x9000               ; run shell, return to kernel when shell does RET
    ret

.load_fail:
    mov si, shell_load_fail_msg
    call console_puts
    call console_newline
    ret

; load_program_table
; Reads a tiny filesystem program table from FS_TABLE_SECTOR into PROG_TABLE_ADDR.
; Output: AH = 0 success, 1 read fail, 2 bad magic, 3 bad entry count, 4 bad layout
load_program_table:
    mov ax, 0
    mov es, ax
    mov bx, PROG_TABLE_ADDR
    mov al, 1
    mov ch, 0
    mov cl, FS_TABLE_SECTOR
    mov dh, 0
    call disk_read_chs
    jc .read_fail

    cmp byte [PROG_TABLE_ADDR + 0], 'C'
    jne .bad_magic ; jump if not equal/non-zero
    cmp byte [PROG_TABLE_ADDR + 1], 'F'
    jne .bad_magic ; jump if not equal/non-zero
    cmp byte [PROG_TABLE_ADDR + 2], 'S'
    jne .bad_magic ; jump if not equal/non-zero
    cmp byte [PROG_TABLE_ADDR + 3], '1'
    jne .bad_magic ; jump if not equal/non-zero

    mov al, [PROG_TABLE_ADDR + 4]
    cmp al, PROG_TABLE_MAX_ENTRIES
    ja .bad_count
    mov [prog_table_count], al

    call validate_program_table_layout
    cmp ah, 0
    jne .bad_layout ; jump if not equal/non-zero

    mov byte [prog_table_loaded], 1
%if DEBUG
        mov si, debug_loaded_msg
        call console_puts
        mov al, [prog_table_count]
    cmp al, 10
    jb .dbg_one_digit
    mov al, '1'
    call console_putc
    mov al, [prog_table_count]
    sub al, 10
    add al, '0'
    call console_putc
    jmp .dbg_count_done ; jump unconditionally
.dbg_one_digit:
    add al, '0'
    call console_putc
.dbg_count_done:
        mov si, debug_newline
        call console_puts
%endif
    xor ah, ah
    ret

.read_fail:
    mov byte [prog_table_loaded], 0
    mov ah, 1
    ret

.bad_magic:
    mov byte [prog_table_loaded], 0
    mov ah, 2
    ret

.bad_count:
    mov byte [prog_table_loaded], 0
    mov ah, 3
    ret

.bad_layout:
    mov byte [prog_table_loaded], 0
    mov ah, 4
    ret

; validate_program_table_layout
; Ensures every entry has valid start/count and does not overlap FS table sector.
; Output: AH = 0 valid, 4 invalid
validate_program_table_layout:
    mov byte [pt_index], 0

.v_loop:
    mov bl, [pt_index]
    cmp bl, [prog_table_count]
    jae .v_ok

    xor ax, ax
    mov al, bl
    shl ax, 4
    mov di, PROG_TABLE_ADDR + 16
    add di, ax

    mov al, [di + 8]                  ; start sector
    mov ah, [di + 9]                  ; sector count

    cmp al, 1
    jb .v_bad
    cmp ah, 0
    je .v_bad ; jump if equal/zero

    mov bl, al
    add bl, ah
    jc .v_bad
    dec bl                            ; end sector

    mov dl, FS_TABLE_SECTOR
    cmp dl, al
    jb .v_next
    cmp dl, bl
    jbe .v_bad

.v_next:
    inc byte [pt_index]
    jmp .v_loop ; jump unconditionally

.v_ok:
    xor ah, ah
    ret

.v_bad:
    mov ah, 4
    ret

; run_named_program
; Input: DS:SI = null-terminated program name
; Output: AH = status (0=ok, 1=unknown name, 2=load fail, 3=fs unavailable)
run_named_program:
    cmp byte [prog_table_loaded], 1
    jne .fs_unavailable ; jump if not equal/non-zero

    mov [run_name_ptr], si
    xor bx, bx
%if DEBUG
    mov si, debug_searching
    call console_puts
    mov si, [run_name_ptr]
    call console_puts
    mov si, debug_newline
    call console_puts
%endif
    mov si, [run_name_ptr]

.search_loop:
    cmp bl, [prog_table_count]
    jae .unknown

    ; DI = PROG_TABLE_ADDR + 16 + (index * PROG_ENTRY_SIZE)
    xor ax, ax
    mov al, bl
    shl ax, 4
    mov di, PROG_TABLE_ADDR + 16
    add di, ax

    mov si, [run_name_ptr]
    push bx
    call str_eq
    pop bx
    cmp al, 1
    je .found ; jump if equal/zero

    inc bl
    jmp .search_loop ; jump unconditionally

.found:
    ; Recompute entry pointer in DI
    xor ax, ax
    mov al, bl
    shl ax, 4
    mov di, PROG_TABLE_ADDR + 16
    add di, ax

    ; Entry layout:
    ; +0..+7  name[8]
    ; +8      start_sector
    ; +9      sector_count
    ; +10..11 load_offset
    ; +12..13 entry_offset
    ; +14     entry_type (1=program, 2=text)

    cmp byte [di + 14], 1
    jne .unknown ; jump if not equal/non-zero

    mov ax, 0
    mov es, ax
    mov bx, [di + 10]
    mov al, [di + 9]
    mov ch, 0
    mov cl, [di + 8]
    mov dh, 0
    push di
    call disk_read_chs
    pop di
    jc .load_fail

    mov bx, [di + 10]
    add bx, [di + 12]
    call bx

    xor ah, ah
    ret

.unknown:
    mov ah, 1
    ret

.load_fail:
    mov ah, 2
    ret

.fs_unavailable:
    mov ah, 3
    ret

; -----------------------------
; InodeFS core helpers
; -----------------------------

; fs_mount_or_format
; Ensures the writable inode filesystem is present.
; If magic is missing, formats a fresh empty filesystem.
fs_mount_or_format:
    mov byte [fs_inode_ready], 0
    mov byte [fs_cwd_inode], INFS_ROOT_INODE

    mov ax, 0
    mov es, ax
    mov bx, INFS_SUPER_BUF
    mov al, 1
    mov ch, 0
    mov cl, INFS_SUPER_SECTOR
    mov dh, 0
    call disk_read_chs
    jc .format

    cmp byte [INFS_SUPER_BUF + 0], 'I'
    jne .format ; jump if not equal/non-zero
    cmp byte [INFS_SUPER_BUF + 1], 'N'
    jne .format ; jump if not equal/non-zero
    cmp byte [INFS_SUPER_BUF + 2], 'D'
    jne .format ; jump if not equal/non-zero
    cmp byte [INFS_SUPER_BUF + 3], '2'
    jne .format ; jump if not equal/non-zero

    mov byte [fs_inode_ready], 1
    ret

.format:
    call fs_format
    ret

; fs_format
; Writes empty superblock/inode table/bitmap to disk.
; Output: AH=0 success, AH=2 disk error
fs_format:
    ; Clear superblock buffer
    mov ax, 0
    mov es, ax
    mov di, INFS_SUPER_BUF
    mov cx, 512
    xor al, al
    rep stosb

    ; Fill superblock header metadata.
    mov byte [INFS_SUPER_BUF + 0], 'I'
    mov byte [INFS_SUPER_BUF + 1], 'N'
    mov byte [INFS_SUPER_BUF + 2], 'D'
    mov byte [INFS_SUPER_BUF + 3], '2'
    mov byte [INFS_SUPER_BUF + 4], 2                      ; format version
    mov byte [INFS_SUPER_BUF + 5], INFS_MAX_INODES
    mov byte [INFS_SUPER_BUF + 6], INFS_DATA_START_SECTOR
    mov byte [INFS_SUPER_BUF + 7], INFS_MAX_BLOCKS

    mov bx, INFS_SUPER_BUF
    mov al, 1
    mov ch, 0
    mov cl, INFS_SUPER_SECTOR
    mov dh, 0
    call disk_write_chs
    jc .io_fail

    ; Clear inode table sector and create root directory inode at index 0.
    mov di, INFS_INODE_BUF
    mov cx, 512
    xor al, al
    rep stosb

    mov byte [INFS_INODE_BUF + INFS_OFF_USED], 1
    mov byte [INFS_INODE_BUF + INFS_OFF_TYPE], INFS_TYPE_DIR
    mov word [INFS_INODE_BUF + INFS_OFF_SIZE], 0
    mov byte [INFS_INODE_BUF + INFS_OFF_START], 0
    mov byte [INFS_INODE_BUF + INFS_OFF_COUNT], 0
    mov byte [INFS_INODE_BUF + INFS_OFF_PARENT], 0xFF
    mov byte [INFS_INODE_BUF + INFS_OFF_NAME + 0], '/'
    mov byte [INFS_INODE_BUF + INFS_OFF_NAME + 1], 0

    mov bx, INFS_INODE_BUF
    mov al, 1
    mov ch, 0
    mov cl, INFS_INODE_SECTOR
    mov dh, 0
    call disk_write_chs
    jc .io_fail

    ; Clear bitmap sector.
    mov di, INFS_BITMAP_BUF
    mov cx, 512
    xor al, al
    rep stosb

    mov bx, INFS_BITMAP_BUF
    mov al, 1
    mov ch, 0
    mov cl, INFS_BITMAP_SECTOR
    mov dh, 0
    call disk_write_chs
    jc .io_fail

    mov byte [fs_inode_ready], 1
    mov byte [fs_cwd_inode], INFS_ROOT_INODE
    xor ah, ah
    ret

.io_fail:
    mov byte [fs_inode_ready], 0
    mov ah, 2
    ret

; fs_find_inode_by_name
; Input: AL = parent inode index, DS:SI = leaf name (no '/').
; Output: AH=0 found (BL=index, DI=inode ptr), AH=1 not found, AH=2 io fail
fs_find_inode_by_name:
    cmp byte [fs_inode_ready], 1
    jne .io_fail ; jump if not equal/non-zero

    mov [fs_name_ptr], si
    mov [fs_parent_index], al

    call fs_load_inode_table
    jc .io_fail

    xor bl, bl
.scan_loop:
    cmp bl, INFS_MAX_INODES
    jae .not_found

    xor ax, ax
    mov al, bl
    shl ax, 4
    mov di, INFS_INODE_BUF
    add di, ax

    cmp byte [di + INFS_OFF_USED], 1
    jne .next ; jump if not equal/non-zero

    mov al, [fs_parent_index]
    cmp byte [di + INFS_OFF_PARENT], al
    jne .next ; jump if not equal/non-zero

    mov si, [fs_name_ptr]
    push bx
    push di
    call fs_name_eq_inode_name
    pop di
    pop bx
    cmp al, 1
    je .found ; jump if equal/zero

.next:
    inc bl
    jmp .scan_loop ; jump unconditionally

.found:
    mov al, bl
    xor ah, ah
    ret

.not_found:
    mov ah, 1
    ret

.io_fail:
    mov ah, 2
    ret

; fs_name_eq_inode_name
; Input: DS:SI = user name, DS:DI = inode record pointer
; Output: AL=1 equal, AL=0 not equal
fs_name_eq_inode_name:
    mov cx, INFS_NAME_LEN
.cmp_loop:
    mov al, [si]
    mov bl, [di + INFS_OFF_NAME]
    cmp al, bl
    jne .no ; jump if not equal/non-zero
    cmp al, 0
    je .yes ; jump if equal/zero
    inc si
    inc di
    dec cx
    jnz .cmp_loop ; jump if not equal/non-zero

    cmp byte [si], 0
    je .yes ; jump if equal/zero
.no:
    xor al, al
    ret
.yes:
    mov al, 1
    ret

; fs_list_file_by_ordinal
; Input: AL = 0-based ordinal among active entries inside directory DS:SI
;        ES:BX = output name buffer (>=11 bytes)
; Output: AH=0 ok, AH=1 end, AH=2 io
;         CX = file size on success
;         DL = inode type
fs_list_file_by_ordinal:
    cmp byte [fs_inode_ready], 1
    jne .io_fail ; jump if not equal/non-zero

    mov [fs_ordinal], al
    mov [fs_name_ptr], si

    call fs_load_inode_table
    jc .io_fail

    mov si, [fs_name_ptr]
    call fs_resolve_path_loaded
    cmp ah, 0
    jne .io_fail ; jump if not equal/non-zero

    mov [fs_parent_index], al

    push es
    push bx

    xor bl, bl
.list_scan:
    cmp bl, INFS_MAX_INODES
    jae .list_end

    xor ax, ax
    mov al, bl
    shl ax, 4
    mov di, INFS_INODE_BUF
    add di, ax

    cmp byte [di + INFS_OFF_USED], 1
    jne .list_next ; jump if not equal/non-zero

    ; Ignore entries with empty names to avoid showing blank/corrupt files.
    cmp byte [di + INFS_OFF_NAME], 0
    je .list_next ; jump if equal/zero

    mov al, [fs_parent_index]
    cmp byte [di + INFS_OFF_PARENT], al
    jne .list_next ; jump if not equal/non-zero

    cmp byte [fs_ordinal], 0
    je .emit ; jump if equal/zero
    dec byte [fs_ordinal]

.list_next:
    inc bl
    jmp .list_scan ; jump unconditionally

.emit:
    pop bx
    pop es

    push di
    mov cx, INFS_NAME_LEN
    mov si, di
    add si, INFS_OFF_NAME
.copy_name:
    mov al, [si]
    mov [es:bx], al
    inc si
    inc bx
    cmp al, 0
    je .name_done ; jump if equal/zero
    loop .copy_name
    mov byte [es:bx], 0
.name_done:
    pop di

    mov cx, [di + INFS_OFF_SIZE]
    mov dl, [di + INFS_OFF_TYPE]
    xor ah, ah
    ret

.list_end:
    pop bx
    pop es
    mov ah, 1
    ret

.list_io_fail:
    pop bx
    pop es
.io_fail:
    mov ah, 2
    ret

; fs_read_file_by_name
; Input: DS:SI = path
;        ES:BX = output buffer
; Output: AH=0 ok, AH=1 not found, AH=2 io
;         CX = bytes in file
fs_read_file_by_name:
    cmp byte [fs_inode_ready], 1
    jne .io_fail ; jump if not equal/non-zero

    call fs_load_inode_table
    jc .io_fail

    call fs_resolve_path_loaded
    cmp ah, 0
    jne .not_found ; jump if not equal/non-zero

    cmp byte [di + INFS_OFF_TYPE], INFS_TYPE_DIR
    je .not_found ; jump if equal/zero

    mov cx, [di + INFS_OFF_SIZE]
    cmp cx, 0
    je .ok ; jump if equal/zero

    mov al, [di + INFS_OFF_COUNT]
    cmp al, 0
    je .ok ; jump if equal/zero

    mov dl, [di + INFS_OFF_START]
    mov cl, INFS_DATA_START_SECTOR
    add cl, dl
    mov ch, 0
    mov dh, 0
    call disk_read_chs
    jc .io_fail

.ok:
    xor ah, ah
    ret

.not_found:
    mov ah, 1
    ret

.io_fail:
    mov ah, 2
    ret

; fs_write_file_by_name
; Input: DS:SI = path
;        ES:BX = input data buffer
;        CX = byte count
; Output: AH=0 ok, AH=1 no space, AH=2 io
fs_write_file_by_name:
    cmp byte [fs_inode_ready], 1
    jne .io_fail ; jump if not equal/non-zero

    mov [fs_path_ptr], si
    mov [fs_write_buf], bx
    mov [fs_write_len], cx

    call fs_load_inode_table
    jc .io_fail

    call fs_load_bitmap
    jc .io_fail

    ; Try resolve existing path.
    mov si, [fs_path_ptr]
    call fs_resolve_path_loaded
    cmp ah, 0
    je .existing ; jump if equal/zero

    ; Not found: resolve parent + leaf and allocate inode.
    mov si, [fs_path_ptr]
    call fs_split_parent_leaf_loaded
    cmp ah, 0
    jne .no_space ; jump if not equal/non-zero

    ; Reject if leaf already exists under parent.
    mov al, [fs_parent_index]
    mov si, fs_leaf_name
    call fs_find_inode_in_loaded
    cmp ah, 0
    je .no_space ; jump if equal/zero

    call fs_alloc_inode_loaded
    cmp ah, 0
    jne .no_space ; jump if not equal/non-zero

    ; Initialize new inode metadata.
    mov byte [di + INFS_OFF_USED], 1
    mov byte [di + INFS_OFF_TYPE], INFS_TYPE_FILE
    mov al, [fs_parent_index]
    mov byte [di + INFS_OFF_PARENT], al
    call fs_name_copy_leaf_to_inode

    ; Mark .arc files as script type.
    call fs_leaf_is_arc
    cmp al, 1
    jne .inode_ready ; jump if not equal/non-zero
    mov byte [di + INFS_OFF_TYPE], INFS_TYPE_ARC
    jmp .inode_ready ; jump unconditionally

.existing:
    cmp byte [di + INFS_OFF_TYPE], INFS_TYPE_DIR
    je .no_space ; jump if equal/zero

.inode_ready:
    ; Free old allocation if present.
    mov dl, [di + INFS_OFF_START]
    mov dh, [di + INFS_OFF_COUNT]
    call fs_free_run_loaded

    mov word [di + INFS_OFF_SIZE], 0
    mov byte [di + INFS_OFF_START], 0
    mov byte [di + INFS_OFF_COUNT], 0

    mov ax, [fs_write_len]
    cmp ax, 0
    je .save_all ; jump if equal/zero

    add ax, 511
    shr ax, 9
    mov [fs_need_blocks], al

    mov al, [fs_need_blocks]
    call fs_alloc_run_loaded
    cmp ah, 0
    jne .no_space ; jump if not equal/non-zero

    mov [fs_start_block], al
    mov [di + INFS_OFF_START], al
    mov al, [fs_need_blocks]
    mov [di + INFS_OFF_COUNT], al

    ; Write file payload blocks to disk.
    mov ax, 0
    mov es, ax
    mov bx, [fs_write_buf]
    mov al, [fs_need_blocks]
    mov ch, 0
    mov cl, INFS_DATA_START_SECTOR
    add cl, [fs_start_block]
    mov dh, 0
    call disk_write_chs
    jc .io_fail

    mov ax, [fs_write_len]
    mov [di + INFS_OFF_SIZE], ax

.save_all:
    call fs_save_bitmap
    jc .io_fail
    call fs_save_inode_table
    jc .io_fail

    xor ah, ah
    ret

.no_space:
    mov ah, 1
    ret

.io_fail:
    mov ah, 2
    ret

; fs_delete_by_path
; Input: DS:SI = path
; Output: AH=0 ok, AH=1 not found/invalid, AH=2 io, AH=3 dir not empty
fs_delete_by_path:
    cmp byte [fs_inode_ready], 1
    jne .io_fail ; jump if not equal/non-zero

    call fs_load_inode_table
    jc .io_fail
    call fs_load_bitmap
    jc .io_fail

    call fs_resolve_path_loaded
    cmp ah, 0
    jne .not_found ; jump if not equal/non-zero

    mov [fs_target_index], al

    cmp al, INFS_ROOT_INODE
    je .not_found ; jump if equal/zero

    cmp byte [di + INFS_OFF_TYPE], INFS_TYPE_DIR
    jne .free_delete ; jump if not equal/non-zero

    ; Directories must be empty before deletion.
    mov bl, 0
.check_child:
    cmp bl, INFS_MAX_INODES
    jae .free_delete
    xor ax, ax
    mov al, bl
    shl ax, 4
    mov bx, INFS_INODE_BUF
    add bx, ax
    cmp byte [bx + INFS_OFF_USED], 1
    jne .next_child ; jump if not equal/non-zero
    mov al, [fs_target_index]
    cmp byte [bx + INFS_OFF_PARENT], al
    je .dir_not_empty ; jump if equal/zero
.next_child:
    inc bl
    jmp .check_child ; jump unconditionally

.free_delete:
    mov dl, [di + INFS_OFF_START]
    mov dh, [di + INFS_OFF_COUNT]
    call fs_free_run_loaded

    ; Clear inode record.
    push di
    mov cx, INFS_INODE_SIZE
    xor al, al
    rep stosb
    pop di

    call fs_save_bitmap
    jc .io_fail
    call fs_save_inode_table
    jc .io_fail

    xor ah, ah
    ret

.dir_not_empty:
    mov ah, 3
    ret

.not_found:
    mov ah, 1
    ret

.io_fail:
    mov ah, 2
    ret

; fs_mkdir_by_path
; Input: DS:SI = path
; Output: AH=0 ok, AH=1 invalid/exist, AH=2 io
fs_mkdir_by_path:
    cmp byte [fs_inode_ready], 1
    jne .io_fail ; jump if not equal/non-zero

    call fs_load_inode_table
    jc .io_fail

    ; Path must not already exist.
    push si
    call fs_resolve_path_loaded
    cmp ah, 0
    je .exists ; jump if equal/zero
    pop si

    ; Resolve parent directory and leaf.
    call fs_split_parent_leaf_loaded
    cmp ah, 0
    jne .invalid ; jump if not equal/non-zero

    call fs_alloc_inode_loaded
    cmp ah, 0
    jne .invalid ; jump if not equal/non-zero

    mov byte [di + INFS_OFF_USED], 1
    mov byte [di + INFS_OFF_TYPE], INFS_TYPE_DIR
    mov word [di + INFS_OFF_SIZE], 0
    mov byte [di + INFS_OFF_START], 0
    mov byte [di + INFS_OFF_COUNT], 0
    mov al, [fs_parent_index]
    mov [di + INFS_OFF_PARENT], al
    call fs_name_copy_leaf_to_inode

    call fs_save_inode_table
    jc .io_fail
    xor ah, ah
    ret

.exists:
    pop si
.invalid:
    mov ah, 1
    ret

.io_fail:
    mov ah, 2
    ret

; fs_chdir_by_path
; Input: DS:SI = path
; Output: AH=0 ok, AH=1 invalid/not found, AH=2 io
fs_chdir_by_path:
    cmp byte [fs_inode_ready], 1
    jne .io_fail ; jump if not equal/non-zero
    call fs_load_inode_table
    jc .io_fail
    call fs_resolve_path_loaded
    cmp ah, 0
    jne .invalid ; jump if not equal/non-zero
    cmp byte [di + INFS_OFF_TYPE], INFS_TYPE_DIR
    jne .invalid ; jump if not equal/non-zero
    mov [fs_cwd_inode], al
    xor ah, ah
    ret

.invalid:
    mov ah, 1
    ret

.io_fail:
    mov ah, 2
    ret

; fs_load_inode_table
; Loads inode table sector to INFS_INODE_BUF. CF set on error.
fs_load_inode_table:
    mov ax, 0
    mov es, ax
    mov bx, INFS_INODE_BUF
    mov al, 1
    mov ch, 0
    mov cl, INFS_INODE_SECTOR
    mov dh, 0
    call disk_read_chs
    ret

; fs_save_inode_table
; Writes inode table sector from INFS_INODE_BUF. CF set on error.
fs_save_inode_table:
    mov ax, 0
    mov es, ax
    mov bx, INFS_INODE_BUF
    mov al, 1
    mov ch, 0
    mov cl, INFS_INODE_SECTOR
    mov dh, 0
    call disk_write_chs
    ret

; fs_load_bitmap
; Loads bitmap sector to INFS_BITMAP_BUF. CF set on error.
fs_load_bitmap:
    mov ax, 0
    mov es, ax
    mov bx, INFS_BITMAP_BUF
    mov al, 1
    mov ch, 0
    mov cl, INFS_BITMAP_SECTOR
    mov dh, 0
    call disk_read_chs
    ret

; fs_save_bitmap
; Writes bitmap sector from INFS_BITMAP_BUF. CF set on error.
fs_save_bitmap:
    mov ax, 0
    mov es, ax
    mov bx, INFS_BITMAP_BUF
    mov al, 1
    mov ch, 0
    mov cl, INFS_BITMAP_SECTOR
    mov dh, 0
    call disk_write_chs
    ret

; fs_get_inode_ptr
; Input: AL=index, Output: DI=inode pointer in INFS_INODE_BUF
fs_get_inode_ptr:
    xor ah, ah
    shl ax, 4
    mov di, INFS_INODE_BUF
    add di, ax
    ret

; fs_path_next_segment
; Input: DS:SI path cursor
; Output: AL=1 segment copied, AL=0 no more
;         AH=1 segment is last, AH=0 more remains
;         SI advanced to delimiter (0 or '/')
;         fs_seg_name filled with null-terminated segment
fs_path_next_segment:
.skip_slash:
    cmp byte [si], '/'
    jne .begin ; jump if not equal/non-zero
    inc si
    jmp .skip_slash ; jump unconditionally

.begin:
    cmp byte [si], 0
    jne .copy ; jump if not equal/non-zero
    xor al, al
    xor ah, ah
    ret

.copy:
    mov di, fs_seg_name
    mov cx, INFS_NAME_LEN
.copy_loop:
    mov al, [si]
    cmp al, 0
    je .finish_last ; jump if equal/zero
    cmp al, '/'
    je .finish_more ; jump if equal/zero
    cmp cx, 0
    je .skip_store ; jump if equal/zero
    mov [di], al
    inc di
    dec cx
.skip_store:
    inc si
    jmp .copy_loop ; jump unconditionally

.finish_more:
    mov byte [di], 0
    mov al, 1
    xor ah, ah
    ret

.finish_last:
    mov byte [di], 0
    mov al, 1
    mov ah, 1
    ret

; fs_find_inode_in_loaded
; Input: AL=parent index, DS:SI=leaf name
; Output: AH=0 found (BL=index, DI=ptr), AH=1 not found
fs_find_inode_in_loaded:
    mov [fs_parent_index], al
    xor bl, bl
.scan:
    cmp bl, INFS_MAX_INODES
    jae .nf
    xor ax, ax
    mov al, bl
    shl ax, 4
    mov di, INFS_INODE_BUF
    add di, ax
    cmp byte [di + INFS_OFF_USED], 1
    jne .next ; jump if not equal/non-zero
    mov al, [fs_parent_index]
    cmp byte [di + INFS_OFF_PARENT], al
    jne .next ; jump if not equal/non-zero
    push bx
    push di
    call fs_name_eq_inode_name
    pop di
    pop bx
    cmp al, 1
    je .ok ; jump if equal/zero
.next:
    inc bl
    jmp .scan ; jump unconditionally
.ok:
    xor ah, ah
    ret
.nf:
    mov ah, 1
    ret

; fs_resolve_path_loaded
; Input: DS:SI path
; Output: AH=0 found (AL=index, DI=ptr), AH=1 not found/invalid
fs_resolve_path_loaded:
    mov al, [si]
    cmp al, '/'
    jne .from_cwd ; jump if not equal/non-zero
    mov al, INFS_ROOT_INODE
    jmp .set_curr ; jump unconditionally
.from_cwd:
    mov al, [fs_cwd_inode]
.set_curr:
    mov [fs_curr_index], al

.seg_loop:
    call fs_path_next_segment
    cmp al, 0
    je .done ; jump if equal/zero

    ; Handle . and ..
    cmp byte [fs_seg_name], '.'
    jne .not_dot ; jump if not equal/non-zero
    cmp byte [fs_seg_name + 1], 0
    je .advance ; jump if equal/zero
    cmp byte [fs_seg_name + 1], '.'
    jne .not_dot ; jump if not equal/non-zero
    cmp byte [fs_seg_name + 2], 0
    jne .not_dot ; jump if not equal/non-zero

    mov al, [fs_curr_index]
    call fs_get_inode_ptr
    mov al, [di + INFS_OFF_PARENT]
    cmp al, 0xFF
    je .advance ; jump if equal/zero
    mov [fs_curr_index], al
    jmp .advance ; jump unconditionally

.not_dot:
    mov al, [fs_curr_index]
    mov si, fs_seg_name
    call fs_find_inode_in_loaded
    cmp ah, 0
    jne .not_found ; jump if not equal/non-zero
    mov [fs_curr_index], bl

.advance:
    cmp ah, 1
    je .done ; jump if equal/zero
    cmp byte [si], '/'
    jne .seg_loop ; jump if not equal/non-zero
    inc si
    jmp .seg_loop ; jump unconditionally

.done:
    mov al, [fs_curr_index]
    call fs_get_inode_ptr
    xor ah, ah
    ret

.not_found:
    mov ah, 1
    ret

; fs_split_parent_leaf_loaded
; Input: DS:SI path
; Output: AH=0 ok (fs_parent_index + fs_leaf_name), AH=1 invalid
fs_split_parent_leaf_loaded:
    mov al, [si]
    cmp al, '/'
    jne .from_cwd ; jump if not equal/non-zero
    mov al, INFS_ROOT_INODE
    jmp .set_parent ; jump unconditionally
.from_cwd:
    mov al, [fs_cwd_inode]
.set_parent:
    mov [fs_parent_index], al

.next_seg:
    call fs_path_next_segment
    cmp al, 0
    je .invalid ; jump if equal/zero

    ; Save this segment as candidate leaf.
    mov si, fs_seg_name
    mov di, fs_leaf_name
    mov cx, INFS_NAME_LEN
.copy_leaf:
    mov al, [si]
    mov [di], al
    inc si
    inc di
    cmp al, 0
    je .leaf_done ; jump if equal/zero
    loop .copy_leaf
    mov byte [di], 0
.leaf_done:

    cmp ah, 1
    je .ok ; jump if equal/zero

    ; Descend through directory segment.
    mov al, [fs_parent_index]
    mov si, fs_seg_name
    call fs_find_inode_in_loaded
    cmp ah, 0
    jne .invalid ; jump if not equal/non-zero
    cmp byte [di + INFS_OFF_TYPE], INFS_TYPE_DIR
    jne .invalid ; jump if not equal/non-zero
    mov [fs_parent_index], bl

    cmp byte [si], '/'
    jne .next_seg ; jump if not equal/non-zero
    inc si
    jmp .next_seg ; jump unconditionally

.ok:
    xor ah, ah
    ret

.invalid:
    mov ah, 1
    ret

; fs_alloc_inode_loaded
; Output: AH=0 and DI pointer on success, AH=1 if none
fs_alloc_inode_loaded:
    xor bl, bl
.find:
    cmp bl, INFS_MAX_INODES
    jae .none
    xor ax, ax
    mov al, bl
    shl ax, 4
    mov di, INFS_INODE_BUF
    add di, ax
    cmp byte [di + INFS_OFF_USED], 0
    je .ok ; jump if equal/zero
    inc bl
    jmp .find ; jump unconditionally
.ok:
    xor ah, ah
    ret
.none:
    mov ah, 1
    ret

; fs_name_copy_leaf_to_inode
; Input: DI inode ptr, fs_leaf_name source
fs_name_copy_leaf_to_inode:
    push di
    add di, INFS_OFF_NAME
    mov si, fs_leaf_name
    mov cx, INFS_NAME_LEN
.cpy:
    mov al, [si]
    mov [di], al
    inc si
    inc di
    cmp al, 0
    je .zero ; jump if equal/zero
    loop .cpy
    pop di
    ret
.zero:
    dec cx
    jz .done ; jump if equal/zero
.zl:
    mov byte [di], 0
    inc di
    dec cx
    jnz .zl ; jump if not equal/non-zero
.done:
    pop di
    ret

; fs_leaf_is_arc
; Output: AL=1 if leaf ends with ".arc", else 0
fs_leaf_is_arc:
    mov si, fs_leaf_name
    xor cx, cx
.len:
    cmp byte [si], 0
    je .check ; jump if equal/zero
    inc si
    inc cx
    jmp .len ; jump unconditionally
.check:
    cmp cx, 4
    jb .no
    mov si, fs_leaf_name
    add si, cx
    sub si, 4
    cmp byte [si + 0], '.'
    jne .no ; jump if not equal/non-zero
    cmp byte [si + 1], 'a'
    jne .no ; jump if not equal/non-zero
    cmp byte [si + 2], 'r'
    jne .no ; jump if not equal/non-zero
    cmp byte [si + 3], 'c'
    jne .no ; jump if not equal/non-zero
    mov al, 1
    ret
.no:
    xor al, al
    ret

; fs_free_run_loaded
; Input: DL start_block, DH count
fs_free_run_loaded:
    cmp dh, 0
    je .ret ; jump if equal/zero
    xor bx, bx
    mov bl, dl
.loop:
    cmp dh, 0
    je .ret ; jump if equal/zero
    mov byte [INFS_BITMAP_BUF + bx], 0
    inc bl
    dec dh
    jmp .loop ; jump unconditionally
.ret:
    ret

; fs_alloc_run_loaded
; Input: AL blocks needed
; Output: AH=0 and AL=start block, AH=1 no space
fs_alloc_run_loaded:
    mov [fs_need_blocks], al
    xor dl, dl
.search:
    mov al, [fs_need_blocks]
    mov bl, dl
    add bl, al
    cmp bl, INFS_MAX_BLOCKS
    ja .no

    mov bl, dl
    mov cl, [fs_need_blocks]
.probe:
    cmp byte [INFS_BITMAP_BUF + bx], 0
    jne .next ; jump if not equal/non-zero
    inc bl
    dec cl
    jnz .probe ; jump if not equal/non-zero

    mov bl, dl
    mov cl, [fs_need_blocks]
.mark:
    mov byte [INFS_BITMAP_BUF + bx], 1
    inc bl
    dec cl
    jnz .mark ; jump if not equal/non-zero

    mov al, dl
    xor ah, ah
    ret

.next:
    inc dl
    cmp dl, INFS_MAX_BLOCKS
    jb .search
.no:
    mov ah, 1
    ret

; ----------------------------------
; disk_read_chs scratch state (kernel globals)
; ----------------------------------
dr_count:
    db 0
dr_lba:
    db 0
dr_dest:
    dw 0
dr_retries:
    db 0
dr_last_status:
    db 0

prog_table_loaded:
    db 0
prog_table_count:
    db 0
run_name_ptr:
    dw 0
pt_index:
    db 0

; InodeFS runtime state scratch
fs_inode_ready:
    db 0
fs_cwd_inode:
    db 0
fs_name_ptr:
    dw 0
fs_path_ptr:
    dw 0
fs_ordinal:
    db 0
fs_inode_index:
    db 0
fs_parent_index:
    db 0
fs_curr_index:
    db 0
fs_target_index:
    db 0
fs_need_blocks:
    db 0
fs_start_block:
    db 0
fs_write_len:
    dw 0
fs_write_buf:
    dw 0
fs_seg_name:
    times INFS_NAME_LEN + 1 db 0
fs_leaf_name:
    times INFS_NAME_LEN + 1 db 0


; --------------------------------DATA SECTION------------------------------------
; Minimal flat GDT for future protected-mode transition:
;   selector 0x08 -> code segment
;   selector 0x10 -> data segment
gdt_start:
    dq 0x0000000000000000
    dq 0x00CF9A000000FFFF
    dq 0x00CF92000000FFFF
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

logo_line_01:
    db "                         ######                         ", 0
logo_line_02:
    db "                     ####  ##  ####                     ", 0
logo_line_03:
    db "                   ##      ##      ##                   ", 0
logo_line_04:
    db "                 ##      ##  ##      ##                 ", 0
logo_line_05:
    db "               ##      ##      ##      ##               ", 0
logo_line_06:
    db "               ##    ##          ##    ##               ", 0
logo_line_07:
    db "             ##    ##              ##    ##             ", 0
logo_line_08:
    db "             ######                  ######             ", 0
logo_line_09:
    db "             ##    ##              ##    ##             ", 0
logo_line_10:
    db "               ##    ##          ##    ##               ", 0
logo_line_11:
    db "               ##      ##      ##      ##               ", 0
logo_line_12:
    db "                 ##      ##  ##      ##                 ", 0
logo_line_13:
    db "                   ##      ##      ##                   ", 0
logo_line_14:
    db "                     ####  ##  ####                     ", 0
logo_line_15:
    db "                         ######                         ", 0

welcome_msg:
    db "Welcome to CircleOS v0.1.22!", 13, 10, 0

help_msg:
    db "Available kernel commands:", 13, 10
    db "  help   - show this message", 13, 10
    db "  csh    - launch Circle shell", 13, 10, 0

prompt:
    db "CircleOS Kernel > ", 0

unknown_msg:
    db "Unknown kernel command. Type 'csh' to open shell.", 13, 10, 0

boot_info_bad_msg:
    db "BOOT INFO INVALID", 13, 10, 0

prog_table_bad_msg:
    db "Program table load/validation failed", 0

debug_searching:
    db "[DEBUG] Searching for program: ", 0
debug_newline:
    db 13, 10, 0
debug_loaded_msg:
     db "[DEBUG] Program table loaded with ", 0
cmd_help_str:
    db "help", 0
cmd_csh_str:
    db "csh", 0

shell_load_fail_msg:
    db "Failed to load csh", 0
command_buf:
    times 32 db 0   ; input storage.



