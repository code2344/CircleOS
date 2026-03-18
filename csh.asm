; csh.asm
; CIRCLE SHELL

[BITS 16]
[ORG 0x9000]

SYSCALL_INT equ 0x80
SYS_PUTS equ 0x02
SYS_NEWLINE equ 0x03

start:
    mov ax, 0
    mov ds, ax

    mov si, shell_msg
    mov ah, SYS_PUTS
    int SYSCALL_INT

    mov ah, SYS_NEWLINE
    int SYSCALL_INT

.hang:
    hlt
    jmp .hang

shell_msg:
    db "Circle Shell via syscall layer", 0