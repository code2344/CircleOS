; ls.asm - List files from writable inode filesystem
; CEX1 VERSION 2

bits 16             ; 16-bit real mode
org 0xA000          ; user program load address

SYSCALL_INT equ 0x80
SYS_PUTC equ 0x01
SYS_PUTS equ 0x02
SYS_FS_LIST equ 0x0B ; kernel filesystem list syscall

start:
    xor ax, ax
    mov ds, ax
    mov es, ax

    mov si, msg_header
    call sys_puts

    mov byte [entry_index], 0  ; start at index 0

.list_loop:
    mov si, list_path
    mov al, [entry_index]      ; get current file ordinal
    mov bx, name_buf           ; output buffer for filename
    mov ah, SYS_FS_LIST        ; issue filesystem list syscall
    int SYSCALL_INT            ; CX returns file size, DL returns type

    cmp ah, 0       ; success?
    je .print_one
    cmp ah, 1       ; end of listing?
    je .done

    ; Syscall failed
    mov si, msg_list_fail
    call sys_puts
    ret

.print_one:
    mov si, name_buf
    call sys_puts
    mov si, msg_size
    call sys_puts
    mov ax, cx      ; get file size from syscall
    call print_dec16  ; print size in decimal
    mov si, msg_bytes
    call sys_puts

    inc byte [entry_index]  ; next file
    jmp .list_loop

.done:
    ret

; print_dec16: print AX as unsigned decimal
print_dec16:
    cmp ax, 0           ; handle zero case specially
    jne .conv
    mov al, '0'
    call sys_putc_char
    ret

.conv:
    mov bx, 10
    xor cx, cx          ; digit counter
.push_digits:
    xor dx, dx
    div bx              ; AL = quotient, DL = remainder (digit)
    push dx             ; save digit
    inc cx              ; count digits
    cmp ax, 0           ; more digits?
    jne .push_digits

.emit_digits:           ; print digits in reverse order (from stack)
    pop dx
    mov al, dl
    add al, '0'         ; convert to ASCII
    call sys_putc_char
    loop .emit_digits
    ret

; Syscall wrappers
sys_putc_char:          ; put character in AL
    mov ah, SYS_PUTC
    int SYSCALL_INT
    ret

sys_puts:               ; put string at DS:SI
    mov ah, SYS_PUTS
    int SYSCALL_INT
    ret

list_path:
    db 0                ; empty path => current working directory (respects cd)

msg_header:
    db "Files:", 13, 10, 0
msg_size:
    db "  size:", 0
msg_bytes:
    db " bytes", 13, 10, 0
msg_list_fail:
    db "filesystem list failed", 13, 10, 0

entry_index:
    db 0                ; current file ordinal
name_buf:
    times 11 db 0       ; returned filename buffer
