; write.asm - Append one line to a fixed text-file region (todo)

[BITS 16]
[ORG 0xA000]

SYSCALL_INT equ 0x80
SYS_PUTC equ 0x01
SYS_PUTS equ 0x02
SYS_NEWLINE equ 0x03
SYS_GETC equ 0x04
SYS_READ_RAW equ 0x07
SYS_WRITE_RAW equ 0x08

%ifndef LOG_SECTOR
LOG_SECTOR equ 15
%endif

%ifndef LOG_SECTORS
LOG_SECTORS equ 1
%endif

LOG_BUF_SIZE equ 512

start:
    mov ax, 0
    mov ds, ax
    mov es, ax

    mov si, msg_title
    call sys_puts

    ; Load existing log text from disk
    mov bx, log_buf
    mov al, LOG_SECTORS
    mov ch, 0
    mov cl, LOG_SECTOR
    mov dh, 0
    mov ah, SYS_READ_RAW
    int SYSCALL_INT
    cmp ah, 0
    jne .read_fail

    ; Find end (first 0 byte) in log buffer
    mov bx, log_buf
    xor cx, cx
.find_end:
    cmp cx, LOG_BUF_SIZE
    jae .full
    cmp byte [bx], 0
    je .have_end
    inc bx
    inc cx
    jmp .find_end

.have_end:
    mov [append_ptr], bx

    mov si, msg_prompt
    call sys_puts
    call read_line

    cmp byte [line_buf], 0
    je .empty

    ; Append line to log buffer
    mov di, [append_ptr]
    mov si, line_buf
.append_loop:
    mov al, [si]
    cmp al, 0
    je .append_crlf

    cmp di, log_buf + LOG_BUF_SIZE - 3
    jae .full

    mov [di], al
    inc di
    inc si
    jmp .append_loop

.append_crlf:
    cmp di, log_buf + LOG_BUF_SIZE - 3
    jae .full
    mov byte [di], 13
    inc di
    mov byte [di], 10
    inc di
    mov byte [di], 0

    ; Write whole sector back
    mov bx, log_buf
    mov al, LOG_SECTORS
    mov ch, 0
    mov cl, LOG_SECTOR
    mov dh, 0
    mov ah, SYS_WRITE_RAW
    int SYSCALL_INT
    cmp ah, 0
    jne .write_fail

    mov si, msg_ok
    call sys_puts
    call sys_newline
    ret

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

read_line:
    xor cx, cx
    mov bx, line_buf
.read_loop:
    call sys_getc

    cmp al, 13
    je .done

    cmp al, 8
    je .backspace

    call sys_putc
    cmp cx, 79
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

.done:
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
    db "write - append one line to todo", 13, 10, 0
msg_prompt:
    db "text> ", 0
msg_ok:
    db "append ok", 0
msg_empty:
    db "nothing written", 0
msg_full:
    db "todo file full", 0
msg_read_fail:
    db "read failed", 0
msg_write_fail:
    db "write failed", 0

append_ptr:
    dw 0

line_buf:
    times 80 db 0

log_buf:
    times LOG_BUF_SIZE db 0
