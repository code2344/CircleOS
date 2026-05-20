; cat.asm - print a text file from the inode filesystem
; CEX1 VERSION 2

BITS 32
org 0xA000          ; user program load address

SYSCALL_INT equ 0x80
SYS_PUTC equ 0x01
SYS_PUTS equ 0x02
SYS_NEWLINE equ 0x03
SYS_GETC equ 0x04
SYS_FS_READ equ 0x09
CTRL_C equ 0x03
FILE_BUF_SIZE equ 1024

start:
    mov ax, 0x10
    mov ds, ax
    mov es, ax

    mov esi, msg_title
    call sys_puts

    mov esi, msg_prompt
    call sys_puts
    call read_name_line

    cmp byte [name_buf], CTRL_C
    je .cancelled
    cmp byte [name_buf], 0
    je .usage

    mov si, name_buf
    mov bx, file_buf
    mov ah, SYS_FS_READ
    int SYSCALL_INT

    cmp ah, 0
    je .print_file
    cmp ah, 1
    je .not_found
    jmp .read_fail

.print_file:
    mov [file_len], cx
    mov esi, msg_ok
    call sys_puts

    mov esi, file_buf
    movzx ecx, word [file_len]
    cmp ecx, 0
    je .done

.print_loop:
    mov al, [esi]
    call sys_putc
    inc esi
    loop .print_loop

    call sys_newline
    jmp .done

.not_found:
    mov esi, msg_not_found
    call sys_puts
    call sys_newline
    jmp .done

.usage:
    mov esi, msg_usage
    call sys_puts
    call sys_newline
    jmp .done

.read_fail:
    mov esi, msg_read_fail
    call sys_puts
    call sys_newline
    jmp .done

.cancelled:
.done:
    ret

read_name_line:
    xor cx, cx
    mov bx, name_buf
.read_loop:
    call sys_getc

    cmp al, CTRL_C
    je .cancel

    cmp al, 13
    je .finish

    cmp al, 8
    je .backspace

    call sys_putc
    cmp cx, 31
    jae .read_loop

    mov si, cx
    mov [bx + si], al
    inc cx
    jmp .read_loop

.backspace:
    cmp cx, 0
    je .read_loop

    mov al, 8
    call sys_putc
    mov al, ' '
    call sys_putc
    mov al, 8
    call sys_putc

    dec cx
    mov si, cx
    mov byte [bx + si], 0
    jmp .read_loop

.cancel:
    mov byte [name_buf], CTRL_C
    call sys_newline
    ret

.finish:
    mov si, cx
    mov byte [bx + si], 0
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

sys_getc:
    mov ah, SYS_GETC
    int SYSCALL_INT
    ret

msg_title:
    db "cat - print a file", 13, 10, 0
msg_prompt:
    db "file> ", 0
msg_ok:
    db "--- file contents ---", 13, 10, 0
msg_usage:
    db "usage: enter a filename", 0
msg_not_found:
    db "file not found", 0
msg_read_fail:
    db "read failed", 0

file_len:
    dw 0
name_buf:
    times 32 db 0
file_buf:
    times FILE_BUF_SIZE db 0
