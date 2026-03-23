; greet.asm - Simple greeting program
; Displays a welcome message
; CEX1 VERSION 1

bits 16             ; 16-bit real mode
org 0xA000          ; user program load address

SYSCALL_INT equ 0x80
SYS_PUTS equ 0x02

start:
    mov ax, cs         ; load code segment to access message strings in CS
    mov ds, ax         ; set data segment to CS
    mov es, ax         ; set extra segment to CS

    mov si, msg_welcome ; point to welcome message
    call sys_puts

    mov si, msg_feature ; point to feature description
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
