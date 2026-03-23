; demo.asm
; Tiny runnable program loaded by kernel SYS_RUN
; CEX1 VERSION 1

[BITS 16]           ; 16-bit real mode assembly
[ORG 0xA000]        ; load address for user programs

SYSCALL_INT equ 0x80
SYS_PUTS equ 0x02
SYS_NEWLINE equ 0x03

start:
    mov ax, 0           ; zero AX for data segment setup
    mov ds, ax          ; point DS to segment 0 for message access

    mov si, demo_msg    ; point to message string
    mov ah, SYS_PUTS    ; select puts syscall
    int SYSCALL_INT     ; print the message

    mov ah, SYS_NEWLINE ; select newline syscall
    int SYSCALL_INT     ; add newline after message

    ret                 ; return to kernel

demo_msg:
    db "demo program executed",
    db "Hello from CSH", 0
