; TUI for CircleOS - SphereTUI
; Provides a simple text-based user interface for file browsing and program launching
; CEX1 VERSION 1

[BITS 16]           ; 16-bit real mode assembly
[ORG 0xA000]        ; load address for user programs

SYSCALL_INT equ 0x80
SYS_PUTC equ 0x01
SYS_PUTS equ 0x02
SYS_NEWLINE equ 0x03
SYS_GETC equ 0x04
SYS_CLEAR equ 0x05
SYS_RUN equ 0x06

CTRL_C equ 0x03         ; user abort
KEY_ENTER equ 13

SCAN_UP equ 0x48
SCAN_DOWN equ 0x50

start:
    mov ax, 0           ; zero AX for data segment setup
    mov ds, ax          ; point DS to segment 0 for message access
    mov es, ax          ; point ES to segment 0 for any file read buffers
    mov ah, SYS_CLEAR        ; clear the screen before showing TUI
    int SYSCALL_INT
    call shortcuts_init_defaults ; initialize shortcuts with default values

sph_redraw:
    call clear_screen
    call draw_frame
    call draw_shortcuts
    jmp sph_loop

sph_loop:
    ; Place prompt at line 24, character 7 (0-based: row 23, col 6).
    mov dh, 23
    mov dl, 6
    call cursor_move

    mov si, msg_prompt
    call sys_puts
    
    call read_line
    cmp byte [cmd_buf], 0
    je sph_loop

    ; quick exits
    mov si, cmd_buf
    mov di, cmd_zero
    call str_eq
    cmp al, 1
    je sph_exit

    mov si, cmd_buf
    mov di, cmd_exit
    call str_eq
    cmp al, 1
    je sph_exit

    ; help command
    mov si, cmd_buf
    mov di, cmd_help
    call str_eq
    cmp al, 1
    je cmd_help_handler

    ; list
    mov si, cmd_buf
    mov di, cmd_list
    call str_eq
    cmp al, 1
    je cmd_list_handler

    ; launch n or launch name
    mov si, cmd_buf
    mov di, cmd_launch_prefix
    call str_startswith
    cmp al, 1
    je cmd_launch_handler

    ; bind N name
    mov si, cmd_buf
    mov di, cmd_bind_prefix
    call str_startswith
    cmp al, 1
    je cmd_bind_handler

    ; unbind N
    mov si, cmd_buf
    mov di, cmd_unbind_prefix
    call str_startswith
    cmp al, 1
    je cmd_unbind_handler

    mov si, msg_unknown
    call sys_puts
    call sys_newline
    jmp sph_loop

sph_exit:
    mov si, msg_goodbye
    call sys_puts
    call sys_newline
    ret

cmd_help_handler:
    mov si, msg_help
    call sys_puts
    call sys_newline
    jmp sph_loop

cmd_list_handler:
    call print_shortcuts
    jmp sph_loop

cmd_launch_handler:
    ; extract argument after "launch "
    mov si, cmd_buf
    add si, 7          ; length of "launch "
    cmp byte [si], 0
    je .usage

    mov al, [si]        ; guard against empty/corrupt names
    cmp al, '1'
    jb .by_name
    cmp al, '9'
    ja .by_name
    cmp byte [si + 1], 0
    jne .by_name

    sub al, '1'         ; slot index 0..8
    xor ah, ah
    mov bx, ax          ; shortcut slot in BX

    mov ax, bx
    mov bx, 9
    mul bx              ; offset = slot * entry_size (16 bytes)
    mov si, shortcut_table
    add si, ax          ; point SI to shortcut entry
    cmp byte [si], 0    ; check if slot is bound
    je .empty_slot

    call launch_program_name
    jmp sph_redraw

.by_name:
    call launch_program_name
    jmp sph_redraw

.empty_slot:
    mov si, msg_empty_slot
    call sys_puts
    call sys_newline
    jmp sph_loop

.usage:
    mov si, msg_launch_usage
    call sys_puts
    call sys_newline
    jmp sph_loop

cmd_bind_handler:
    ; extract arguments after "bind "
    mov si, msg_todo_bind
    call sys_puts
    call sys_newline
    jmp sph_loop

cmd_unbind_handler:
    ; extract arguments after "unbind "
    mov si, msg_todo_unbind
    call sys_puts
    call sys_newline
    jmp sph_loop

launch_program_name:
    mov ah, SYS_RUN
    int SYSCALL_INT
    cmp ah, 0
    je .ok
    mov si, msg_launch_fail
    call sys_puts
    call sys_newline
.ok:
    ret

clear_screen:
    mov ah, SYS_CLEAR
    int SYSCALL_INT
    ret

draw_frame:
    ; first pass, print prebuilt ascii
    mov si, frame_line_01
    call sys_puts
    call sys_newline
    mov si, frame_line_02
    call sys_puts
    call sys_newline
    mov si, frame_line_03
    call sys_puts
    call sys_newline
    mov si, frame_line_04
    call sys_puts
    call sys_newline
    mov si, frame_line_05
    call sys_puts
    call sys_newline
    mov si, frame_line_06
    call sys_puts
    call sys_newline
    mov si, frame_line_07
    call sys_puts
    call sys_newline
    mov si, frame_line_08
    call sys_puts
    call sys_newline
    mov si, frame_line_09
    call sys_puts
    call sys_newline
    mov si, frame_line_10
    call sys_puts
    call sys_newline
    mov si, frame_line_11
    call sys_puts
    call sys_newline
    mov si, frame_line_12
    call sys_puts
    call sys_newline
    mov si, frame_line_13
    call sys_puts
    call sys_newline
    mov si, frame_line_14
    call sys_puts
    call sys_newline
    mov si, frame_line_15
    call sys_puts
    call sys_newline
    mov si, frame_line_16
    call sys_puts
    call sys_newline
    mov si, frame_line_17
    call sys_puts
    call sys_newline
    mov si, frame_line_18
    call sys_puts
    call sys_newline
    mov si, frame_line_19
    call sys_puts
    call sys_newline
    mov si, frame_line_20
    call sys_puts
    call sys_newline
    mov si, frame_line_21
    call sys_puts
    call sys_newline
    mov si, frame_line_22
    call sys_puts
    call sys_newline
    mov si, frame_line_23
    call sys_puts
    call sys_newline
    mov si, frame_line_24
    call sys_puts
    call sys_newline
    mov si, frame_line_25
    call sys_puts
    call sys_newline
    ret

draw_shortcuts:
    ret

print_shortcuts:
    mov si, msg_slots_header
    call sys_puts
    call sys_newline

    mov si, shortcut_table
    mov cx, 9          ; max 9 shortcuts

    ret

read_line:
    xor cx, cx          ; clear CX for counting input length
    mov bx, cmd_buf     ; point BX to command buffer

.loop:
    call sys_getc       ; get character from user input

    cmp al, CTRL_C      ; cancel input
    je .cancel

    cmp al, KEY_ENTER   ; enter = done
    je .done

    cmp al, 8           ; backspace
    je .backspace

    call sys_putc       ; echo character
    cmp cx, 63          ; prevent overflow (leave space for null terminator)
    jae .loop
    mov si, cx
    mov [bx + si], al   ; store character in buffer
    inc cx
    jmp .loop

.backspace:
    cmp cx, 0
    je .loop
    mov al, 8
    call sys_putc
    mov al, ' '
    call sys_putc
    mov al, 8
    call sys_putc
    dec cx
    jmp .loop

.cancel:
    call sys_newline
    mov byte [cmd_buf], 0  ; null-terminate buffer to indicate cancel
    ret

.done:
    mov si, cx
    mov byte [bx + si], 0  ; null-terminate buffer
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

cursor_move:
    ; Input: DH=row, DL=col (both 0-based)
    mov ah, 0x02
    mov bh, 0
    int 0x10
    ret

str_eq:                ; compare strings at DS:SI and DS:DI, return AL=1 if equal, else 0
.eq_loop:
    mov al, [si]
    mov bl, [di]
    cmp al, bl
    jne .no
    cmp al, 0           ; end of string?
    je .yes
    inc si
    inc di
    jmp .eq_loop
.yes:
    mov al, 1
    ret
.no:
    xor al, al
    ret

str_startswith:       ; check if string at DS:SI starts with string at DS:DI, return AL=1 if yes, else 0
.sw_loop:
    mov al, [di]
    cmp al, 0           ; end of prefix string?
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
    xor al, al
    ret

shortcuts_init_defaults:
    ; initialize shortcut table with zeros (unbound)
    mov byte [shortcut_table + 0], 'l'
    mov byte [shortcut_table + 1], 's'
    mov byte [shortcut_table + 2], 0
    ; rest of the 16-byte entries are already zero-initialized by default

    ret

; commands
cmd_help:
    db "help", 0
cmd_list:
    db "list", 0
cmd_launch_prefix:
    db "launch ", 0
cmd_bind_prefix:
    db "bind ", 0
cmd_unbind_prefix:
    db "unbind ", 0
cmd_zero:
    db "0", 0
cmd_exit:
    db "exit", 0

; messages
msg_help:
    db "Available commands:", 13, 10
    db "help - show this message", 13, 10
    db "list - list shortcuts", 13, 10
    db "launch N|name - launch program by shortcut number or name", 13, 10
    db "bind N name - bind program name to shortcut number", 13, 10
    db "unbind N - unbind shortcut number", 13, 10
    db "exit or quit - exit the TUI", 13, 10, 0

msg_prompt:
    db "SPH > ", 0
msg_goodbye:
    db "Goodbye!", 13, 10, 0
msg_unknown:
    db "Unknown command. Type 'help' for a list of commands.", 13, 10, 0
msg_launch_usage:
    db "Usage: launch N|name", 13, 10, 0
msg_empty_slot:
    db "Shortcut slot is empty. Use 'bind N name' to bind a program.", 13, 10, 0
msg_launch_fail:
    db "Failed to launch program. Make sure the name is correct and the program exists.", 13, 10, 0
msg_slots_header:
    db "Shortcuts:", 13, 10, 0
msg_todo_bind:
    db "Bind command not implemented yet. This is a TODO.", 13, 10, 0
msg_todo_unbind:
    db "Unbind command not implemented yet. This is a TODO.", 13, 10, 0

; frame ascii art
frame_line_01:
    db "+---+--------------------------------------------------------------------------+", 0
frame_line_02:
    db "| 1 |                                                                          |", 0
frame_line_03:
    db "|---|                                                                          |", 0
frame_line_04:
    db "| 2 |                                                                          |", 0
frame_line_05:
    db "|---|                                                                          |", 0
frame_line_06:
    db "| 3 |                                                                          |", 0
frame_line_07:
    db "|---|                                                                          |", 0
frame_line_08:
    db "| 4 |                                                                          |", 0
frame_line_09:
    db "|---|                                                                          |", 0
frame_line_10:
    db "| 5 |                                                                          |", 0
frame_line_11:
    db "|---|                                                                          |", 0
frame_line_12:
    db "| 6 |                                                                          |", 0
frame_line_13:
    db "|---|                                                                          |", 0
frame_line_14:
    db "| 7 |                                                                          |", 0
frame_line_15:
    db "|---|                                                                          |", 0
frame_line_16:
    db "| 8 |                                                                          |", 0
frame_line_17:
    db "|---|                                                                          |", 0
frame_line_18:
    db "| 9 |                                                                          |", 0
frame_line_19:
    db "|---|                                                                          |", 0
frame_line_20:
    db "| 0 |                                                                          |", 0
frame_line_21:
    db "|---|                                                                          |", 0
frame_line_22:
    db "|   +--------------------------------------------------------------------------+", 0
frame_line_23:
    db "|   |                                                                          |", 0
frame_line_24:
    db "|   |                                                                          |", 0
frame_line_25:
    db "+---+--------------------------------------------------------------------------+", 0

shortcut_table:
    times 81 db 0

cmd_buf:
    times 64 db 0