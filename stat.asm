; stat.asm - Display program statistics
; Shows program count and memory layout

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

    ; Get program table info
    mov di, 0x0600
    
    mov al, [di + 4]
    mov [prog_count], al

    mov si, msg_count
    call sys_puts
    
    mov al, [prog_count]
    call print_hex8

    mov si, msg_memory_layout
    call sys_puts

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
    db "=== Program Statistics ===", 0x0A, 0
msg_count:
    db "Total programs: ", 0
msg_memory_layout:
    db 0x0A, "Memory: Kernel=0x7E00, Shell=0x9000, User=0xA000", 0x0A, 0

prog_count: db 0
