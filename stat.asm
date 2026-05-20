; stat.asm - Display program statistics
; Shows program count and memory layout
; CEX1 VERSION 1

BITS 32
org 0xA000          ; user program load address

SYSCALL_INT equ 0x80
SYS_PUTC equ 0x01
SYS_PUTS equ 0x02

start:
    mov eax, 0x10
    mov ds, ax
    mov es, ax

    mov esi, msg_title
    call sys_puts

    ; Read program count from kernel program table at 0x0600
    mov al, byte [0x0600 + 4]   ; program count
    mov [prog_count], al

    mov esi, msg_count
    call sys_puts

    mov al, [prog_count]
    call print_hex8

    mov esi, msg_memory_layout
    call sys_puts

    ret                 ; return to kernel

print_hex8:             ; print AL as two hex digits
    push eax
    mov ah, al
    shr al, 4           ; shift upper nibble to lower position
    call print_hex_digit
    pop eax
    call print_hex_digit
    ret

print_hex_digit:        ; print low nibble of AL as hex
    and al, 0x0F        ; isolate low nibble
    cmp al, 0x0A        ; check if 0-9 or A-F
    jl .is_digit        ; branch if 0-9
    add al, 'A' - 0x0A  ; convert 10-15 to A-F
    jmp .print_it
.is_digit:
    add al, '0'         ; convert 0-9 to ASCII
.print_it:
    mov ah, SYS_PUTC
    int SYSCALL_INT
    ret

sys_puts:
    mov ah, SYS_PUTS
    int SYSCALL_INT
    ret

msg_title:
    db "=== Program Statistics ===", 13, 10, 0
msg_count:
    db "Total programs: ", 0
msg_memory_layout:
    db 13, 10, "Memory: Kernel=0x7E00, Shell=0x9000, User=0xA000", 13, 10, 0

prog_count: db 0
