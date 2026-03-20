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

%ifndef DEBUG
%assign DEBUG 0
%endif

%ifndef FS_TABLE_SECTOR
FS_TABLE_SECTOR equ 17
%endif

%ifndef SHELL_SECTORS
SHELL_SECTORS equ 1
%endif

PROG_TABLE_ADDR equ 0x0600
PROG_TABLE_MAX_ENTRIES equ 16
PROG_ENTRY_SIZE equ 16
PROG_NAME_LEN equ 8


start:
    mov ax, 0           ; clear register AX temporarily to initialise segment registers
    mov ds, ax          ; clear and initialise data segment
    mov es, ax          ; clear and initialise extra segment

    ; Early protected-mode groundwork:
    ; 1) enable A20 so addresses above 1MB are usable later
    ; 2) load a flat GDT so we can transition in a later phase
    call enable_a20
    call load_boot_gdt

    cmp byte [BOOT_SIG0_OFF], 'C'
    jne .boot_info_bad
    cmp byte [BOOT_SIG1_OFF], 'B'
    jne .boot_info_bad

    mov al, [BOOT_DRIVE_OFF]
    mov [kernel_boot_drive], al
    call install_syscall_vector
    call load_program_table
    cmp ah, 0
    jne .prog_table_bad

    call show_boot_logo
    call delay_5s
    call console_clear

    ; Use kernel as backend and start userspace shell directly.
    call launch_shell
    jmp .shell_loop

    mov si, welcome_msg    ; move boot message to source
    call console_puts   ; calls print string (prints SI)

        jmp .shell_loop


.boot_info_bad:
    mov si, boot_info_bad_msg   ; boot info bad handler, alerts if boot info bad
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
    je .backspace       ; jump if ZF is set, if AL = 8 then the previous line set ZF so jump to .backspace jump target

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
    jmp .read_loop

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
    jmp .read_loop

.command_ready:
    mov si, cx
    mov byte [bx + si], 0       ;null terminate the command so routines know where it ends

    call console_newline

    ; Exact command dispatch
    cmp byte [command_buf], 0
    je .shell_loop

    ; help
    mov si, command_buf
    mov di, cmd_help_str
    call str_eq
    cmp al, 1
    je .cmd_help

    ; csh
    mov si, command_buf
    mov di, cmd_csh_str
    call str_eq
    cmp al, 1
    je .cmd_csh

    ; Unknown command
    mov si, unknown_msg
    call console_puts
    call console_newline
    jmp .shell_loop

.cmd_help:
    mov si, help_msg
    call console_puts
    call console_newline
    jmp .shell_loop
.cmd_csh:
    call launch_shell
    jmp .shell_loop

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
    lodsb
    cmp al, 0
    je .done
    call console_putc
    jmp .loop
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
    lodsb
    cmp al, 0
    je .logo_done
    cmp al, '#'
    jne .logo_emit
    mov al, 0xDB
.logo_emit:
    call console_putc
    jmp .logo_loop
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
    cli
    mov word [SYSCALL_INT * 4], syscall_handler
    mov word [SYSCALL_INT * 4 + 2], 0
    sti
    ret

syscall_handler:
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    push ds
    push es

    cmp ah, SYS_PUTC
    je .sys_putc

    cmp ah, SYS_PUTS
    je .sys_puts

    cmp ah, SYS_NEWLINE
    je .sys_newline

    cmp ah, SYS_GETC
    je .sys_getc

    cmp ah, SYS_CLEAR
    je .sys_clear

    cmp ah, SYS_RUN
    je .sys_run

    cmp ah, SYS_READ_RAW
    je .sys_read_raw

    cmp ah, SYS_WRITE_RAW
    je .sys_write_raw

    mov ah, 0xFF
    jmp .done

.sys_putc:
    call console_putc
    xor ah, ah
    jmp .done

.sys_puts:
    call console_puts
    xor ah, ah
    jmp .done

.sys_newline:
    call console_newline
    xor ah, ah
    jmp .done

.sys_getc:
    call kbd_getc
    jmp .done

.sys_clear:
    call console_clear
    xor ah, ah
    jmp .done

.sys_run:
    call run_named_program
    jmp .done

.sys_read_raw:
    call disk_read_chs
    jc .sys_read_raw_fail
    xor ah, ah
    jmp .done

.sys_read_raw_fail:
    mov ah, 2
    jmp .done

.sys_write_raw:
    call disk_write_chs
    jc .sys_write_raw_fail
    xor ah, ah
    jmp .done

.sys_write_raw_fail:
    mov ah, 2
    jmp .done

.done:
    pop es
    pop ds
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    iret

; ----------------------------------
; Disk wrapper API (BIOS-backed)
; ----------------------------------
; disk_read_chs
; Inputs:
;   AL = sector count
;   CL = logical sector number (1-based)
;   ES:BX = destination buffer
; Uses:
;   DL = [kernel_boot_drive]
; Returns:
;   CF clear on success
;   CF set on error, AH = BIOS status
; Clobbers:
;   DL, SI
;
; Optional reliability:
;   one retry after INT 13h reset (AH=00h)
disk_read_chs:
    ; Save requested geometry/count so we can retry with the same inputs
    mov [dr_count], al
    mov [dr_lba], cl
    mov [dr_dest], bx

    mov byte [dr_retries], 1          ; one retry after first failure

.read_try:
    ; Restore inputs for this attempt
    mov cl, [dr_lba]
    call lba_to_chs
    mov al, [dr_count]
    mov bx, [dr_dest]
    mov dl, [kernel_boot_drive]

    mov ah, 0x02                      ; BIOS read sectors
    int 0x13
    jnc .ok                           ; CF=0 -> success

    ; Failure: AH has BIOS status code
    mov [dr_last_status], ah

    ; If no retry left, return failure with AH preserved
    cmp byte [dr_retries], 0
    je .fail

    ; Consume retry and reset disk system, then try again
    dec byte [dr_retries]
    mov ah, 0x00                      ; BIOS reset disk system
    mov dl, [kernel_boot_drive]
    int 0x13
    jmp .read_try

.ok:
    clc                               ; explicit success
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
    je .write_fail

    dec byte [dr_retries]
    mov ah, 0x00
    mov dl, [kernel_boot_drive]
    int 0x13
    jmp .write_try

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
    jne .no
    cmp al, 0
    je .yes
    inc si
    inc di
    jmp .eq_loop
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
    je .yes
    mov bl, [si]
    cmp bl, al
    jne .no
    inc si
    inc di
    jmp .sw_loop
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
    jne .bad_magic
    cmp byte [PROG_TABLE_ADDR + 1], 'F'
    jne .bad_magic
    cmp byte [PROG_TABLE_ADDR + 2], 'S'
    jne .bad_magic
    cmp byte [PROG_TABLE_ADDR + 3], '1'
    jne .bad_magic

    mov al, [PROG_TABLE_ADDR + 4]
    cmp al, PROG_TABLE_MAX_ENTRIES
    ja .bad_count
    mov [prog_table_count], al

    call validate_program_table_layout
    cmp ah, 0
    jne .bad_layout

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
    jmp .dbg_count_done
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
    je .v_bad

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
    jmp .v_loop

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
    jne .fs_unavailable

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
    je .found

    inc bl
    jmp .search_loop

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
    jne .unknown

    mov ax, 0
    mov es, ax
    mov bx, [di + 10]
    mov al, [di + 9]
    mov ch, 0
    mov cl, [di + 8]
    mov dh, 0
    call disk_read_chs
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
    db "Welcome to CircleOS v0.1.15!", 13, 10, 0

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



