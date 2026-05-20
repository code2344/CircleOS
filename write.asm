; write.asm - Append one line to a writable inode filesystem file
; CEX1 VERSION 2

[BITS 32]           ; 32-bit protected mode
[ORG 0xA000]        ; user program load address

SYSCALL_INT equ 0x80
SYS_PUTC equ 0x01
SYS_PUTS equ 0x02
SYS_NEWLINE equ 0x03
SYS_GETC equ 0x04
SYS_FS_READ equ 0x09
SYS_FS_WRITE equ 0x0A
CTRL_C equ 0x03
FILE_BUF_SIZE equ 1024

start:
    mov ax, 0x10
    mov ds, ax
    mov es, ax

    ; Display title and prompt for filename
    mov si, msg_title
    call sys_puts

    mov si, msg_file_prompt
    call sys_puts
    call read_name_line         ; read target filename from stdin

    cmp byte [name_buf], CTRL_C ; user cancelled?
    je .cancelled
    cmp byte [name_buf], 0      ; no filename entered?
    je .usage

    ; Try to read existing file; not found (AH=1) means start empty
    mov si, name_buf
    mov bx, file_buf
    mov ah, SYS_FS_READ
    int SYSCALL_INT

    cmp ah, 0       ; file exists and was read?
    je .have_existing
    cmp ah, 1       ; file not found (ok, start empty)?
    je .new_file
    jmp .read_fail  ; other error

.have_existing:
    mov [append_ofs], cx  ; CX has bytes read from file
    cmp word [append_ofs], FILE_BUF_SIZE - 3
    jae .full            ; no room to append
    jmp .prompt_text

.new_file:
    mov word [append_ofs], 0  ; start with empty file

.prompt_text:
    mov si, msg_text_prompt
    call sys_puts
    call read_text_line  ; read new line from stdin

    cmp byte [line_buf], CTRL_C  ; user cancelled?
    je .cancelled
    cmp byte [line_buf], 0       ; empty line?
    je .empty

    ; Build output: existing file + new line + CRLF
    mov di, file_buf
    add di, [append_ofs] ; position after existing content
    mov si, line_buf
.append_loop:
    mov al, [si]
    cmp al, 0            ; reached end of new line?
    je .append_crlf

    cmp di, file_buf + FILE_BUF_SIZE - 3  ; room for char + CRLF?
    jae .full

    mov [di], al
    inc di
    inc si
    jmp .append_loop

.append_crlf:
    cmp di, file_buf + FILE_BUF_SIZE - 3
    jae .full
    mov byte [di], 13   ; CR
    inc di
    mov byte [di], 10   ; LF
    inc di
    mov byte [di], 0    ; null-terminate buffer
    mov ax, di
    sub ax, file_buf
    mov [append_end_ofs], ax  ; total bytes to write

    ; Write file back to filesystem
    mov si, name_buf
    mov bx, file_buf
    mov cx, [append_end_ofs]
    mov ah, SYS_FS_WRITE
    int SYSCALL_INT
    cmp ah, 0           ; write successful?
    jne .write_fail

    mov si, msg_ok
    call sys_puts
    call sys_newline
    ret

.cancelled:
    ret                 ; exit without saving

.empty:
    mov si, msg_empty
    call sys_puts
    call sys_newline
    ret

.full:
    mov si, msg_full
    call sys_puts
    call sys_newline
    ret

.usage:
    mov si, msg_usage
    call sys_puts
    call sys_newline
    ret

.read_fail:
    mov si, msg_read_fail
    call sys_puts
    call sys_newline
    ret

.write_fail:
    mov si, msg_write_fail
    call sys_puts
    call sys_newline
    ret

read_name_line:         ; read filename with backspace/ctrl-c support
    xor cx, cx
    mov bx, name_buf
.read_loop:
    call sys_getc

    cmp al, CTRL_C      ; cancel entry
    je .cancel

    cmp al, 13          ; enter = done
    je .done

    cmp al, 8           ; backspace
    je .backspace

    call sys_putc       ; echo character
    cmp cx, 31          ; prevent overflow
    jae .read_loop

    mov si, cx
    mov [bx + si], al
    inc cx
    jmp .read_loop

.backspace:
    cmp cx, 0
    je .read_loop

    mov al, 8
    call sys_putc       ; backspace
    mov al, ' '
    call sys_putc       ; erase
    mov al, 8
    call sys_putc       ; move cursor back

    dec cx
    mov si, cx
    mov byte [bx + si], 0
    jmp .read_loop

.cancel:
    mov byte [name_buf], CTRL_C
    call sys_newline
    ret

.done:
    mov si, cx
    mov byte [bx + si], 0  ; null-terminate input
    call sys_newline
    ret

read_text_line:         ; read text line with backspace/ctrl-c support
    xor cx, cx
    mov bx, line_buf
.read_loop:
    call sys_getc

    cmp al, CTRL_C      ; cancel entry
    je .cancel

    cmp al, 13          ; enter = done
    je .done

    cmp al, 8           ; backspace
    je .backspace

    call sys_putc       ; echo character
    cmp cx, 79          ; prevent overflow
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
    mov byte [line_buf], CTRL_C
    call sys_newline
    ret

.done:
    mov si, cx
    mov byte [bx + si], 0  ; null-terminate input
    call sys_newline
    ret

sys_putc:               ; syscall: put character
    mov ah, SYS_PUTC
    int SYSCALL_INT
    ret

sys_puts:               ; syscall: put string
    mov ah, SYS_PUTS
    int SYSCALL_INT
    ret

sys_newline:            ; syscall: newline
    mov ah, SYS_NEWLINE
    int SYSCALL_INT
    ret

sys_getc:               ; syscall: get character
    mov ah, SYS_GETC
    int SYSCALL_INT
    ret

msg_title:
    db "write - append one line to file", 13, 10, 0
msg_file_prompt:
    db "file> ", 0
msg_text_prompt:
    db "text> ", 0
msg_usage:
    db "usage: enter file name then text", 0
msg_ok:
    db "append ok", 0
msg_empty:
    db "nothing written", 0
msg_full:
    db "file full", 0
msg_read_fail:
    db "read failed", 0
msg_write_fail:
    db "write failed", 0

append_ofs:
    dw 0                   ; offset where to append new text
append_end_ofs:
    dw 0                   ; final size of file after append

name_buf:
    times 32 db 0          ; filename input buffer

line_buf:
    times 80 db 0          ; text line input buffer

file_buf:
    times FILE_BUF_SIZE db 0  ; file content buffer
