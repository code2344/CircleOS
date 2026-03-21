; info.asm - Display system information
; Shows boot info and memory layout

bits 16
org 0xA000

SYSCALL_INT equ 0x80
SYS_PUTC equ 0x01
SYS_PUTS equ 0x02

start:
    mov ax, cs
    mov ds, ax
    mov es, ax

    mov si, msg_title
    call sys_puts

    mov si, msg_signature
    call sys_puts
    
    ; Read boot info signature from 0x0500
    mov ax, [0x0500]
    call print_hex16

    mov si, msg_version
    call sys_puts
    
    ; Read boot info version
    mov al, [0x0502]
    call print_hex8

    mov si, msg_drive
    call sys_puts
    
    ; Read boot info drive number
    mov al, [0x0503]
    call print_hex8

    mov si, msg_sectors
    call sys_puts
    
    ; Read boot info sector count
    mov ax, [0x0504]
    call print_hex16

    ; Show user-facing component versions.
    mov si, msg_os_version
    call sys_puts

    mov si, msg_kernel_version
    call sys_puts

    mov si, msg_csh_version
    call sys_puts

    mov si, msg_memory
    call sys_puts

    ret

print_hex16:
    push ax
    mov al, ah
    call print_hex8
    pop ax
    call print_hex8
    ret

print_hex8:
    push ax
    shr al, 4
    call print_hex_digit
    pop ax
    call print_hex_digit
    ret

print_hex_digit:
    and al, 0x0F
    cmp al, 0x0A
    jl .is_digit
    add al, 'A' - 0x0A
    jmp .print_it
.is_digit:
    add al, '0'
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
    db 13, 10, "OS version: v0.1.21", 0
msg_kernel_version:
    db 13, 10, "Kernel version: v0.1.21", 0
msg_csh_version:
    db 13, 10, "CSH version: v0.1.21", 0
msg_memory:
    db 13, 10, "Memory: 640KB available", 13, 10, 0
