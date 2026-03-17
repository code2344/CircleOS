; kernel.asm
; CircleOS kernel - a simple shell with basic commands.

[BITS 16]           ; assemble these instructions for 16-bit mode
[ORG 0x7E00]        ; this code lives at 0x7e00

start:
    mov ax, 0           ; clear register AX temporarily to initialise segment registers
    mov ds, ax          ; clear and initialise data segment
    mov es, ax          ; clear and initialise extra segment

    mov si, welcome_msg    ; move boot message to source
    call print_string   ; calls print string (prints SI)


; begin main shell loop
.shell_loop:
    mov si, prompt      ; move prompt (arcsh >)
    call print_string   ; print prompt

    ; read command from keyboard
    xor cx, cx          ; cx=0, start at first byte
    mov bx, command_buf ; bx points to command buffer start

.read_loop:
    mov ah, 0x00        ; bios wait for key press and return 
    int 0x16            ; bios interrupt to return key press
    
    ; check for enter key
    cmp al, 13          ; key press goes into AL for the ascii code, ascii code of carriage return is 13 or 0D
    je .command_ready   ; enter means command is finished, so jump to command execution

    cmp al, 8           ; check for backspace character
    je .backspace       ; jump if ZF is set, if AL = 8 then the previous line set ZF so jump to .backspace jump target

    ; print character via BIOS TTY by running int 10 and setting AH to 0E
    mov ah, 0x0E
    int 0x10

    ; store typed character in command buffer at [BX+CX], bx is base and cx is index
    mov si, cx
    mov byte [bx + si], al
    inc cx

    ; limit input length to 32 bytes
    cmp cx, 32
    jl .read_loop

    ; if at or over 32 keep reading but ignore storage
    jmp .read_loop

.backspace:
    cmp cx, 0           ; is the cursor already at the start?
    je .read_loop       ; if yes, exit backspace loop and go to read loop

    mov ah, 0x0E
    mov al, 8           ; ASCII backspace
    int 0x10
    mov al, ' '         ; print ' ' to cover/erase old character
    int 0x10
    mov al, 8           ; backspace again :)
    int 0x10

    dec cx
    jmp .read_loop

.command_ready:
    mov si, cx
    mov byte [bx + si], 0       ;null terminate the command so routines know where it ends

    mov ah, 0x0E                ; set for printing
    mov al, 13                  ; 13 is CR (or new line)
    int 0x10                    ; print character to screen
    mov al, 10
    int 0x10

    ; simple command parser, just match by first character
    mov si, command_buf
    lodsb                       ; puts si into al and increments si

    cmp al, 'h'                 ; help?
    je .cmd_help

    cmp al, 'e'                 ; echo?
    je .cmd_echo

    cmp al, 'c'                 ; clear
    je .cmd_clear

    cmp al, 0                   ; empty command?
    je .shell_loop

    mov si, unknown_msg         ; unknown command message
    call print_string
    jmp .shell_loop

.cmd_help:
    mov si, help_msg
    call print_string
    jmp .shell_loop

.cmd_echo:
    ; assumes command starts with "echo ", skips as prefix
    mov si, command_buf
    inc si                      ; skip 'e'
    lodsb                       ; consume 'c'
    lodsb                       ; consume 'h'
    lodsb                       ; consume 'o'
    lodsb                       ; consume ' ' or 0 if just echo without space

    cmp al, 0
    je .shell_loop              ; if al is 0 then there was nothing after 'echo' so no command

    dec si
    call print_string

    ; newline after echoed text
    mov ah, 0x0E
    mov al, 13                  ; CR
    int 0x10
    mov al, 10                  ; line feed
    int 0x10

    jmp .shell_loop

.cmd_clear:
    ;clear using bios scroll up function
    ; int 10 ah 06 is scroll
    ; al is lines to scroll 0 is clear Available
    ; bh is attribute of blank lines
    ; cx is upper left
    ; dx is lower right
    mov ah, 0x06
    mov al, 0
    mov bh, 0x07
    mov cx, 0
    mov dx, 0x184F
    int 0x10                    ; bios video services

    ; put cursor at top left through video int with ah=06h
    mov ah, 0x02
    mov bh, 0
    mov dx, 0
    int 0x10

    jmp .shell_loop

print_string:
    lodsb               ; Load byte from [ds:si] into al, increment si, ds is data segment default for reading data
    cmp al, 0           ; is the byte the null terminator?
    je .done            ; if it's yes then the program's done

    mov ah, 0x0E        ; BIOS teletype output
    int 0x10            ; Call bios video interrupt
    jmp print_string    ; loop to the next character
    
.done:
    ret

; text data
welcome_msg:
    db "Welcome to CircleOS v0.1.0!", 13, 10, 0

help_msg:
    db "Available commands:", 13, 10
    db "  help   - show this message", 13, 10
    db "  echo   - echo text back", 13, 10
    db "  clear  - clear the screen", 13, 10, 0

prompt:
    db "CircleOS Kernel > ", 0

unknown_msg:
    db "Unknown command. Type 'help' for commands.", 13, 10, 0

command_buf:
    times 32 db 0   ; input storage.



