; cat.asm - Read and print text files from CFS1 table

[BITS 16]
[ORG 0xA000]

SYSCALL_INT equ 0x80
SYS_PUTC equ 0x01
SYS_PUTS equ 0x02
SYS_NEWLINE equ 0x03
SYS_GETC equ 0x04
SYS_READ_RAW equ 0x07
CTRL_C equ 0x03

PROG_TABLE_ADDR equ 0x0600
PROG_ENTRY_SIZE equ 16
PROG_NAME_LEN equ 8
ENTRY_TYPE_TEXT equ 2

start:
    mov ax, 0
    mov ds, ax
    mov es, ax

    mov si, msg_title
    call sys_puts

    mov si, msg_prompt
    call sys_puts
    call read_line

    ; Ctrl+C from prompt aborts cat and returns to csh.
    cmp byte [name_buf], CTRL_C
    je .cancelled

    cmp byte [name_buf], 0
    je .usage

    mov si, name_buf
    call find_text_entry
    cmp al, 1
    jne .not_found

    mov bx, file_buf
    mov al, [file_count]
    mov ch, 0
    mov cl, [file_sector]
    mov dh, 0
    mov ah, SYS_READ_RAW
    int SYSCALL_INT
    cmp ah, 0
    jne .read_fail

    mov si, file_buf
    call sys_puts
    call sys_newline
    ret

.cancelled:
    ret

.usage:
    mov si, msg_usage
    call sys_puts
    call sys_newline
    ret

.not_found:
    mov si, msg_not_found
    call sys_puts
    call sys_newline
    ret

.read_fail:
    mov si, msg_read_fail
    call sys_puts
    call sys_newline
    ret

; Read one command-line style input into name_buf
read_line:
    xor cx, cx
    mov bx, name_buf

.read_loop:
    call sys_getc

    ; Ctrl+C cancels filename entry.
    cmp al, CTRL_C
    je .cancel

    cmp al, 13
    je .done

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

.done:
    mov si, cx
    mov byte [bx + si], 0
    call sys_newline
    ret

; Input: DS:SI -> null-terminated filename
; Output: AL=1 found, AL=0 not found, file_sector/file_count set on success
find_text_entry:
    mov [name_ptr], si
    mov byte [entry_index], 0

    mov bx, PROG_TABLE_ADDR
    mov al, [es:bx + 4]
    mov [entry_count], al

.search_loop:
    mov al, [entry_index]
    cmp al, [entry_count]
    jae .no

    xor ax, ax
    mov al, [entry_index]
    shl ax, 4
    mov di, PROG_TABLE_ADDR + 16
    add di, ax

    mov si, [name_ptr]
    push di
    call str_eq_entry_name
    pop di
    cmp al, 1
    jne .next

    mov bx, di
    cmp byte [es:bx + 14], ENTRY_TYPE_TEXT
    jne .next

    mov al, [es:bx + 8]
    mov [file_sector], al
    mov al, [es:bx + 9]
    mov [file_count], al
    mov al, 1
    ret

.next:
    inc byte [entry_index]
    jmp .search_loop

.no:
    xor al, al
    ret

; Compare DS:SI null-terminated name with ES:DI fixed 8-byte table name
; Output: AL=1 equal, AL=0 not equal
str_eq_entry_name:
    mov cx, PROG_NAME_LEN

.cmp_loop:
    mov al, [si]
    mov bl, [es:di]
    cmp al, bl
    jne .no

    cmp al, 0
    je .yes

    inc si
    inc di
    dec cx
    jnz .cmp_loop

    cmp byte [si], 0
    je .yes

.no:
    xor al, al
    ret

.yes:
    mov al, 1
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
    db "cat - print text file", 13, 10, 0
msg_prompt:
    db "file> ", 0
msg_usage:
    db "usage: cat then enter <name>", 0
msg_not_found:
    db "file not found", 0
msg_read_fail:
    db "file read failed", 0

entry_count: db 0
entry_index: db 0
file_sector: db 0
file_count: db 0
name_ptr: dw 0

name_buf:
    times 32 db 0

file_buf:
    times 1024 db 0
