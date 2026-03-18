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


start:
    mov ax, 0           ; clear register AX temporarily to initialise segment registers
    mov ds, ax          ; clear and initialise data segment
    mov es, ax          ; clear and initialise extra segment

    cmp byte [BOOT_SIG0_OFF], 'C'
    jne .boot_info_bad
    cmp byte [BOOT_SIG1_OFF], 'B'
    jne .boot_info_bad

    mov al, [BOOT_DRIVE_OFF]
    mov [kernel_boot_drive], al
    call install_syscall_vector

    mov si, welcome_msg    ; move boot message to source
    call console_puts   ; calls print string (prints SI)
    jmp .shell_loop


.boot_info_bad:
    mov si, boot_info_bad_msg   ; boot info bad handler, alerts if boot info bad
    call console_puts
    jmp halt

; begin main shell loop
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

    mov ah, 0x0E                ; set for printing
    mov al, 13                  ; 13 is CR (or new line)
    int 0x10                    ; print character to screen
    mov al, 10
    int 0x10

    ; simple command parser, just match by first character
    mov si, command_buf
    lodsb                       ; puts si into al and increments si

    cmp al, 'h'                 ; help?
    je .cmd_help

    cmp al, 'e'                 ; echo?
    je .cmd_echo

    cmp al, 'c'                 ; clear
    je .cmd_clear

    cmp al, 0                   ; empty command?
    je .shell_loop

    mov si, unknown_msg         ; unknown command message
    call console_puts
    jmp .shell_loop

.cmd_help:
    mov si, help_msg
    call console_puts
    jmp .shell_loop

.cmd_echo:
    ; assumes command starts with "echo ", skips as prefix
    mov si, command_buf
    inc si                      ; skip 'e'
    lodsb                       ; consume 'c'
    lodsb                       ; consume 'h'
    lodsb                       ; consume 'o'
    lodsb                       ; consume ' ' or 0 if just echo without space

    cmp al, 0
    je .shell_loop              ; if al is 0 then there was nothing after 'echo' so no command

    dec si
    call console_puts

    ; newline after echoed text
    mov ah, 0x0E
    mov al, 13                  ; CR
    int 0x10
    mov al, 10                  ; line feed
    int 0x10

    jmp .shell_loop

.cmd_clear:
    ;clear using bios scroll up function
    ; int 10 ah 06 is scroll
    ; al is lines to scroll 0 is clear Available
    ; bh is attribute of blank lines
    ; cx is upper left
    ; dx is lower right
    mov ah, 0x06
    mov al, 0
    mov bh, 0x07
    mov cx, 0
    mov dx, 0x184F
    int 0x10                    ; bios video services

    ; put cursor at top left through video int with ah=06h
    mov ah, 0x02
    mov bh, 0
    mov dx, 0
    int 0x10

    jmp .shell_loop

; print_string:
;    lodsb               ; Load byte from [ds:si] into al, increment si, ds is data segment default for reading data
;    cmp al, 0           ; is the byte the null terminator?
;    je .done            ; if it's yes then the program's done
;
;    mov ah, 0x0E        ; BIOS teletype output
;    int 0x10            ; Call bios video interrupt
;    jmp print_string    ; loop to the next character
    
.done:
    ret

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

; wait for keypress and return it
; output al = ascii, ah = scan code
; clobbers ah and al
kbd_getc:
    mov ah, 0x00
    int 0x16
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
;   CH = cylinder
;   CL = sector (1-based)
;   DH = head
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
    mov [dr_cyl], ch
    mov [dr_sect], cl
    mov [dr_head], dh
    mov [dr_dest], bx

    mov byte [dr_retries], 1          ; one retry after first failure

.read_try:
    ; Restore inputs for this attempt
    mov al, [dr_count]
    mov ch, [dr_cyl]
    mov cl, [dr_sect]
    mov dh, [dr_head]
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

; ----------------------------------
; disk_read_chs scratch state (kernel globals)
; ----------------------------------
dr_count:
    db 0
dr_cyl:
    db 0
dr_sect:
    db 0
dr_head:
    db 0
dr_dest:
    dw 0
dr_retries:
    db 0
dr_last_status:
    db 0


; --------------------------------DATA SECTION------------------------------------
welcome_msg:
    db "Welcome to CircleOS v0.1.0!", 13, 10, 0

help_msg:
    db "Available commands:", 13, 10
    db "  help   - show this message", 13, 10
    db "  echo   - echo text back", 13, 10
    db "  clear  - clear the screen", 13, 10, 0

prompt:
    db "CircleOS Kernel > ", 0

unknown_msg:
    db "Unknown command. Type 'help' for commands.", 13, 10, 0

boot_info_bad_msg:
    db "BOOT INFO INVALID", 13, 10, 0


command_buf:
    times 32 db 0   ; input storage.



