; ls.asm - Verbose directory listing
; Shows name, sector, count, load address, and type for each table entry

bits 16
org 0xA000

SYSCALL_INT equ 0x80
SYS_PUTC equ 0x01
SYS_PUTS equ 0x02

start:
    mov ax, cs
    mov ds, ax
    xor ax, ax
    mov es, ax

    ; Print header
    mov si, msg_header
    call sys_puts

    ; Program table is at kernel-known address 0x0600
    ; Keep loop state in memory because syscalls may clobber registers.
    mov byte [entry_index], 0
    mov al, [es:0x0604]
    mov [entry_count], al

.list_loop:
    mov al, [entry_index]
    cmp al, [entry_count]
    jae .done

    ; Calculate entry offset: base(0x0600) + 16 + (index * 16)
    xor ax, ax
    mov al, [entry_index]
    shl ax, 4
    mov bx, 0x0600
    add bx, 16          ; skip header
    add bx, ax          ; add index offset

    mov [entry_ptr], bx

    ; name
    call print_name_8bytes

    ; sector
    mov si, msg_sector
    call sys_puts
    mov bx, [entry_ptr]
    mov al, [es:bx + 8]
    call print_hex8

    ; count (size in sectors)
    mov si, msg_count
    call sys_puts
    mov bx, [entry_ptr]
    mov al, [es:bx + 9]
    call print_hex8

    ; load address
    mov si, msg_load
    call sys_puts
    mov bx, [entry_ptr]
    mov ax, [es:bx + 10]
    call print_hex16

    ; entry type
    mov si, msg_type
    call sys_puts
    mov bx, [entry_ptr]
    mov al, [es:bx + 14]
    cmp al, 1
    je .type_prog
    cmp al, 2
    je .type_text
    mov al, '?'
    jmp .type_out
.type_prog:
    mov al, 'P'
    jmp .type_out
.type_text:
    mov al, 'T'
.type_out:
    call sys_putc_char

    mov si, msg_newline
    call sys_puts

    inc byte [entry_index]
    jmp .list_loop

.done:
    ret

; Print exactly 8 bytes or until first null
print_name_8bytes:
    xor dx, dx
.name_loop:
    cmp dx, 8
    jae .name_done

    mov al, [es:bx]
    cmp al, 0
    je .name_done
    call sys_putc_char

    inc bx
    inc dx
    jmp .name_loop
.name_done:
    ret

print_hex16:
    push ax
    mov al, ah
    call print_hex8
    pop ax
    call print_hex8
    ret

print_hex8:
    push ax
    mov bl, al
    shr al, 4
    call print_hex_digit
    mov al, bl
    and al, 0x0F
    call print_hex_digit
    pop ax
    ret

print_hex_digit:
    and al, 0x0F
    cmp al, 10
    jl .digit
    add al, 'A' - 10
    jmp .emit
.digit:
    add al, '0'
.emit:
    call sys_putc_char
    ret

; Syscall: putc
sys_putc_char:
    mov ah, SYS_PUTC
    int SYSCALL_INT
    ret

; Syscall: puts
sys_puts:
    mov ah, SYS_PUTS
    int SYSCALL_INT
    ret

msg_header:
    db "Directory (verbose):", 13, 10, 0
msg_sector:
    db " sec:", 0
msg_count:
    db " cnt:", 0
msg_load:
    db " load:0x", 0
msg_type:
    db " type:", 0
msg_newline:
    db 13, 10, 0

entry_count:
    db 0
entry_index:
    db 0
entry_ptr:
    dw 0
