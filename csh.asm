; csh.asm
; CIRCLE SHELL

[BITS 16]
[ORG 0x9000]

SYSCALL_INT equ 0x80
SYS_PUTC equ 0x01
SYS_PUTS equ 0x02
SYS_NEWLINE equ 0x03
SYS_GETC equ 0x04
SYS_CLEAR equ 0x05
SYS_RUN equ 0x06

start:
    mov ax, 0
    mov ds, ax

    mov si, shell_banner
    call sys_puts
    call sys_newline

.shell_loop:
    mov si, shell_prompt
    call sys_puts

    xor cx, cx
    mov bx, cmd_buf

.read_loop:
    call sys_getc

    cmp al, 13
    je .command_ready

    cmp al, 8
    je .backspace

    ; Echo typed character
    call sys_putc

    ; Store typed character if there is room
    cmp cx, 31
    jge .read_loop
    mov si, cx
    mov byte [bx + si], al
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
    jmp .read_loop

.command_ready:
    mov si, cx
    mov byte [bx + si], 0
    call sys_newline

    cmp byte [cmd_buf], 0
    je .shell_loop

    ; help
    mov si, cmd_buf
    mov di, cmd_help
    call str_eq
    cmp al, 1
    je .cmd_help

    ; clear
    mov si, cmd_buf
    mov di, cmd_clear
    call str_eq
    cmp al, 1
    je .cmd_clear

    ; echo <text>
    mov si, cmd_buf
    mov di, cmd_echo_prefix
    call str_startswith
    cmp al, 1
    je .cmd_echo

    ; plain "echo" prints just a newline
    mov si, cmd_buf
    mov di, cmd_echo
    call str_eq
    cmp al, 1
    je .cmd_echo_empty

    ; exit
    mov si, cmd_buf
    mov di, cmd_exit
    call str_eq
    cmp al, 1
    je .cmd_exit

    ; run <name>
    mov si, cmd_buf
    mov di, cmd_run_prefix
    call str_startswith
    cmp al, 1
    je .cmd_run

    ; plain "run" prints usage
    mov si, cmd_buf
    mov di, cmd_run
    call str_eq
    cmp al, 1
    je .cmd_run_usage

    ; unknown
    mov si, msg_unknown
    call sys_puts
    call sys_newline
    jmp .shell_loop

.cmd_help:
    mov si, msg_help
    call sys_puts
    call sys_newline
    jmp .shell_loop

.cmd_clear:
    call sys_clear
    jmp .shell_loop

.cmd_echo:
    ; "echo " is 5 chars, print the remainder
    mov si, cmd_buf
    add si, 5
    call sys_puts
    call sys_newline
    jmp .shell_loop

.cmd_echo_empty:
    call sys_newline
    jmp .shell_loop

.cmd_exit:
    mov si, msg_exit
    call sys_puts
    call sys_newline
    ret

.cmd_run:
    mov si, cmd_buf
    add si, 4                      ; skip "run "
    cmp byte [si], 0
    je .cmd_run_usage

    call sys_run
    cmp ah, 0
    je .shell_loop
    cmp ah, 1
    je .cmd_run_not_found
    cmp ah, 2
    je .cmd_run_load_fail
    cmp ah, 3
    je .cmd_run_fs_fail

    mov si, msg_run_failed
    call sys_puts
    call sys_newline
    jmp .shell_loop

.cmd_run_usage:
    mov si, msg_run_usage
    call sys_puts
    call sys_newline
    jmp .shell_loop

.cmd_run_not_found:
    mov si, msg_run_not_found
    call sys_puts
    call sys_newline
    jmp .shell_loop

.cmd_run_load_fail:
    mov si, msg_run_load_fail
    call sys_puts
    call sys_newline
    jmp .shell_loop

.cmd_run_fs_fail:
    mov si, msg_run_fs_fail
    call sys_puts
    call sys_newline
    jmp .shell_loop

; --- syscall helpers ---
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

sys_clear:
    mov ah, SYS_CLEAR
    int SYSCALL_INT
    ret

; Input: DS:SI points to program name
; Output: AH status (0=ok, 1=unknown, 2=load fail)
sys_run:
    mov ah, SYS_RUN
    int SYSCALL_INT
    ret

; str_eq: DS:SI == DS:DI -> AL=1 yes, AL=0 no
str_eq:
.eq_loop:
    mov al, [si]
    mov bl, [di]
    cmp al, bl
    jne .no
    cmp al, 0
    je .yes
    inc si
    inc di
    jmp .eq_loop
.yes:
    mov al, 1
    ret
.no:
    mov al, 0
    ret

; str_startswith: DS:SI starts with DS:DI -> AL=1 yes, AL=0 no
str_startswith:
.sw_loop:
    mov al, [di]
    cmp al, 0
    je .yes
    mov bl, [si]
    cmp bl, al
    jne .no
    inc si
    inc di
    jmp .sw_loop
.yes:
    mov al, 1
    ret
.no:
    mov al, 0
    ret

shell_banner:
    db "Circle Shell interactive mode v0.1.3", 0

shell_prompt:
    db "csh> ", 0

msg_help:
    db "commands: help, clear, echo <text>, run <name>, exit", 0

msg_unknown:
    db "unknown command", 0

msg_exit:
    db "returning to kernel", 0

msg_run_usage:
    db "usage: run <name>", 0

msg_run_not_found:
    db "program not found", 0

msg_run_load_fail:
    db "program load failed", 0

msg_run_failed:
    db "program failed", 0

msg_run_fs_fail:
    db "filesystem unavailable", 0

cmd_help:
    db "help", 0

cmd_clear:
    db "clear", 0

cmd_echo:
    db "echo", 0

cmd_echo_prefix:
    db "echo ", 0

cmd_run:
    db "run", 0

cmd_run_prefix:
    db "run ", 0

cmd_exit:
    db "exit", 0

cmd_buf:
    times 32 db 0