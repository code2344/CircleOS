[BITS 16]
[ORG 0xA000]

SYSCALL_INT equ 0x80
SYS_PUTS equ 0x02
SYS_NEWLINE equ 0x03
SYS_PUTC equ 0x01


start:
    mov ax, 0
    mov ds, ax

    mov si, line1
    call sys_puts
    mov si, line2
    call sys_puts
    mov si, line3
    call sys_puts
    call sys_newline






    ret 

report_msg:
    db "CircleOS development report", 13, 10, 0
    