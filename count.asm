[BITS 16]
[ORG 0xA000]

SYSCALL_INT equ 0x80
SYS_PUTS    equ 0x02
SYS_NEWLINE equ 0x03
SYS_PUTC    equ 0x01

start:
    mov ax, 0
    mov ds, ax
    mov es, ax

    mov byte [frame_count], 0

    mov ax, 1
    call print_count
    ret

print_count:
    ; print AX
    push ax
    call print_u16_dec
    call sys_newline
    pop ax

    inc byte [frame_count]
    cmp byte [frame_count], 10
    jne .skip_sp

    mov byte [frame_count], 0
    mov [saved_sp], sp
    push ax
    mov ax, [saved_sp]
    call print_sp_hex
    call sys_newline
    pop ax

.skip_sp:

    ; recurse with AX + 1
    inc ax
    call print_count
    ret

sys_putc:
    mov ah, SYS_PUTC
    int SYSCALL_INT
    ret

sys_newline:
    mov ah, SYS_NEWLINE
    int SYSCALL_INT
    ret

print_sp_hex:
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

print_u16_dec:
    push ax
    push bx
    push cx
    push dx

    xor cx, cx
    mov bx, 10

.convert:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz .convert

.print_loop:
    pop dx
    add dl, '0'
    mov al, dl
    call sys_putc
    loop .print_loop

    pop dx
    pop cx
    pop bx
    pop ax
    ret

frame_count:
    db 0

saved_sp:
    dw 0