; greet.asm - Simple greeting program
; Displays a welcome message

[BITS 32]
org 0xA000          ; user program load address

SYSCALL_INT equ 0x80
SYS_PUTS equ 0x02

start:
    mov ax, 0x10
    mov ds, ax
    mov es, ax

    mov esi, msg_welcome
    call sys_puts

    mov esi, msg_feature
    call sys_puts

    ret                 ; return to kernel

sys_puts:
    mov ah, SYS_PUTS
    int SYSCALL_INT
    ret

msg_welcome:
    db "=== Welcome to CircleOS ===", 13, 10, 0
msg_feature:
    db "This is a simple x86 real-mode operating system!", 13, 10, 0
