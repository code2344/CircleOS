; ls.asm - List files from writable inode filesystem
; CEX1 VERSION 2

BITS 32
org 0xA000          ; user program load address

SYSCALL_INT equ 0x80
SYS_PUTC equ 0x01
SYS_PUTS equ 0x02
SYS_FS_LIST equ 0x0B ; kernel filesystem list syscall
INFS_TYPE_DIR equ 2

start:
    ; Direct VGA start marker to prove program entry in protected mode
    mov dword [0x000B8000], 0x074C0A00

    mov eax, 0x10
    mov ds, ax
    mov es, ax

    mov esi, msg_trace_start
    call sys_puts

    mov esi, msg_header
    call sys_puts

    mov byte [entry_index], 0  ; start at index 0

.list_loop:
    mov esi, msg_trace_before
    call sys_puts

    mov esi, list_path
    mov al, [entry_index]      ; get current file ordinal
    mov ebx, name_buf          ; output buffer for filename
    mov ah, SYS_FS_LIST        ; issue filesystem list syscall
    int SYSCALL_INT            ; CX returns file size, DL returns type (file/dir) on success, AH=1 means end of listing, AH=0 means success, other AH values indicate errors

    mov esi, msg_trace_after
    call sys_puts

    cmp ah, 0       ; success?
    je .print_one
    cmp ah, 1       ; end of listing?
    je .done

    ; Syscall failed
    mov si, msg_list_fail
    call sys_puts
    ret

.print_one:
    mov [entry_size], cx      ; preserve size returned by syscall
    mov [entry_type], dl      ; preserve inode type returned by syscall

    mov esi, msg_item_prefix
    call sys_puts

    mov al, [name_buf]        ; guard against empty/corrupt names
    cmp al, 32
    jb .show_unnamed
    mov esi, name_buf
    call sys_puts
    jmp .show_type

.show_unnamed:
    mov esi, msg_unnamed
    call sys_puts

.show_type:
    mov esi, msg_sep
    call sys_puts

    cmp byte [entry_type], INFS_TYPE_DIR
    je .print_dir
    mov esi, msg_type_file
    call sys_puts
    jmp .print_size

.print_dir:
    mov esi, msg_type_dir
    call sys_puts

.print_size:
    mov esi, msg_sep
    call sys_puts
    mov eax, [entry_size]
    call print_dec16          ; print size in decimal
    mov esi, msg_bytes
    call sys_puts

    inc byte [entry_index]  ; next file
    jmp .list_loop

.done:
    ret

; print_dec16: print AX as unsigned decimal
print_dec16:
    cmp eax, 0           ; handle zero case specially
    jne .conv
    mov al, '0'
    call sys_putc_char
    ret

.conv:
    mov ebx, 10
    xor ecx, ecx          ; digit counter
.push_digits:
    xor edx, edx
    div ebx              ; eax = quotient, edx = remainder (digit)
    push edx             ; save digit
    inc ecx              ; count digits
    cmp eax, 0           ; more digits?
    jne .push_digits

.emit_digits:           ; print digits in reverse order (from stack)
    pop edx
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

sys_puts:               ; put string at ESI
    mov ah, SYS_PUTS
    int SYSCALL_INT
    ret

list_path:
    db 0                ; empty path => current working directory (respects cd)

msg_header:
    db "Files:", 13, 10, 0
msg_item_prefix:
    db "- ", 0
msg_sep:
    db "  ", 0
msg_type_file:
    db "file", 0
msg_type_dir:
    db "dir ", 0
msg_unnamed:
    db "<unnamed>", 0
msg_bytes:
    db " bytes", 13, 10, 0
msg_list_fail:
    db "filesystem list failed", 13, 10, 0

msg_trace_start:
    db "[ls] start", 13, 10, 0

msg_trace_before:
    db "[ls] before sys_fs_list", 13, 10, 0

msg_trace_after:
    db "[ls] after sys_fs_list", 13, 10, 0

entry_index:
    db 0                ; current file ordinal
entry_type:
    db 0                ; returned inode type (file/dir)
entry_size:
    dw 0                ; returned byte size for current entry
name_buf:
    times 11 db 0       ; returned filename buffer
