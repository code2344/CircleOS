[BITS 16]
[ORG 0xA000]

SYSCALL_INT equ 0x80
SYS_PUTS equ 0x02
SYS_NEWLINE equ 0x03
SYS_PUTC equ 0x01

start:
    mov ax, 0
    mov ds, ax
    mov es, ax
    
    mov si, msg_time
    call sys_puts

    mov ah, 0x02
    int 0x1A

    mov al, ch
    call print_bcd_byte
    mov al, ':'
    call sys_putc
    mov al, cl
    call print_bcd_byte
    mov al, ':'
    call sys_putc
    mov al, dh
    call print_bcd_byte

    call sys_newline
    mov si, msg_date
    call sys_puts

    mov ah, 0x04
    int 0x1A

    mov ax, cx
    call print_u16_dec
    mov al, '-'
    call sys_putc
    mov al, dh
    call print_bcd_byte
    mov al, '-'
    call sys_putc
    mov al, dl
    call print_bcd_byte

    call sys_newline
    ret

sys_putc:
    mov ah, SYS_PUTC
    int SYSCALL_INT
    ret

sys_puts:
    mov ah, SYS_PUTS
    int SYSCALL_INT
    ret

sys_newline:
    mov ah, SYS_NEWLINE
    int SYSCALL_INT
    ret

print_bcd_byte:
    push ax
    mov ah, al
    shr al, 4
    and al, 0x0F
    add al, '0'
    call sys_putc
    mov al, ah
    and al, 0x0F
    add al, '0'
    call sys_putc
    pop ax
    ret

print_u16_dec:
    push ax
    push bx
    push cx
    push dx

    mov bx, 10
    xor cx, cx

.div_loop:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz .div_loop

.print_loop:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

msg_time:
    db 'Current time: ', 0
msg_date:
    db 'Current date: ', 0

