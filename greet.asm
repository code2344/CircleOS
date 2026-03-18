; greet.asm - Simple greeting program
; Displays a welcome message

bits 16
org 0xA000

SYSCALL_INT equ 0x80
SYS_PUTS equ 0x02

start:
    mov ax, cs
    mov ds, ax
    mov es, ax

    mov si, msg_welcome
    call sys_puts

    mov si, msg_feature
    call sys_puts

    ret

sys_puts:
    mov ah, SYS_PUTS
    int SYSCALL_INT
    ret

msg_welcome:
    db "=== Welcome to CircleOS ===", 0x0A, 0
msg_feature:
    db "This is a simple x86 real-mode operating system!", 0x0A, 0
