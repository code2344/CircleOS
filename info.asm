; info.asm - Display system information
; Shows boot info and memory layout

BITS 32
org 0xA000          ; user program load address

SYSCALL_INT equ 0x80
SYS_PUTC equ 0x01
SYS_PUTS equ 0x02

start:
    mov eax, 0x10
    mov ds, ax
    mov es, ax

    mov esi, msg_title
    call sys_puts

    mov esi, msg_signature
    call sys_puts

    ; Bootloader stores info struct at 0x0500; first 2 bytes are signature (CB)
    mov ax, word [0x0500]
    movzx eax, ax
    call print_hex16

    mov esi, msg_version
    call sys_puts

    ; Boot info version at offset +2
    mov al, [0x0502]
    call print_hex8

    mov esi, msg_drive
    call sys_puts

    ; BIOS drive number at offset +3
    mov al, [0x0503]
    call print_hex8

    mov esi, msg_sectors
    call sys_puts

    ; Kernel sector count at offset +4
    mov ax, word [0x0504]
    movzx eax, ax
    call print_hex16

    ; Show component version strings
    mov esi, msg_os_version
    call sys_puts

    mov esi, msg_kernel_version
    call sys_puts

    mov esi, msg_csh_version
    call sys_puts

    mov esi, msg_memory
    call sys_puts

    ret

print_hex16:            ; print AX as four hex digits
    push ax
    mov al, ah          ; print high byte first
    call print_hex8
    pop ax
    call print_hex8
    ret

print_hex8:             ; print AL as two hex digits
    push ax
    shr al, 4           ; shift upper nibble to lower position
    call print_hex_digit
    pop ax
    call print_hex_digit
    ret

print_hex_digit:        ; print low nibble of AL as hex ASCII
    and al, 0x0F        ; isolate low 4 bits
    cmp al, 0x0A        ; check if digit (0-9) or letter (A-F)
    jl .is_digit
    add al, 'A' - 0x0A  ; convert 10-15 to A-F
    jmp .print_it
.is_digit:
    add al, '0'         ; convert 0-9 to ASCII
.print_it:
    mov ah, SYS_PUTC
    int SYSCALL_INT
    ret

sys_puts:
    mov ah, SYS_PUTS
    int SYSCALL_INT
    ret

msg_title:
    db "=== System Information ===", 13, 10, 0
msg_signature:
    db "Boot signature: 0x", 0
msg_version:
    db 13, 10, "Boot version: 0x", 0
msg_drive:
    db 13, 10, "Boot drive: 0x", 0
msg_sectors:
    db 13, 10, "Kernel sectors: 0x", 0
msg_os_version:
    db 13, 10, "OS version: v0.1.22", 0
msg_kernel_version:
    db 13, 10, "Kernel version: v0.1.22", 0
msg_csh_version:
    db 13, 10, "CSH version: v0.1.22", 0
msg_memory:
    db 13, 10, "Memory: 640KB available", 13, 10, 0
