; kernel.asm
; CircleOS kernel - a simple shell with basic commands.
; Protected-mode 32-bit kernel with native IRQ-based drivers

[BITS 32]           ; assemble these instructions for 32-bit mode
[ORG 0x7E00]        ; this code lives at 0x7e00

BOOT_INFO_ADDR equ 0x0500
BOOT_SIG0_OFF equ BOOT_INFO_ADDR + 0
BOOT_SIG1_OFF equ BOOT_INFO_ADDR + 1
BOOT_VER_OFF equ BOOT_INFO_ADDR + 2
BOOT_DRIVE_OFF equ BOOT_INFO_ADDR + 3
BOOT_KSECT_OFF equ BOOT_INFO_ADDR + 4

SYSCALL_INT equ 0x80
SYS_PUTC equ 0x01
SYS_PUTS equ 0x02
SYS_NEWLINE equ 0x03
SYS_GETC equ 0x04
SYS_CLEAR equ 0x05
SYS_RUN equ 0x06
SYS_READ_RAW equ 0x07
SYS_WRITE_RAW equ 0x08
SYS_FS_READ equ 0x09
SYS_FS_WRITE equ 0x0A
SYS_FS_LIST equ 0x0B
SYS_FS_DELETE equ 0x0C
SYS_FS_MKDIR equ 0x0D
SYS_FS_CHDIR equ 0x0E
SYS_REBOOT equ 0x0F
SYS_SET_VIDEO_MODE equ 0x10
SYS_PRESENT_FRAMEBUFFER equ 0x11

%ifndef DEBUG
%define DEBUG 0
%endif

%ifndef FS_TABLE_SECTOR
FS_TABLE_SECTOR equ 20
%endif

%ifndef SHELL_SECTORS
SHELL_SECTORS equ 2
%endif

%ifndef LS_SECTOR
LS_SECTOR equ 19
%endif

%ifndef LS_SECTORS
LS_SECTORS equ 1
%endif

%ifndef INFO_SECTOR
INFO_SECTOR equ 20
%endif

%ifndef INFO_SECTORS
INFO_SECTORS equ 1
%endif

%ifndef STAT_SECTOR
STAT_SECTOR equ 21
%endif

%ifndef STAT_SECTORS
STAT_SECTORS equ 1
%endif

%ifndef GREET_SECTOR
GREET_SECTOR equ 22
%endif

%ifndef GREET_SECTORS
GREET_SECTORS equ 1
%endif

%ifndef CAT_SECTOR
CAT_SECTOR equ 23
%endif

%ifndef CAT_SECTORS
CAT_SECTORS equ 1
%endif

%ifndef TODO_SECTOR
TODO_SECTOR equ 25
%endif

%ifndef TODO_SECTORS
TODO_SECTORS equ 1
%endif

%ifndef DIR_SECTOR
DIR_SECTOR equ 19
%endif

%ifndef DIR_SECTORS
DIR_SECTORS equ 1
%endif

%ifndef WRITE_SECTOR
WRITE_SECTOR equ 26
%endif

%ifndef WRITE_SECTORS
WRITE_SECTORS equ 1
%endif

%ifndef IMG_SECTOR
IMG_SECTOR equ 27
%endif

%ifndef IMG_SECTORS
IMG_SECTORS equ 1
%endif

%ifndef SPHERE_SECTOR
SPHERE_SECTOR equ 28
%endif

%ifndef SPHERE_SECTORS
SPHERE_SECTORS equ 1
%endif

PROG_TABLE_ADDR equ 0x0600
PROG_TABLE_MAX_ENTRIES equ 16
SHELL_LOAD_ADDR equ 0xB000

; -----------------------------
; InodeFS (flat root directory)
; -----------------------------
INFS_SUPER_SECTOR equ 200
INFS_INODE_SECTOR equ 201
INFS_BITMAP_SECTOR equ 202
INFS_DATA_START_SECTOR equ 203

INFS_MAX_INODES equ 32
INFS_MAX_BLOCKS equ 128
INFS_INODE_SIZE equ 16
INFS_NAME_LEN equ 8
INFS_ROOT_INODE equ 0

INFS_TYPE_FILE equ 1
INFS_TYPE_DIR equ 2
INFS_TYPE_ARC equ 3

INFS_OFF_USED equ 0
INFS_OFF_TYPE equ 1
INFS_OFF_SIZE equ 2
INFS_OFF_START equ 4
INFS_OFF_COUNT equ 5
INFS_OFF_PARENT equ 6
INFS_OFF_NAME equ 8

INFS_SUPER_BUF equ 0x1200
INFS_INODE_BUF equ 0x1400
INFS_BITMAP_BUF equ 0x1600

start:
    [BITS 16]               ; temporarily 16-bit for boot
    cli                     ; disable interrupts during mode switch
    
    mov ax, 0               ; DS and ES point to absolute memory for boot info
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7000          ; safe real-mode stack before preload BIOS calls
    mov al, 'k'
    call bios_putc_16

    ; Verify boot sector signature (bootloader must write it)
    cmp byte [BOOT_SIG0_OFF], 'C'
    jne .boot_info_bad      ; bootloader didn't initialize boot info
    cmp byte [BOOT_SIG1_OFF], 'B'
    jne .boot_info_bad
    mov al, 's'
    call bios_putc_16

    ; Retrieve boot drive from bootloader
    mov al, [BOOT_DRIVE_OFF]
    mov [kernel_boot_drive], al

    ; Preload core boot assets (program table + shell) from the actual boot drive.
    mov byte [boot_preload_ok], 0
    call preload_boot_assets_16
    mov al, 'p'
    call bios_putc_16

    call enable_a20         ; enable A20 gate
    call load_boot_gdt      ; load flat GDT
    mov al, 'g'
    call bios_putc_16
    
    ; ========== PROTECTED MODE SWITCH ==========
    mov eax, cr0
    or eax, 1               ; set CR0.PE bit
    mov cr0, eax
    
    ; Far jump to 32-bit code segment (0x08 = flat code selector)
    ; Use explicit 32-bit far jump encoding while still in 16-bit mode.
    db 0x66, 0xEA
    dd .pm_entry
    dw 0x08
    
    [BITS 32]
.pm_entry:
    ; Now running in 32-bit protected mode
    ; Reload segment registers to 32-bit flat mode (selector 0x10 = flat data)
    mov eax, 0x10
    mov ds, eax
    mov es, eax
    mov ss, eax
    mov esp, 0x7E00         ; stack just below kernel
    
    xor eax, eax            ; zero out GS/FS
    mov gs, eax
    mov fs, eax

    mov edi, 0xB8000
    mov word [edi], 0x074D  ; 'M' with light gray attribute
    
    ; Install IDT for protected mode
    call install_idt_32

    sti                     ; re-enable interrupts after IDT is live

    ; Display boot banner
    call console_clear_32
    call show_boot_logo
    mov eax, 120
    call delay_ms
    call console_clear_32

    ; Assume storage is available until proven otherwise.
    mov byte [disk_available], 1
    mov byte [rescue_reason], 0

    ; If we booted from floppy, don't expect ATA-backed storage.
    cmp byte [kernel_boot_drive], 0x80
    jae .pm_disk_ok
    mov byte [disk_available], 0
.pm_disk_ok:

    ; Load program table if it wasn't already preloaded in real mode.
    cmp byte [prog_table_loaded], 1
    je .pm_table_ready
    call load_program_table
    cmp ah, 0               ; AH=0 success, else error
    jne .prog_table_bad
.pm_table_ready:

    ; Boot resilience: defer InodeFS mount/format until explicitly needed.
    ; Some environments can stall during early metadata probing.
    mov byte [fs_inode_ready], 0
    mov byte [fs_cwd_inode], INFS_ROOT_INODE
.pm_after_fs:

    ; If storage is unavailable, still try preloaded userspace shell if table exists.
    cmp byte [disk_available], 1
    je .pm_try_shell
    cmp byte [boot_preload_ok], 1
    jne rescue_ui

.pm_try_shell:

    ; Launch user shell (csh.asm entry point)
    call launch_shell
    jmp rescue_ui


.boot_info_bad:
    mov si, boot_info_bad_msg
    call bios_puts_16
    jmp halt

.prog_table_bad:
    mov bl, ah
    mov si, prog_table_bad_msg
    call console_puts
    mov si, prog_table_bad_code_msg
    call console_puts
    mov al, bl
    call print_hex8_32

    cmp bl, 1
    jne .pt_not_read_fail
    mov si, prog_table_bad_read_msg
    call console_puts
    jmp .pt_reason_done ; jump unconditionally

.pt_not_read_fail:
    cmp bl, 2
    jne .pt_not_magic_fail
    mov si, prog_table_bad_magic_msg
    call console_puts
    jmp .pt_reason_done ; jump unconditionally

.pt_not_magic_fail:
    cmp bl, 3
    jne .pt_not_count_fail
    mov si, prog_table_bad_count_msg
    call console_puts
    jmp .pt_reason_done ; jump unconditionally

.pt_not_count_fail:
    cmp bl, 4
    jne .pt_reason_done
    mov si, prog_table_bad_layout_msg
    call console_puts

.pt_reason_done:
    mov si, prog_table_bad_ata_msg
    call console_puts
    mov al, [ata_last_status]
    call print_hex8_32
    call console_newline
    mov byte [rescue_reason], 0x10
    jmp halt
.shell_loop:
    mov si, prompt      ; move prompt (CircleOS Kernel >)
    call console_puts_32   ; print prompt

    ; read command from keyboard
    xor ecx, ecx          ; ecx=0, start at first byte
    mov ebx, command_buf ; ebx points to command buffer start

.read_loop:
    call kbd_getc_32
    
    ; check for enter key
    cmp al, 13          ; key press goes into AL for the ascii code, ascii code of carriage return is 13 or 0D
    je .command_ready   ; enter means command is finished, so jump to command execution

    cmp al, 8           ; check for backspace character
    je .backspace      

    call console_putc_32

    ; store typed character in command buffer at [BX+CX]
    mov byte [ebx + ecx], al
    inc ecx

    ; limit input length to 32 bytes
    cmp ecx, 32
    jl .read_loop

    ; if at or over 32 keep reading but ignore storage
    jmp .read_loop ; jump unconditionally

.backspace:
    cmp ecx, 0           ; is the cursor already at the start?
    je .read_loop       ; if yes, exit backspace loop and go to read loop

    call console_putc_32  ; print backspace char

    dec ecx
    jmp .read_loop ; jump unconditionally

.command_ready:
    mov byte [ebx + ecx], 0       ;null terminate the command so routines know where it ends

    call console_newline_32

    ; Exact command dispatch
    cmp byte [command_buf], 0
    je .shell_loop ; jump if equal/zero

    ; help
    mov si, command_buf
    mov di, cmd_help_str
    call str_eq
    cmp al, 1
    je .cmd_help ; jump if equal/zero

    ; csh
    mov si, command_buf
    mov di, cmd_csh_str
    call str_eq
    cmp al, 1
    je .cmd_csh ; jump if equal/zero

    ; Unknown command
    mov si, unknown_msg
    call console_puts_32
    call console_newline_32
    jmp .shell_loop ; jump unconditionally

.cmd_help:
    mov si, help_msg
    call console_puts_32
    call console_newline_32
    jmp .shell_loop ; jump unconditionally
.cmd_csh:
    call launch_shell
    jmp .shell_loop ; jump unconditionally

kernel_boot_drive:
    db 0
boot_preload_ok:
    db 0

halt:
    hlt                 ; halt the cpu
    jmp halt            ; infinite loop just in case
; ----------------------------------
; Kernel service wrappers for routines (32-bit protected mode)
;-----------------------------------

; console_putc_32
; Input: AL = character
; Writes directly to VGA text-mode VRAM at 0xB8000
; Uses 80x25 text mode: 2 bytes per character (char + attribute)
; Clobbers: EAX, EBX, ECX, EDX
gVGA_CURSOR equ 0x1000     ; kernel RAM storage for cursor position (0-80)
cursor_x equ (gVGA_CURSOR)
cursor_y equ (gVGA_CURSOR+1)

console_putc_32:
    push eax
    push ebx
    push ecx
    push edx
    
    mov bl, al              ; save character
    cmp al, 13              ; CR?
    je .putc_newline
    
    cmp al, 8               ; backspace?
    je .putc_backspace
    
    ; Regular character - write to VRAM
    mov al, [cursor_y]      ; row
    mov cl, 80
    mul cl                  ; EAX = row * 80
    mov cl, [cursor_x]      ; column
    add eax, ecx            ; offset = row*80 + col
    shl eax, 1              ; each cell is 2 bytes (char + attr)
    
    mov edx, 0xB8000        ; VGA text VRAM
    add edx, eax
    
    mov [edx], bl           ; write character
    mov byte [edx+1], 0x07  ; white on black attribute
    
    ; advance cursor
    inc byte [cursor_x]
    cmp byte [cursor_x], 80
    jl .putc_done
    
    ; wrap to next line
    mov byte [cursor_x], 0
    inc byte [cursor_y]
    cmp byte [cursor_y], 25
    jl .putc_done
    
    ; scroll: move lines 1-24 up to 0-23, clear line 24
    call scroll_vga
    mov byte [cursor_y], 24
    jmp .putc_done
    
.putc_backspace:
    cmp byte [cursor_x], 0
    je .putc_xy_start
    
    dec byte [cursor_x]
    ; clear the character
    mov al, [cursor_y]
    mov cl, 80
    mul cl
    mov cl, [cursor_x]
    add eax, ecx
    shl eax, 1
    mov edx, 0xB8000
    add edx, eax
    mov byte [edx], ' '
    mov byte [edx+1], 0x07
    jmp .putc_done
    
.putc_newline:
    mov byte [cursor_x], 0
    inc byte [cursor_y]
    cmp byte [cursor_y], 25
    jl .putc_done
    
    call scroll_vga
    mov byte [cursor_y], 24
    jmp .putc_done
    
.putc_xy_start:
    cmp byte [cursor_y], 0
    je .putc_done
    mov byte [cursor_x], 79
    dec byte [cursor_y]
    
.putc_done:
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

scroll_vga:
    ; Scroll VGA text up one line: lines 1-24 → 0-23, clear line 24
    push eax
    push ecx
    push esi
    push edi
    
    mov esi, 0xB8000 + 80*2 ; source = line 1
    mov edi, 0xB8000        ; dest = line 0
    mov ecx, 24*80*2        ; 24 lines * 80 chars * 2 bytes
    cld
    rep movsb
    
    ; Clear bottom line (line 24)
    mov edi, 0xB8000 + 24*80*2
    xor eax, eax
    mov ecx, 80*2
    rep stosb
    
    pop edi
    pop esi
    pop ecx
    pop eax
    ret

; Input: DS:SI = null terminated string
; clobbers: EAX, EBX, ECX, EDX, ESI
console_puts_32:
.loop:
    lodsb
    cmp al, 0
    je .done
    call console_putc_32
    jmp .loop
.done:
    ret

; prints CRLF
console_newline_32:
    mov al, 13
    call console_putc_32
    mov al, 10
    call console_putc_32
    ret

; clears text mode screen
console_clear_32:
    push eax
    push eax
    push ecx
    push edi
    
    mov edi, 0xB8000
    xor eax, eax
    mov ecx, 80*25*2        ; 80 columns, 25 rows, 2 bytes each
    cld
    rep stosb
    
    ; reset cursor
    mov byte [cursor_x], 0
    mov byte [cursor_y], 0
    
    pop edi
    pop ecx
    pop eax
    pop eax
    ret

; ========== KEYBOARD DRIVER (IRQ1) ==========
; Polls port 0x60 for keyboard data (simple polling, no IRQ yet)

kbd_getc_32:
    push ecx
    push edx
    push ebx
    
    ; Poll keyboard status port for key available
.kbd_wait:
    mov edx, 0x64           ; kbd controller status port
    in al, dx
    test al, 1              ; bit 0 = output buffer full?
    jz .kbd_wait
    
    ; Read key from data port
    mov edx, 0x60           ; kbd data port
    in al, dx

    ; Set-2 break prefix means next scancode is release byte.
    cmp al, 0xF0
    jne .kbd_not_set2_break_prefix
    mov byte [kbd_scancode_set], 2
    mov byte [kbd_set2_break], 1
    jmp .kbd_wait ; jump unconditionally

.kbd_not_set2_break_prefix:

    ; If previous byte was a Set-2 break prefix, consume release byte.
    cmp byte [kbd_set2_break], 1
    jne .kbd_no_set2_break_byte
    mov byte [kbd_set2_break], 0
    mov bl, al
    cmp bl, 0x12            ; left shift release in set-2
    je .kbd_shift_off
    cmp bl, 0x59            ; right shift release in set-2
    je .kbd_shift_off
    jmp .kbd_wait ; jump unconditionally

.kbd_no_set2_break_byte:

    ; Ignore extended prefix bytes in this minimal decoder.
    cmp al, 0xE0
    je .kbd_wait

    mov bl, al

    ; Release scancode: update modifiers and continue waiting.
    test bl, 0x80
    jnz .kbd_release

    ; Shift press (left/right).
    cmp bl, 0x2A
    je .kbd_shift_on
    cmp bl, 0x36
    je .kbd_shift_on

    ; Set-2 shift make codes only apply when set-2 has been observed.
    cmp byte [kbd_scancode_set], 2
    jne .kbd_translate
    cmp bl, 0x12
    je .kbd_shift_on
    cmp bl, 0x59
    je .kbd_shift_on

.kbd_translate:

    ; If set-2 mode has been observed, use set-2 translation first.
    cmp byte [kbd_scancode_set], 2
    jne .kbd_translate_set1
    mov al, bl
    cmp byte [kbd_shift_state], 0
    je .kbd_set2_plain
    call kbd_translate_set2_shift
    jmp .kbd_emit

.kbd_set2_plain:
    call kbd_translate_set2
    jmp .kbd_emit

.kbd_translate_set1:

    ; Translate scancode to ASCII.
    movzx ebx, bl
    cmp byte [kbd_shift_state], 0
    je .kbd_normal
    mov al, [kbd_ascii_shift + ebx]
    jmp .kbd_emit ; jump unconditionally

.kbd_normal:
    mov al, [kbd_ascii + ebx]

.kbd_emit:
    cmp al, 0
    je .kbd_wait
    pop ebx
    pop edx
    pop ecx
    ret

.kbd_release:
    and bl, 0x7F
    cmp bl, 0x2A
    je .kbd_shift_off
    cmp bl, 0x36
    je .kbd_shift_off
    jmp .kbd_wait ; jump unconditionally

.kbd_shift_on:
    mov byte [kbd_shift_state], 1
    jmp .kbd_wait ; jump unconditionally

.kbd_shift_off:
    mov byte [kbd_shift_state], 0
    jmp .kbd_wait ; jump unconditionally
    
    pop ebx
    pop edx
    pop ecx
    ret

; Set-2 translation subset for shell typing.
; Input: AL = set-2 make scancode
; Output: AL = ASCII or 0 if unmapped
kbd_translate_set2:
    cmp al, 0x1C
    je .s2_a
    cmp al, 0x32
    je .s2_b
    cmp al, 0x21
    je .s2_c
    cmp al, 0x23
    je .s2_d
    cmp al, 0x24
    je .s2_e
    cmp al, 0x2B
    je .s2_f
    cmp al, 0x34
    je .s2_g
    cmp al, 0x33
    je .s2_h
    cmp al, 0x43
    je .s2_i
    cmp al, 0x3B
    je .s2_j
    cmp al, 0x42
    je .s2_k
    cmp al, 0x4B
    je .s2_l
    cmp al, 0x3A
    je .s2_m
    cmp al, 0x31
    je .s2_n
    cmp al, 0x44
    je .s2_o
    cmp al, 0x4D
    je .s2_p
    cmp al, 0x15
    je .s2_q
    cmp al, 0x2D
    je .s2_r
    cmp al, 0x1B
    je .s2_s
    cmp al, 0x2C
    je .s2_t
    cmp al, 0x3C
    je .s2_u
    cmp al, 0x2A
    je .s2_v
    cmp al, 0x1D
    je .s2_w
    cmp al, 0x22
    je .s2_x
    cmp al, 0x35
    je .s2_y
    cmp al, 0x1A
    je .s2_z

    cmp al, 0x16
    je .s2_1
    cmp al, 0x1E
    je .s2_2
    cmp al, 0x26
    je .s2_3
    cmp al, 0x25
    je .s2_4
    cmp al, 0x2E
    je .s2_5
    cmp al, 0x36
    je .s2_6
    cmp al, 0x3D
    je .s2_7
    cmp al, 0x3E
    je .s2_8
    cmp al, 0x46
    je .s2_9
    cmp al, 0x45
    je .s2_0

    cmp al, 0x4E
    je .s2_minus
    cmp al, 0x55
    je .s2_eq
    cmp al, 0x54
    je .s2_lbr
    cmp al, 0x5B
    je .s2_rbr
    cmp al, 0x4C
    je .s2_scol
    cmp al, 0x52
    je .s2_quote
    cmp al, 0x41
    je .s2_comma
    cmp al, 0x49
    je .s2_dot
    cmp al, 0x4A
    je .s2_slash
    cmp al, 0x29
    je .s2_space
    cmp al, 0x5A
    je .s2_enter
    cmp al, 0x66
    je .s2_bs
    cmp al, 0x0D
    je .s2_tab

    xor al, al
    ret

.s2_a: mov al, 'a'
    ret
.s2_b: mov al, 'b'
    ret
.s2_c: mov al, 'c'
    ret
.s2_d: mov al, 'd'
    ret
.s2_e: mov al, 'e'
    ret
.s2_f: mov al, 'f'
    ret
.s2_g: mov al, 'g'
    ret
.s2_h: mov al, 'h'
    ret
.s2_i: mov al, 'i'
    ret
.s2_j: mov al, 'j'
    ret
.s2_k: mov al, 'k'
    ret
.s2_l: mov al, 'l'
    ret
.s2_m: mov al, 'm'
    ret
.s2_n: mov al, 'n'
    ret
.s2_o: mov al, 'o'
    ret
.s2_p: mov al, 'p'
    ret
.s2_q: mov al, 'q'
    ret
.s2_r: mov al, 'r'
    ret
.s2_s: mov al, 's'
    ret
.s2_t: mov al, 't'
    ret
.s2_u: mov al, 'u'
    ret
.s2_v: mov al, 'v'
    ret
.s2_w: mov al, 'w'
    ret
.s2_x: mov al, 'x'
    ret
.s2_y: mov al, 'y'
    ret
.s2_z: mov al, 'z'
    ret
.s2_1: mov al, '1'
    ret
.s2_2: mov al, '2'
    ret
.s2_3: mov al, '3'
    ret
.s2_4: mov al, '4'
    ret
.s2_5: mov al, '5'
    ret
.s2_6: mov al, '6'
    ret
.s2_7: mov al, '7'
    ret
.s2_8: mov al, '8'
    ret
.s2_9: mov al, '9'
    ret
.s2_0: mov al, '0'
    ret
.s2_minus: mov al, '-'
    ret
.s2_eq: mov al, '='
    ret
.s2_lbr: mov al, '['
    ret
.s2_rbr: mov al, ']'
    ret
.s2_scol: mov al, ';'
    ret
.s2_quote: mov al, 39
    ret
.s2_comma: mov al, ','
    ret
.s2_dot: mov al, '.'
    ret
.s2_slash: mov al, '/'
    ret
.s2_space: mov al, ' '
    ret
.s2_enter: mov al, 13
    ret
.s2_bs: mov al, 8
    ret
.s2_tab: mov al, 9
    ret

kbd_translate_set2_shift:
    call kbd_translate_set2
    cmp al, 'a'
    jb .s2s_nonalpha
    cmp al, 'z'
    ja .s2s_nonalpha
    sub al, 32
    ret

.s2s_nonalpha:
    cmp al, '1'
    je .s2s_exclam
    cmp al, '2'
    je .s2s_at
    cmp al, '3'
    je .s2s_hash
    cmp al, '4'
    je .s2s_dollar
    cmp al, '5'
    je .s2s_percent
    cmp al, '6'
    je .s2s_caret
    cmp al, '7'
    je .s2s_amp
    cmp al, '8'
    je .s2s_star
    cmp al, '9'
    je .s2s_lpar
    cmp al, '0'
    je .s2s_rpar
    cmp al, '-'
    je .s2s_us
    cmp al, '='
    je .s2s_plus
    cmp al, '['
    je .s2s_lcb
    cmp al, ']'
    je .s2s_rcb
    cmp al, ';'
    je .s2s_colon
    cmp al, 39
    je .s2s_dquote
    cmp al, ','
    je .s2s_lt
    cmp al, '.'
    je .s2s_gt
    cmp al, '/'
    je .s2s_qm
    ret

.s2s_exclam: mov al, '!'
    ret
.s2s_at: mov al, '@'
    ret
.s2s_hash: mov al, '#'
    ret
.s2s_dollar: mov al, '$'
    ret
.s2s_percent: mov al, '%'
    ret
.s2s_caret: mov al, '^'
    ret
.s2s_amp: mov al, '&'
    ret
.s2s_star: mov al, '*'
    ret
.s2s_lpar: mov al, '('
    ret
.s2s_rpar: mov al, ')'
    ret
.s2s_us: mov al, '_'
    ret
.s2s_plus: mov al, '+'
    ret
.s2s_lcb: mov al, '{'
    ret
.s2s_rcb: mov al, '}'
    ret
.s2s_colon: mov al, ':'
    ret
.s2s_dquote: mov al, 34
    ret
.s2s_lt: mov al, '<'
    ret
.s2s_gt: mov al, '>'
    ret
.s2s_qm: mov al, '?'
    ret

; ========== ATA PIO DISK DRIVER (replaces INT 0x13) ==========
; Reads/writes sectors using ATA PIO protocol
; Supports CHS to LBA conversion (same as before)

ata_read_sectors_32:
    ; Input:
    ;   AL = sector count
    ;   CL = starting sector (1-based)
    ;   ES:BX = destination buffer
    ;   DL = drive number (ignored, assumes drive 0)
    ;   CH = cylinder, DH = head (from lba_to_chs conversion)
    ; Output: CF clear on success, set on error
    
    push eax
    push ebx
    push ecx
    push edx
    push ebp
    push esi
    push edi
    
    mov [ata_sector_count], al
    mov [ata_sector_num], cl
    mov [ata_cylinder], ch
    mov [ata_head], dh
    mov [ata_buffer_offset], ebx
    mov [ata_buffer_segment], es
    
    mov byte [ata_retries], 3
    
.ata_read_try:
    ; Restore parameters
    mov al, [ata_sector_count]
    mov cl, [ata_sector_num]
    mov ch, [ata_cylinder]
    mov dh, [ata_head]
    mov ebx, [ata_buffer_offset]
    mov es, [ata_buffer_segment]
    
    ; Convert CHS to LBA: LBA = (C * 2 * 18) + (H * 18) + (S - 1)
    movzx eax, byte [ata_cylinder]
    imul eax, 36            ; sectors per cylinder (2 heads * 18 sectors)
    movzx edx, byte [ata_head]
    imul edx, 18            ; sectors per head
    add eax, edx
    movzx edx, byte [ata_sector_num]
    dec edx                 ; convert to 0-based sector index
    add eax, edx
    mov [ata_lba], eax
    
    ; Write ATA registers for read
    mov edx, 0x1F2          ; sector count register
    mov al, [ata_sector_count]
    out dx, al
    
    mov edx, 0x1F3          ; LBA low
    mov eax, [ata_lba]
    out dx, al
    
    mov edx, 0x1F4          ; LBA mid
    mov eax, [ata_lba]
    shr eax, 8
    out dx, al
    
    mov edx, 0x1F5          ; LBA high
    mov eax, [ata_lba]
    shr eax, 16
    out dx, al
    
    mov edx, 0x1F6          ; device/head register
    mov eax, [ata_lba]
    shr eax, 24
    and al, 0x0F
    or al, 0xE0             ; LBA mode, drive 0
    out dx, al

    ; 400ns delay after drive/head select
    mov edx, 0x1F7
    in al, dx
    in al, dx
    in al, dx
    in al, dx
    
    mov edx, 0x1F7          ; command register
    mov al, 0x20            ; READ SECTORS command
    out dx, al
    
    ; Read sector(s) from data port (0x1F0)
    mov ebx, [ata_buffer_offset]
    mov es, [ata_buffer_segment]
    mov edi, ebx
    movzx ebp, byte [ata_sector_count]

.ata_sector_loop:
    ; Wait for DRQ for each sector
    mov ecx, 2000000
.ata_wait:
    mov edx, 0x1F7
    in al, dx
    test al, 0x80           ; BSY set?
    jnz .ata_wait_next
    test al, 0x01           ; ERR set?
    jnz .ata_error
    test al, 0x08           ; DRQ set?
    jnz .ata_data_ready

.ata_wait_next:
    dec ecx
    jnz .ata_wait
    mov byte [ata_last_status], al
    jmp .ata_error

.ata_data_ready:
    mov edx, 0x1F0
    mov ecx, 256            ; 256 words = 512 bytes
    cld
    rep insw

    dec ebp
    jnz .ata_sector_loop
    
    clc                     ; success
    jmp .ata_return
    
.ata_error:
    mov byte [ata_last_status], al
    cmp byte [ata_retries], 0
    je .ata_fail
    
    dec byte [ata_retries]
    jmp .ata_read_try
    
.ata_fail:
    stc                     ; error
    
.ata_return:
    pop edi
    pop esi
    pop ebp
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

ata_write_sectors_32:
    ; Same concept but writes to disk
    ; For now, returns error (can implement similar to read)
    ; Input: same as ata_read
    ; Output: CF set (not implemented)
    
    stc
    ret

; ========== WRAPPER FUNCTIONS FOR OLD DISK API ==========
; These maintain backward compatibility with FS code that uses CHS addressing

disk_read_chs:
    ; Wrapper: takes 16-bit CHS parameters and calls ATA driver
    ; Input:  AL = count, CL = sector, CH = cylinder, DH = head
    ;         ES:BX = buffer (in real-mode segment terms)
    ; Output: CF clear on success, set on error
    
    ; Convert ES to selector 0x10 for protected mode
    mov ax, 0x10
        mov al, 'M'
        call console_putc_32
    call ata_read_sectors_32
    ret

disk_write_chs:
    ; Wrapper: takes 16-bit CHS parameters and calls ATA driver
    ; Input: same as disk_read_chs
    ; Output: CF clear on success, set on error
    
    mov ax, 0x10
    mov es, ax
    call ata_write_sectors_32
    ret

[BITS 16]

preload_boot_assets_16:
    ; Program table -> PROG_TABLE_ADDR
    mov bx, PROG_TABLE_ADDR
    mov si, FS_TABLE_SECTOR
    mov al, 1
    call bios_read_linear_sectors_16
    jc .table_fail

    ; Validate CFS1 header and count.
    cmp byte [PROG_TABLE_ADDR + 0], 'C'
    jne .table_fail
    cmp byte [PROG_TABLE_ADDR + 1], 'F'
    jne .table_fail
    cmp byte [PROG_TABLE_ADDR + 2], 'S'
    jne .table_fail
    cmp byte [PROG_TABLE_ADDR + 3], '1'
    jne .table_fail

    mov al, [PROG_TABLE_ADDR + 4]
    cmp al, PROG_TABLE_MAX_ENTRIES
    ja .table_fail
    mov [prog_table_count], al
    mov byte [prog_table_loaded], 1
    jmp short .table_done ; jump unconditionally

.table_fail:
    mov byte [prog_table_loaded], 0

.table_done:

    ; Shell -> SHELL_LOAD_ADDR
    mov ax, (SHELL_LOAD_ADDR >> 4)
    mov es, ax
    xor bx, bx
    mov al, [BOOT_KSECT_OFF]
    add al, 2
    xor ah, ah
    mov si, ax
    mov al, SHELL_SECTORS
    call bios_read_linear_sectors_16
    jc .shell_fail

    mov byte [boot_preload_ok], 1
    clc
    ret

.shell_fail:
    mov byte [boot_preload_ok], 0
    stc
    ret

; bios_read_linear_sectors_16
; Input: SI=start logical sector (1-based), AL=count, ES:BX=dest (ES assumed 0)
; Output: CF clear success, set on failure
bios_read_linear_sectors_16:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov di, ax
    and di, 0x00FF

.next_sector:
    cmp di, 0
    je .ok

    ; Convert logical sector to CHS (18 spt, 2 heads => 36 sectors/cylinder)
    mov ax, si
    dec ax
    xor dx, dx
    mov cx, 36
    div cx                  ; AX=cyl, DX=remainder in cylinder

    mov ch, al              ; cylinder (low 8 bits)

    mov ax, dx
    xor dx, dx
    mov cx, 18
    div cx                  ; AX=head, DX=sector_index

    mov dh, al              ; head
    mov cl, dl
    inc cl                  ; 1-based sector

    mov dl, [BOOT_DRIVE_OFF]
    mov ah, 0x02
    mov al, 1
    int 0x13
    jc .io_fail

    add bx, 512
    inc si
    dec di
    jmp .next_sector

.ok:
    clc
    jmp .done

.io_fail:
    stc

.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

bios_putc_16:
    push ax
    mov ah, 0x0E
    int 0x10
    pop ax
    ret

bios_puts_16:
    ; Input: DS:SI -> zero-terminated string
.loop:
    lodsb
    test al, al
    jz .done
    call bios_putc_16
    jmp .loop
.done:
    ret

; Boot-time helpers (invoked before protected-mode switch)
enable_a20:
    in al, 0x92
    or al, 0x02
    out 0x92, al
    ret

load_boot_gdt:
    lgdt [gdt_descriptor]
    ret

[BITS 32]

; Compatibility wrappers for existing call sites
console_putc:
    jmp console_putc_32

console_puts:
    jmp console_puts_32

console_newline:
    jmp console_newline_32

console_clear:
    jmp console_clear_32

kbd_getc:
    jmp kbd_getc_32

; ========== TIMER DRIVER (replaces INT 0x15) ==========
; Simple busy-loop based delay

delay_ms:
    ; Input: EAX = milliseconds
    ; Crude busy-loop; spin for approximately N milliseconds
    
    push ebx
    push ecx
    
    ; Each iteration ~1 microsecond, so multiply by 1000
    mov ebx, eax
    shl ebx, 10             ; approximately * 1000
    
.delay_loop:
    dec ebx
    jnz .delay_loop
    
    pop ecx
    pop ebx
    ret

; ========== SCRATCH DATA FOR DRIVERS ==========
ata_sector_count: db 0
ata_sector_num: db 0
ata_cylinder: db 0
ata_head: db 0
ata_lba: dd 0
ata_buffer_offset: dd 0
ata_buffer_segment: dw 0
ata_retries: db 0
ata_last_status: db 0

program_table_fallback_blob:
    db 'C', 'F', 'S', '1'
    db 11
    times 11 db 0

    db 'l', 's', 0, 0, 0, 0, 0, 0
    db LS_SECTOR
    db LS_SECTORS
    dw 0xA000
    dw 0x0000
    db 1, 0

    db 'i', 'n', 'f', 'o', 0, 0, 0, 0
    db INFO_SECTOR
    db INFO_SECTORS
    dw 0xA000
    dw 0x0000
    db 1, 0

    db 's', 't', 'a', 't', 0, 0, 0, 0
    db STAT_SECTOR
    db STAT_SECTORS
    dw 0xA000
    dw 0x0000
    db 1, 0

    db 'g', 'r', 'e', 'e', 't', 0, 0, 0
    db GREET_SECTOR
    db GREET_SECTORS
    dw 0xA000
    dw 0x0000
    db 1, 0

    db 'c', 'a', 't', 0, 0, 0, 0, 0
    db CAT_SECTOR
    db CAT_SECTORS
    dw 0xA000
    dw 0x0000
    db 1, 0

    db 't', 'o', 'd', 'o', 0, 0, 0, 0
    db TODO_SECTOR
    db TODO_SECTORS
    dw 0x0000
    dw 0x0000
    db 2, 0

    db 'd', 'i', 'r', 0, 0, 0, 0, 0
    db DIR_SECTOR
    db DIR_SECTORS
    dw 0xA000
    dw 0x0000
    db 1, 0

    db 'w', 'r', 'i', 't', 'e', 0, 0, 0
    db WRITE_SECTOR
    db WRITE_SECTORS
    dw 0xA000
    dw 0x0000
    db 1, 0

    db 'l', 's', 'v', 0, 0, 0, 0, 0
    db DIR_SECTOR
    db DIR_SECTORS
    dw 0xA000
    dw 0x0000
    db 1, 0

    db 'i', 'm', 'g', 0, 0, 0, 0, 0
    db IMG_SECTOR
    db IMG_SECTORS
    dw 0xA000
    dw 0x0000
    db 1, 0

    db 's', 'p', 'h', 'e', 'r', 'e', 0, 0
    db SPHERE_SECTOR
    db SPHERE_SECTORS
    dw 0xA000
    dw 0x0000
    db 1, 0

print_hex_nibble_32:
    and al, 0x0F
    cmp al, 9
    jbe .hex_digit
    add al, 7
.hex_digit:
    add al, '0'
    call console_putc_32
    ret

print_hex8_32:
    push eax
    mov ah, al
    shr al, 4
    call print_hex_nibble_32
    mov al, ah
    and al, 0x0F
    call print_hex_nibble_32
    pop eax
    ret

show_boot_logo:
    call console_newline
    call console_newline
    call console_newline
    mov si, logo_line_01
    call console_puts_logo
    call console_newline
    mov si, logo_line_02
    call console_puts_logo
    call console_newline
    mov si, logo_line_03
    call console_puts_logo
    call console_newline
    mov si, logo_line_04
    call console_puts_logo
    call console_newline
    mov si, logo_line_05
    call console_puts_logo
    call console_newline
    mov si, logo_line_06
    call console_puts_logo
    call console_newline
    mov si, logo_line_07
    call console_puts_logo
    call console_newline
    mov si, logo_line_08
    call console_puts_logo
    call console_newline
    mov si, logo_line_09
    call console_puts_logo
    call console_newline
    mov si, logo_line_10
    call console_puts_logo
    call console_newline
    mov si, logo_line_11
    call console_puts_logo
    call console_newline
    mov si, logo_line_12
    call console_puts_logo
    call console_newline
    mov si, logo_line_13
    call console_puts_logo
    call console_newline
    mov si, logo_line_14
    call console_puts_logo
    call console_newline
    mov si, logo_line_15
    call console_puts_logo
    call console_newline
    call console_newline
    call console_puts_version
    call console_newline
    ret

; console_puts_logo
; Input: DS:SI = null-terminated logo row with '#'(on) and ' '(off)
; Renders '#' as CP437 full block (0xDB)
console_puts_logo:
.logo_loop:
    lodsb ; load byte from DS:SI into AL
    cmp al, 0
    je .logo_done ; jump if equal/zero
    cmp al, '#'
    jne .logo_emit ; jump if not equal/non-zero
    mov al, 0xDB
.logo_emit:
    call console_putc
    jmp .logo_loop ; jump unconditionally
.logo_done:
    ret

; console_puts_version
; Displays boot and kernel version info for debugging
console_puts_version:
    mov si, welcome_msg
    call console_puts
    ret


; delay_5s
; BIOS wait: CX:DX microseconds = 5,000,000 (0x004C4B40)
delay_5s:
    mov ah, 0x86
    mov cx, 0x004C
    mov dx, 0x4B40
    ; stub (was int 0x15, now unused)
    ret

; ========== IDT SETUP FOR PROTECTED MODE ==========
; Creates an IDT with gate descriptor for syscall (int 0x80)
; Also hooks IRQ1 (keyboard) and IRQ14 (disk) handlers

install_idt_32:
    cli
    
    ; Initialize all IDT entries to zero
    xor eax, eax
    mov edi, idt_table
    mov ecx, 256 * 8        ; 256 gates * 8 bytes each
    cld
    rep stosb
    
    ; Gate 0x80 (syscall) -> syscall_handler
    mov eax, syscall_handler_32
    mov [idt_table + 0x80*8 + 0], ax      ; offset low
    mov [idt_table + 0x80*8 + 2], word 0x0008  ; code segment selector
    mov [idt_table + 0x80*8 + 4], word 0xEE00  ; gate type = interrupt, DPL=3 (user), present
    shr eax, 16
    mov [idt_table + 0x80*8 + 6], ax      ; offset high
    
    ; Gate 0x21 (IRQ1 = keyboard) -> keyboard_handler_32
    mov eax, keyboard_irq_handler
    mov [idt_table + 0x21*8 + 0], ax
    mov [idt_table + 0x21*8 + 2], word 0x0008
    mov [idt_table + 0x21*8 + 4], word 0xEE00
    shr eax, 16
    mov [idt_table + 0x21*8 + 6], ax
    
    ; Gate 0x2E (IRQ14 = ATA disk) -> disk_irq_handler
    mov eax, disk_irq_handler
    mov [idt_table + 0x2E*8 + 0], ax
    mov [idt_table + 0x2E*8 + 2], word 0x0008
    mov [idt_table + 0x2E*8 + 4], word 0xEE00
    shr eax, 16
    mov [idt_table + 0x2E*8 + 6], ax
    
    ; Load IDT
    lidt [idt_descriptor]
    
    ; Program PIC (programmable interrupt controller) to remap IRQs
    ; IRQ0-7 -> INT 0x20-0x27
    ; IRQ8-15 -> INT 0x28-0x2F
    mov al, 0x11            ; ICW1: begin init sequence
    out 0x20, al            ; master PIC
    out 0xA0, al            ; slave PIC
    
    mov al, 0x20            ; ICW2: master offset
    out 0x21, al
    mov al, 0x28            ; ICW2: slave offset
    out 0xA1, al
    
    mov al, 0x04            ; ICW3: master has slave on IRQ2
    out 0x21, al
    mov al, 0x02            ; ICW3: slave is on IRQ2 of master
    out 0xA1, al
    
    mov al, 0x01            ; ICW4: x86 mode
    out 0x21, al
    out 0xA1, al
    
    ; Unmask IRQ1 (keyboard) and IRQ14 (disk) in PIC
    mov al, 0xFB            ; mask all except IRQ1,2
    out 0x21, al
    mov al, 0xBF            ; mask all except IRQ6 (which unmasks IRQ14 and below)
    out 0xA1, al
    
    sti
    ret

; Placeholder IRQ handlers (will be filled by interrupt)
keyboard_irq_handler:
    ; Read key from keyboard and send EOI
    mov al, 0x20
    out 0x20, al            ; EOI to master PIC
    iret

disk_irq_handler:
    ; Disk interrupt - just send EOI for now
    mov al, 0x20
    out 0xA0, al            ; EOI to slave PIC
    mov al, 0x20
    out 0x20, al            ; EOI to master PIC
    iret

; ================== SYSCALL DISPATCHER (32-BIT) ==================
; Kernel's main entry point for all user syscalls (INT 0x80)
; Every program request (I/O, filesystem, execution) routes through here
;
; Syscall Interface:
; - User code: mov ah, SYS_XXX / mov [other regs] = args / int 0x80
; - Kernel receives INT 0x80, dispatches based on AH value
; - Syscall returns with AH = status, other regs = results
; - All registers preserved except: AH (status), CX (byte count for some calls)
;
; Status codes are syscall-specific:
; - 0x00: Success
; - 0x01: Not found / File error
; - 0x02: I/O error / Already exists
; - 0xFF: Unknown syscall
syscall_handler_32:
    pushad                  ; save all 32-bit registers
    push ds                 ; save segment registers
    push es

    ; ================== DISPATCH TABLE (17 SYSCALLS) ==================
    ; Each syscall code maps to a handler function
    
    cmp ah, SYS_PUTC        ; 0x01: output single character
    je .sys_putc

    cmp ah, SYS_PUTS        ; 0x02: output null-terminated string
    je .sys_puts

    cmp ah, SYS_NEWLINE     ; 0x03: output CR+LF
    je .sys_newline

    cmp ah, SYS_GETC        ; 0x04: read single keystroke
    je .sys_getc

    cmp ah, SYS_CLEAR       ; 0x05: clear screen
    je .sys_clear

    cmp ah, SYS_RUN         ; 0x06: load and execute program
    je .sys_run

    cmp ah, SYS_READ_RAW    ; 0x07: read sectors from disk directly
    je .sys_read_raw

    cmp ah, SYS_WRITE_RAW   ; 0x08: write sectors to disk directly
    je .sys_write_raw

    cmp ah, SYS_FS_READ     ; 0x09: read file from InodeFS
    je .sys_fs_read

    cmp ah, SYS_FS_WRITE    ; 0x0A: write/append file to InodeFS
    je .sys_fs_write

    cmp ah, SYS_FS_LIST     ; 0x0B: list files in directory
    je .sys_fs_list

    cmp ah, SYS_FS_DELETE   ; 0x0C: delete file/directory from InodeFS
    je .sys_fs_delete

    cmp ah, SYS_FS_MKDIR    ; 0x0D: create directory in InodeFS
    je .sys_fs_mkdir

    cmp ah, SYS_FS_CHDIR    ; 0x0E: change current working directory
    je .sys_fs_chdir

    cmp ah, SYS_REBOOT      ; 0x0F: reboot system
    je .sys_reboot

    cmp ah, SYS_SET_VIDEO_MODE ; 0x10: set BIOS video mode (AL=0x03 text, AL=0x13 graphics)
    je .sys_set_video_mode

    cmp ah, SYS_PRESENT_FRAMEBUFFER ; 0x11: copy 320x200x8bpp backbuffer to VGA memory
    je .sys_present_framebuffer

    ; Unknown or unsupported syscall code
    mov ah, 0xFF            ; return error: unknown syscall
    jmp .done

; ================== SYSCALL HANDLERS ==================
; Each handler implements one service
; On exit to .done: restore registers and iret to caller

.sys_putc:
    call console_putc_32    ; print character in AL to video memory
    xor eax, eax            ; EAX = 0: success
    jmp .done

.sys_puts:
    call console_puts_32    ; print string at DS:SI to video memory
    xor eax, eax            ; EAX = 0: success
    jmp .done

.sys_newline:
    call console_newline_32 ; print CR+LF (0x0D, 0x0A)
    xor eax, eax            ; EAX = 0: success
    jmp .done

.sys_getc:
    call kbd_getc_32        ; poll keystroke, return ASCII in AL
    jmp .done                ; AH set by kbd_getc_32

.sys_clear:
    call console_clear_32   ; clear video memory, reset cursor
    xor eax, eax            ; EAX = 0: success
    jmp .done

.sys_run:
    call run_named_program  ; search program table, load, execute (DS:SI = name)
    jmp .done                ; AH = status from run_named_program (0=success, 1=not found, 2=load error, 3=unavailable)

.sys_read_raw:
    call ata_read_sectors_32 ; read sectors via ATA PIO (AL=count, CL=sector, ES:BX=buffer)
    jc .sys_read_raw_fail   ; CF=1 on error
    xor eax, eax            ; CF=0: success, EAX=0
    jmp .done

.sys_read_raw_fail:
    mov eax, 2              ; return error code 2 (I/O error)
    jmp .done

.sys_write_raw:
    call ata_write_sectors_32 ; write sectors via ATA PIO
    jc .sys_write_raw_fail  ; CF=1 on error
    xor eax, eax            ; CF=0: success, EAX=0
    jmp .done

.sys_write_raw_fail:
    mov eax, 2              ; return error code 2 (I/O error)
    jmp .done

.sys_fs_read:
    ; Read entire file from InodeFS by pathname
    ; Input: DS:SI = file path, ES:BX = output buffer
    ; Output: AH = status (0=success, 1=not found, 2=error), CX = bytes read
    call fs_read_file_by_name
    jmp .done_keep_cx

.sys_fs_write:
    ; Write/append to file in InodeFS
    ; Input: DS:SI = file path, ES:BX = data buffer, CX = bytes to write
    ; Output: AH = status (0=success, 1=error, 2=full)
    call fs_write_file_by_name
    jmp .done

.sys_fs_list:
    ; List files in current directory
    ; Input: CX = which entry to return (0, 1, 2, ...)
    ; Output: AH = status, CX = byte count, ES:BX = entry info
    call fs_list_file_by_ordinal
    jmp .done_keep_cx

.sys_fs_delete:
    ; Delete file or directory from InodeFS
    ; Input: DS:SI = file path
    ; Output: AH = status (0=success, 1=not found, 2=error)
    call fs_delete_by_path
    jmp .done

.sys_fs_mkdir:
    ; Create new directory in InodeFS
    ; Input: DS:SI = directory path
    ; Output: AH = status (0=success, 1=already exists, 2=error)
    call fs_mkdir_by_path
    jmp .done

.sys_fs_chdir:
    ; Change current working directory
    ; Input: DS:SI = directory path
    ; Output: AH = status (0=success, 1=not found, 2=error)
    call fs_chdir_by_path
    jmp .done

.sys_reboot:
    jmp kernel_reboot

.sys_set_video_mode:
    ; Set hardware video mode (0x03 text mode, 0x13 graphics).
    ; For now, just set text mode via direct hardware
    ; This can be extended with graphics mode setup
    cmp al, 0x03
    je .set_text_mode
    cmp al, 0x13
    je .set_graphics_mode
    mov eax, 1              ; error for invalid mode
    jmp .done
    
.set_text_mode:
    ; Already in text mode, just clear
    call console_clear_32
    xor eax, eax
    jmp .done
    
.set_graphics_mode:
    ; Not implemented for now (would require VGA mode switch)
    mov eax, 1
    jmp .done

.sys_present_framebuffer:
    ; Blit one full Mode 13h frame from caller RAM to VGA memory.
    ; Input: DS:SI = source backbuffer pointer (expects 64,000 bytes).
    ; Layout: 320 * 200 * 1 byte-per-pixel = 64,000 bytes.
    ; Output: EAX = 0 on success.
    cld                     ; ensure forward string copy direction.
    mov eax, 0xA0000       ; VGA linear framebuffer for mode 13h (physical address). 
    mov edi, eax
    mov esi, esi            ; source already in ESI
    mov ecx, 64000          ; total byte count for a full frame.
    rep movsb               ; copy DS:ESI -> EDI, ECX bytes.
    xor eax, eax            ; report success to caller.
    jmp .done               ; return via normal register-restore path.

.done:
    ; Restore all registers and return to caller
    ; By this point, EAX contains the syscall result/status
    mov [syscall_ret_eax], eax
    pop es                  ; restore ES
    pop ds                  ; restore DS
    popad                   ; restore caller registers
    mov eax, [syscall_ret_eax]
    iret                    ; return to caller (restores EIP, CS, and flags)

.done_keep_cx:
    ; Variant epilogue for syscalls that return result in ECX.
    ; Preserve ECX by restoring it at the end
    mov [syscall_ret_eax], eax
    mov [syscall_ret_ecx], ecx
    pop es
    pop ds
    popad                   ; restore all registers
    mov eax, [syscall_ret_eax]
    mov ecx, [syscall_ret_ecx]
    iret

syscall_ret_eax: dd 0
syscall_ret_ecx: dd 0

; ==================== DISK I/O (BIOS-BACKED) ====================
; Uses BIOS INT 0x13 to read/write sectors
; Handles CHS (Cylinder-Head-Sector) addressing on floppy/hard disk


; lba_to_chs
; Input: CL = logical sector (1-based)
; Output: CH = cylinder, DH = head, CL = sector (1-based)
; Uses: AX, DX
lba_to_chs:
    mov ax, 0x10
    mov al, cl
    dec al                          ; convert to zero-based LBA

    xor ah, ah
    mov dl, 36                      ; sectors per cylinder (18*2)
    div dl                          ; AL=cylinder, AH=remainder in cylinder
    mov ch, al

    mov al, ah
    xor ah, ah
    mov dl, 18                      ; sectors per head/track
    div dl                          ; AL=head, AH=sector index
    mov dh, al
    mov cl, ah
    inc cl                          ; back to 1-based sector
    ret


; str_eq
; Input:  DS:SI = string A, DS:DI = string B
; Output: AL = 1 if equal, 0 if not
; Clobbers: AL, BL
str_eq:
.eq_loop:
    mov al, [si]
    mov bl, [di]
    cmp al, bl
    jne .no ; jump if not equal/non-zero
    cmp al, 0
    je .yes ; jump if equal/zero
    inc si
    inc di
    jmp .eq_loop ; jump unconditionally
.yes:
    mov al, 1
    ret
.no:
    mov al, 0
    ret


; str_startswith
; Input:  DS:SI = full string, DS:DI = prefix
; Output: AL = 1 if SI starts with DI, else 0
; Clobbers: AL, BL
str_startswith:
.sw_loop:
    mov al, [di]
    cmp al, 0
    je .yes ; jump if equal/zero
    mov bl, [si]
    cmp bl, al
    jne .no ; jump if not equal/non-zero
    inc si
    inc di
    jmp .sw_loop ; jump unconditionally
.yes:
    mov al, 1
    ret
.no:
    mov al, 0
    ret


launch_shell:
    ; If shell was preloaded from boot drive in real mode, run it directly.
    cmp byte [boot_preload_ok], 1
    je .run_preloaded

    cmp byte [disk_available], 1
    jne .maybe_preloaded

    ; Load csh to SHELL_LOAD_ADDR
    mov eax, 0x10
    mov es, eax             ; ES = flat data selector
    mov ebx, SHELL_LOAD_ADDR

    mov al, SHELL_SECTORS   ; shell sector count from build
    mov ch, 0                 ; cylinder 0
    mov cl, [BOOT_KSECT_OFF]  ; kernel sectors from boot info
    add cl, 2                 ; shell starts after boot(1) + kernel
    mov dh, 0                 ; head 0

    call ata_read_sectors_32
    jc .load_fail

    ; Call shell at SHELL_LOAD_ADDR (32-bit near call via register)
    mov eax, SHELL_LOAD_ADDR
    call eax                ; run shell, return to kernel when shell does RET
    ret

.maybe_preloaded:
    ; Only jump to SHELL_LOAD_ADDR when we explicitly preloaded shell in real mode.
    cmp byte [boot_preload_ok], 1
    je .run_preloaded
    jmp .no_disk ; jump unconditionally

.run_preloaded:
    mov eax, SHELL_LOAD_ADDR
    call eax
    mov al, 3
    mov [rescue_reason], al
    ret

.load_fail:
    mov si, shell_load_fail_msg
    call console_puts_32
    mov si, ata_status_msg
    call console_puts_32
    mov al, [ata_last_status]
    call print_hex8_32
    call console_newline_32
    mov al, 1
    mov [rescue_reason], al
    ret

.no_disk:
    mov si, shell_disk_unavailable_msg
    call console_puts_32
    call console_newline_32
    mov al, 2
    mov [rescue_reason], al
    ret

; rescue_ui
; Minimal failure-mode interface when userspace shell is unavailable.
; Keys: R reboot, D diagnostics, K keyboard test, H halt
rescue_ui:
    call console_newline_32
    mov si, rescue_title_msg
    call console_puts_32
    call console_newline_32

    mov si, rescue_hint_msg
    call console_puts_32
    call console_newline_32

.menu:
    mov si, rescue_menu_msg
    call console_puts_32

    call kbd_getc_32
    mov bl, al
    call console_putc_32
    call console_newline_32

    cmp bl, 'r'
    je .do_reboot ; jump if equal/zero
    cmp bl, 'R'
    je .do_reboot ; jump if equal/zero

    cmp bl, 'd'
    je .do_diag ; jump if equal/zero
    cmp bl, 'D'
    je .do_diag ; jump if equal/zero

    cmp bl, 'k'
    je .do_kbd ; jump if equal/zero
    cmp bl, 'K'
    je .do_kbd ; jump if equal/zero

    cmp bl, 'h'
    je .do_halt ; jump if equal/zero
    cmp bl, 'H'
    je .do_halt ; jump if equal/zero

    mov si, rescue_badkey_msg
    call console_puts_32
    call console_newline_32
    jmp .menu ; jump unconditionally

.do_diag:
    call rescue_print_diag
    jmp .menu ; jump unconditionally

.do_kbd:
    call rescue_keyboard_test
    jmp .menu ; jump unconditionally

.do_reboot:
    jmp kernel_reboot

.do_halt:
    mov si, rescue_halt_msg
    call console_puts_32
    call console_newline_32
    jmp halt

rescue_print_diag:
    mov si, rescue_diag_prefix
    call console_puts_32

    mov al, [rescue_reason]
    call print_hex8_32

    mov si, rescue_diag_sep
    call console_puts_32
    mov al, [ata_last_status]
    call print_hex8_32

    mov si, rescue_diag_sep
    call console_puts_32
    mov al, [disk_available]
    call print_hex8_32

    mov si, rescue_diag_sep
    call console_puts_32
    mov al, [prog_table_loaded]
    call print_hex8_32

    mov si, rescue_diag_sep
    call console_puts_32
    mov al, [prog_table_count]
    call print_hex8_32

    call console_newline_32
    ret

rescue_keyboard_test:
    mov si, rescue_kbd_msg
    call console_puts_32
    call console_newline_32
.kt_loop:
    call kbd_getc_32
    cmp al, 27
    je .kt_done ; jump if equal/zero
    call console_putc_32
    jmp .kt_loop ; jump unconditionally
.kt_done:
    call console_newline_32
    ret

kernel_reboot:
    ; Reboot machine via CPU reset (stub: halt loop for now).
    cli
.reboot_halt:
    hlt
    jmp .reboot_halt ; jump unconditionally

; load_program_table
; Reads a tiny filesystem program table from FS_TABLE_SECTOR into PROG_TABLE_ADDR.
; Output: AH = 0 success, 1 read fail, 2 bad magic, 3 bad entry count, 4 bad layout
load_program_table:
    mov eax, 0x10
    mov es, eax             ; ES = flat data selector
    mov ebx, PROG_TABLE_ADDR
    mov al, 1
    mov ch, 0
    mov cl, FS_TABLE_SECTOR
    mov dh, 0
    call ata_read_sectors_32
    jc .read_fail

    cmp byte [PROG_TABLE_ADDR + 0], 'C'
    jne .bad_magic ; jump if not equal/non-zero
    cmp byte [PROG_TABLE_ADDR + 1], 'F'
    jne .bad_magic ; jump if not equal/non-zero
    cmp byte [PROG_TABLE_ADDR + 2], 'S'
    jne .bad_magic ; jump if not equal/non-zero
    cmp byte [PROG_TABLE_ADDR + 3], '1'
    jne .bad_magic ; jump if not equal/non-zero

    mov al, [PROG_TABLE_ADDR + 4]
    cmp al, PROG_TABLE_MAX_ENTRIES
    ja .bad_count
    mov [prog_table_count], al

    call validate_program_table_layout
    cmp ah, 0
    jne .bad_layout ; jump if not equal/non-zero

    mov byte [prog_table_loaded], 1
%if DEBUG
        mov si, debug_loaded_msg
        call console_puts_32
        mov al, [prog_table_count]
    cmp al, 10
    jb .dbg_one_digit
    mov al, '1'
    call console_putc_32
    mov al, [prog_table_count]
    sub al, 10
    add al, '0'
    call console_putc_32
    jmp .dbg_count_done ; jump unconditionally
.dbg_one_digit:
    add al, '0'
    call console_putc_32
.dbg_count_done:
        mov si, debug_newline
        call console_puts_32
%endif
    xor ah, ah
    ret

.read_fail:
    cmp byte [ata_last_status], 0xFF
    jne .read_fail_disk
    mov byte [disk_available], 0
    call load_program_table_fallback
    ret

.read_fail_disk:
    mov byte [prog_table_loaded], 0
    mov ah, 1
    ret

.bad_magic:
    cmp byte [kernel_boot_drive], 0x80
    jae .bad_magic_fail
    mov byte [disk_available], 0
    call load_program_table_fallback
    ret

.bad_magic_fail:
    mov byte [prog_table_loaded], 0
    mov ah, 2
    ret

.bad_count:
    cmp byte [kernel_boot_drive], 0x80
    jae .bad_count_fail
    mov byte [disk_available], 0
    call load_program_table_fallback
    ret

.bad_count_fail:
    mov byte [prog_table_loaded], 0
    mov ah, 3
    ret

.bad_layout:
    cmp byte [kernel_boot_drive], 0x80
    jae .bad_layout_fail
    mov byte [disk_available], 0
    call load_program_table_fallback
    ret

.bad_layout_fail:
    mov byte [prog_table_loaded], 0
    mov ah, 4
    ret

; validate_program_table_layout
; Ensures every entry has valid start/count and does not overlap FS table sector.
; Output: AH = 0 valid, 4 invalid
validate_program_table_layout:
    mov byte [pt_index], 0

.v_loop:
    mov bl, [pt_index]
    cmp bl, [prog_table_count]
    jae .v_ok

    mov ax, 0x10
    mov al, bl
    shl ax, 4
    mov di, PROG_TABLE_ADDR + 16
    add di, ax

    cmp byte [di + 14], 4
    je .v_large

    mov al, [di + 8]                  ; start sector
    mov ah, [di + 9]                  ; sector count

    cmp al, 1
    jb .v_bad
    cmp ah, 0
    je .v_bad ; jump if equal/zero

    mov bl, al
    add bl, ah
    jc .v_bad
    dec bl                            ; end sector

    mov dl, FS_TABLE_SECTOR
    cmp dl, al
    jb .v_next
    cmp dl, bl
    jbe .v_bad

    jmp .v_next

.v_large:
    mov ax, [di + 8]                  ; start sector (word)
    mov cx, [di + 10]                 ; sector count (word)

    cmp ax, 1
    jb .v_bad
    cmp cx, 0
    je .v_bad

    mov bx, ax
    add bx, cx
    jc .v_bad
    dec bx                            ; end sector

    mov dl, FS_TABLE_SECTOR
    movzx dx, dl
    cmp dx, ax
    jb .v_next
    cmp dx, bx
    jbe .v_bad

.v_next:
    inc byte [pt_index]
    jmp .v_loop ; jump unconditionally

.v_ok:
    xor ah, ah
    ret

.v_bad:
    mov ah, 4
    ret

; load_program_table_fallback
; Builds a CFS1 table in memory when ATA ports are unavailable (status 0xFF).
; Output: AH = 0 success, 2 bad magic, 3 bad count, 4 bad layout
load_program_table_fallback:
    mov esi, program_table_fallback_blob
    mov edi, PROG_TABLE_ADDR
    mov ecx, 16 + (11 * 16)
.ptf_copy:
    mov al, [esi]
    mov [edi], al
    inc esi
    inc edi
    dec ecx
    jnz .ptf_copy

    cmp byte [PROG_TABLE_ADDR + 0], 'C'
    jne .ptf_bad_magic
    cmp byte [PROG_TABLE_ADDR + 1], 'F'
    jne .ptf_bad_magic
    cmp byte [PROG_TABLE_ADDR + 2], 'S'
    jne .ptf_bad_magic
    cmp byte [PROG_TABLE_ADDR + 3], '1'
    jne .ptf_bad_magic

    mov al, [PROG_TABLE_ADDR + 4]
    cmp al, PROG_TABLE_MAX_ENTRIES
    ja .ptf_bad_count
    mov [prog_table_count], al

    call validate_program_table_layout
    cmp ah, 0
    jne .ptf_bad_layout

    mov byte [prog_table_loaded], 1
    xor ah, ah
    ret

.ptf_bad_magic:
    mov byte [prog_table_loaded], 0
    mov ah, 2
    ret

.ptf_bad_count:
    mov byte [prog_table_loaded], 0
    mov ah, 3
    ret

.ptf_bad_layout:
    mov byte [prog_table_loaded], 0
    mov ah, 4
    ret

; load_linear_sectors_32
; Input:
;   EAX = start logical sector (1-based)
;   EDX = sector count (1..65535)
;   ES:EBX = destination buffer
; Output: CF clear on success, set on failure
load_linear_sectors_32:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi

    mov esi, eax
    mov edi, edx

.ll_loop:
    cmp edi, 0
    je .ll_ok

    mov eax, esi
    dec eax
    xor edx, edx
    mov ecx, 36
    div ecx

    mov ch, al
    mov eax, edx
    xor edx, edx
    mov ecx, 18
    div ecx

    mov dh, al
    mov cl, dl
    inc cl

    mov eax, edi
    cmp eax, 255
    jbe .ll_chunk_ready
    mov eax, 255

.ll_chunk_ready:
    mov dl, al
    call ata_read_sectors_32
    jc .ll_fail

    movzx ecx, dl
    shl ecx, 9
    add ebx, ecx

    movzx ecx, dl
    add esi, ecx
    sub edi, ecx
    jmp .ll_loop

.ll_ok:
    clc
    jmp .ll_done

.ll_fail:
    stc

.ll_done:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; run_named_program
; Input: DS:SI = null-terminated program name
; Output: AH = status (0=ok, 1=unknown name, 2=load fail, 3=fs unavailable)
run_named_program:
    cmp byte [prog_table_loaded], 1
    jne .fs_unavailable ; jump if not equal/non-zero

    mov [run_name_ptr], si
    xor ebx, ebx

    mov si, [run_name_ptr]

.search_loop:
    cmp bl, [prog_table_count]
    jae .unknown

    ; DI = PROG_TABLE_ADDR + 16 + (index * PROG_ENTRY_SIZE)
    mov eax, 0x10
    mov al, bl
    shl eax, 4
    mov edi, PROG_TABLE_ADDR + 16
    add edi, eax

    mov si, [run_name_ptr]
    push ebx
    call str_eq_progname
    pop ebx
    cmp al, 1
    je .found

    inc bl
    jmp .search_loop

.found:
    ; Recompute entry pointer in DI
    mov eax, 0x10
    mov al, bl
    shl eax, 4
    mov edi, PROG_TABLE_ADDR + 16
    add edi, eax

    cmp byte [edi + 14], 1
    je .run_small
    cmp byte [edi + 14], 4
    je .run_large
    jmp .unknown

.run_small:
    mov ax, 0x10
    mov es, ax              ; ES = flat data selector
    mov ebx, [edi + 10]     ; load_offset
    mov al, [edi + 9]       ; sector count
    mov ch, 0
    mov cl, [edi + 8]       ; start sector
    mov dh, 0
    push edi
    call ata_read_sectors_32
    pop edi
    jc .load_fail

    ; Call program entry point via register (32-bit)
    mov eax, [edi + 10]     ; load offset
    add eax, [edi + 12]     ; add entry offset
    call eax                ; execute program

    xor ah, ah
    ret

.run_large:
    mov ax, 0x10
    mov es, ax
    mov ebx, [edi + 12]         ; load_offset
    movzx eax, word [edi + 8]   ; start sector (word)
    movzx edx, word [edi + 10]  ; sector count (word)
    push edi
    call load_linear_sectors_32
    pop edi
    jc .load_fail

    mov eax, [edi + 12]         ; entry = load_offset for large entries
    call eax

    xor ah, ah
    ret

.unknown:
    mov ah, 1
    ret

.load_fail:
    mov ah, 2
    ret

.fs_unavailable:
    mov ah, 3
    ret

; str_eq_progname
; Compare a shell command name against an 8-byte program-table name field.
; Input: DS:SI = null-terminated user name, DS:DI = table name[8]
; Output: AL = 1 match, 0 mismatch
str_eq_progname:
    push cx
    mov cx, 8

.cmp_loop:
    mov al, [si]
    mov bl, [di]

    cmp al, 0
    je .input_ended

    cmp al, bl
    jne .no

    inc si
    inc di
    loop .cmp_loop

    ; Consumed 8 chars from the table field: input must end here.
    cmp byte [si], 0
    jne .no
    jmp .yes

.input_ended:
    cmp bl, 0
    jne .no

.yes:
    mov al, 1
    pop cx
    ret

.no:
    mov al, 0
    pop cx
    ret

; -----------------------------
; InodeFS core helpers
; -----------------------------

; fs_mount_or_format
; Ensures the writable inode filesystem is present.
; If magic is missing, formats a fresh empty filesystem.
fs_mount_or_format:
    mov byte [fs_inode_ready], 0
    mov byte [fs_cwd_inode], INFS_ROOT_INODE

    cmp byte [disk_available], 1
    jne .no_disk

    mov ax, 0
    mov es, ax
    mov bx, INFS_SUPER_BUF
    mov al, 1
    mov ch, 0
    mov cl, INFS_SUPER_SECTOR
    mov dh, 0
    call disk_read_chs
    jc .format

    cmp byte [INFS_SUPER_BUF + 0], 'I'
    jne .format ; jump if not equal/non-zero
    cmp byte [INFS_SUPER_BUF + 1], 'N'
    jne .format ; jump if not equal/non-zero
    cmp byte [INFS_SUPER_BUF + 2], 'D'
    jne .format ; jump if not equal/non-zero
    cmp byte [INFS_SUPER_BUF + 3], '2'
    jne .format ; jump if not equal/non-zero

    mov byte [fs_inode_ready], 1
    ret

.format:
    call fs_format
    cmp ah, 0
    je .format_ok
    mov si, fs_mount_fail_msg
    call console_puts_32
    call console_newline_32
.format_ok:
    ret

.no_disk:
    mov si, fs_no_disk_msg
    call console_puts_32
    call console_newline_32
    ret

; fs_format
; Writes empty superblock/inode table/bitmap to disk.
; Output: AH=0 success, AH=2 disk error
fs_format:
    ; Clear superblock buffer
    mov ax, 0
    mov es, ax
    mov di, INFS_SUPER_BUF
    mov cx, 512
    xor al, al
    rep stosb

    ; Fill superblock header metadata.
    mov byte [INFS_SUPER_BUF + 0], 'I'
    mov byte [INFS_SUPER_BUF + 1], 'N'
    mov byte [INFS_SUPER_BUF + 2], 'D'
    mov byte [INFS_SUPER_BUF + 3], '2'
    mov byte [INFS_SUPER_BUF + 4], 2                      ; format version
    mov byte [INFS_SUPER_BUF + 5], INFS_MAX_INODES
    mov byte [INFS_SUPER_BUF + 6], INFS_DATA_START_SECTOR
    mov byte [INFS_SUPER_BUF + 7], INFS_MAX_BLOCKS

    mov bx, INFS_SUPER_BUF
    mov al, 1
    mov ch, 0
    mov cl, INFS_SUPER_SECTOR
    mov dh, 0
    call disk_write_chs
    jc .io_fail

    ; Clear inode table sector and create root directory inode at index 0.
    mov di, INFS_INODE_BUF
    mov cx, 512
    xor al, al
    rep stosb

    mov byte [INFS_INODE_BUF + INFS_OFF_USED], 1
    mov byte [INFS_INODE_BUF + INFS_OFF_TYPE], INFS_TYPE_DIR
    mov word [INFS_INODE_BUF + INFS_OFF_SIZE], 0
    mov byte [INFS_INODE_BUF + INFS_OFF_START], 0
    mov byte [INFS_INODE_BUF + INFS_OFF_COUNT], 0
    mov byte [INFS_INODE_BUF + INFS_OFF_PARENT], 0xFF
    mov byte [INFS_INODE_BUF + INFS_OFF_NAME + 0], '/'
    mov byte [INFS_INODE_BUF + INFS_OFF_NAME + 1], 0

    mov bx, INFS_INODE_BUF
    mov al, 1
    mov ch, 0
    mov cl, INFS_INODE_SECTOR
    mov dh, 0
    call disk_write_chs
    jc .io_fail

    ; Clear bitmap sector.
    mov di, INFS_BITMAP_BUF
    mov cx, 512
    xor al, al
    rep stosb

    mov bx, INFS_BITMAP_BUF
    mov al, 1
    mov ch, 0
    mov cl, INFS_BITMAP_SECTOR
    mov dh, 0
    call disk_write_chs
    jc .io_fail

    mov byte [fs_inode_ready], 1
    mov byte [fs_cwd_inode], INFS_ROOT_INODE
    xor ah, ah
    ret

.io_fail:
    mov byte [fs_inode_ready], 0
    mov ah, 2
    ret

; fs_find_inode_by_name
; Input: AL = parent inode index, DS:SI = leaf name (no '/').
; Output: AH=0 found (BL=index, DI=inode ptr), AH=1 not found, AH=2 io fail
fs_find_inode_by_name:
    cmp byte [fs_inode_ready], 1
    jne .io_fail ; jump if not equal/non-zero

    mov [fs_name_ptr], si
    mov [fs_parent_index], al

    call fs_load_inode_table
    jc .io_fail

    xor bl, bl
.scan_loop:
    cmp bl, INFS_MAX_INODES
    jae .not_found

    mov ax, 0x10
    mov al, bl
    shl ax, 4
    mov di, INFS_INODE_BUF
    add di, ax

    cmp byte [di + INFS_OFF_USED], 1
    jne .next ; jump if not equal/non-zero

    mov al, [fs_parent_index]
    cmp byte [di + INFS_OFF_PARENT], al
    jne .next ; jump if not equal/non-zero

    mov si, [fs_name_ptr]
    push bx
    push di
    call fs_name_eq_inode_name
    pop di
    pop bx
    cmp al, 1
    je .found ; jump if equal/zero

.next:
    inc bl
    jmp .scan_loop ; jump unconditionally

.found:
    mov al, bl
    xor ah, ah
    ret

.not_found:
    mov ah, 1
    ret

.io_fail:
    mov ah, 2
    ret

; fs_name_eq_inode_name
; Input: DS:SI = user name, DS:DI = inode record pointer
; Output: AL=1 equal, AL=0 not equal
fs_name_eq_inode_name:
    push si
    push di
    mov cx, INFS_NAME_LEN
.cmp_loop:
    mov al, [si]
    mov bl, [di + INFS_OFF_NAME]
    cmp al, bl
    jne .no ; jump if not equal/non-zero
    cmp al, 0
    je .yes ; jump if equal/zero
    inc si
    inc di
    dec cx
    jnz .cmp_loop ; jump if not equal/non-zero

    cmp byte [si], 0
    je .yes ; jump if equal/zero
.no:
    xor al, al
    pop di
    pop si
    ret
.yes:
    mov al, 1
    pop di
    pop si
    ret

; fs_list_file_by_ordinal
; Input: AL = 0-based ordinal among active entries inside directory DS:SI
;        ES:BX = output name buffer (>=11 bytes)
; Output: AH=0 ok, AH=1 end, AH=2 io
;         CX = file size on success
;         DL = inode type
fs_list_file_by_ordinal:
    cmp byte [fs_inode_ready], 1
    jne .io_fail ; jump if not equal/non-zero

    ; Preserve caller output buffer. Helper calls below clobber ES/BX.
    mov [fs_io_es], es
    mov [fs_io_bx], bx

    mov [fs_ordinal], al
    mov [fs_name_ptr], si

    call fs_load_inode_table
    jc .io_fail

    mov si, [fs_name_ptr]
    call fs_resolve_path_loaded
    cmp ah, 0
    jne .io_fail ; jump if not equal/non-zero

    mov [fs_parent_index], al

    xor bl, bl
.list_scan:
    cmp bl, INFS_MAX_INODES
    jae .list_end

    mov ax, 0x10
    mov al, bl
    shl ax, 4
    mov di, INFS_INODE_BUF
    add di, ax

    cmp byte [di + INFS_OFF_USED], 1
    jne .list_next ; jump if not equal/non-zero

    ; Ignore entries with empty names to avoid showing blank/corrupt files.
    cmp byte [di + INFS_OFF_NAME], 0
    je .list_next ; jump if equal/zero

    ; Ignore entries with non-printable leading characters.
    mov al, [di + INFS_OFF_NAME]
    cmp al, 32
    jb .list_next ; jump if below printable ASCII

    mov al, [fs_parent_index]
    cmp byte [di + INFS_OFF_PARENT], al
    jne .list_next ; jump if not equal/non-zero

    cmp byte [fs_ordinal], 0
    je .emit ; jump if equal/zero
    dec byte [fs_ordinal]

.list_next:
    inc bl
    jmp .list_scan ; jump unconditionally

.emit:
    mov bx, [fs_io_bx]
    mov ax, [fs_io_es]
    mov es, ax

    push di
    mov cx, INFS_NAME_LEN
    mov si, di
    add si, INFS_OFF_NAME
.copy_name:
    mov al, [si]
    mov [es:bx], al
    inc si
    inc bx
    cmp al, 0
    je .name_done ; jump if equal/zero
    loop .copy_name
    mov byte [es:bx], 0
.name_done:
    pop di

    mov cx, [di + INFS_OFF_SIZE]
    mov dl, [di + INFS_OFF_TYPE]
    xor ah, ah
    ret

.list_end:
    mov ah, 1
    ret
.io_fail:
    mov ah, 2
    ret

; fs_read_file_by_name
; Input: DS:SI = path
;        ES:BX = output buffer
; Output: AH=0 ok, AH=1 not found, AH=2 io
;         CX = bytes in file
fs_read_file_by_name:
    cmp byte [fs_inode_ready], 1
    jne .io_fail ; jump if not equal/non-zero

    ; Preserve caller output buffer (ES:BX). Helper calls below use ES/BX too.
    mov [fs_io_es], es
    mov [fs_io_bx], bx

    call fs_load_inode_table
    jc .io_fail

    call fs_resolve_path_loaded
    cmp ah, 0
    jne .not_found ; jump if not equal/non-zero

    cmp byte [di + INFS_OFF_TYPE], INFS_TYPE_DIR
    je .not_found ; jump if equal/zero

    mov cx, [di + INFS_OFF_SIZE]
    cmp cx, 0
    je .ok ; jump if equal/zero

    mov al, [di + INFS_OFF_COUNT]
    cmp al, 0
    je .ok ; jump if equal/zero

    push cx                 ; preserve byte count return value
    mov dl, [di + INFS_OFF_START]
    mov cl, INFS_DATA_START_SECTOR
    add cl, dl
    mov ch, 0
    mov dh, 0
    mov bx, [fs_io_bx]      ; restore destination offset provided by caller
    mov ax, [fs_io_es]
    mov es, ax              ; restore destination segment provided by caller
    mov al, [di + INFS_OFF_COUNT] ; restore sector count (AX load above clobbered AL)
    call disk_read_chs
    pop cx                  ; restore file size for syscall return
    jc .io_fail

    ; Decrypt file payload in-place after disk read.
    cmp cx, 0
    je .ok
    mov bx, [fs_io_bx]
    mov ax, [fs_io_es]
    mov es, ax
    mov dl, [di + INFS_OFF_START]
    call fs_crypto_xor_region

.ok:
    xor ah, ah
    ret

.not_found:
    mov ah, 1
    ret

.io_fail:
    mov ah, 2
    ret

; fs_write_file_by_name
; Input: DS:SI = path
;        ES:BX = input data buffer
;        CX = byte count
; Output: AH=0 ok, AH=1 no space, AH=2 io
fs_write_file_by_name:
    cmp byte [fs_inode_ready], 1
    jne .io_fail ; jump if not equal/non-zero

    mov [fs_path_ptr], si
    mov [fs_write_buf], bx
    mov [fs_write_len], cx

    call fs_load_inode_table
    jc .io_fail

    call fs_load_bitmap
    jc .io_fail

    ; Try resolve existing path.
    mov si, [fs_path_ptr]
    call fs_resolve_path_loaded
    cmp ah, 0
    je .existing ; jump if equal/zero

    ; Not found: resolve parent + leaf and allocate inode.
    mov si, [fs_path_ptr]
    call fs_split_parent_leaf_loaded
    cmp ah, 0
    jne .no_space ; jump if not equal/non-zero

    ; Reject if leaf already exists under parent.
    mov al, [fs_parent_index]
    mov si, fs_leaf_name
    call fs_find_inode_in_loaded
    cmp ah, 0
    je .no_space ; jump if equal/zero

    call fs_alloc_inode_loaded
    cmp ah, 0
    jne .no_space ; jump if not equal/non-zero

    ; Initialize new inode metadata.
    mov byte [di + INFS_OFF_USED], 1
    mov byte [di + INFS_OFF_TYPE], INFS_TYPE_FILE
    mov al, [fs_parent_index]
    mov byte [di + INFS_OFF_PARENT], al
    mov si, [fs_path_ptr]
    call fs_name_copy_path_tail_to_inode

    ; Mark .arc files as script type.
    call fs_leaf_is_arc
    cmp al, 1
    jne .inode_ready ; jump if not equal/non-zero
    mov byte [di + INFS_OFF_TYPE], INFS_TYPE_ARC
    jmp .inode_ready ; jump unconditionally

.existing:
    cmp byte [di + INFS_OFF_TYPE], INFS_TYPE_DIR
    je .no_space ; jump if equal/zero

.inode_ready:
    ; Free old allocation if present.
    mov dl, [di + INFS_OFF_START]
    mov dh, [di + INFS_OFF_COUNT]
    call fs_free_run_loaded

    mov word [di + INFS_OFF_SIZE], 0
    mov byte [di + INFS_OFF_START], 0
    mov byte [di + INFS_OFF_COUNT], 0

    mov ax, [fs_write_len]
    cmp ax, 0
    je .save_all ; jump if equal/zero

    add ax, 511
    shr ax, 9
    mov [fs_need_blocks], al

    mov al, [fs_need_blocks]
    call fs_alloc_run_loaded
    cmp ah, 0
    jne .no_space ; jump if not equal/non-zero

    mov [fs_start_block], al
    mov [di + INFS_OFF_START], al
    mov al, [fs_need_blocks]
    mov [di + INFS_OFF_COUNT], al

    ; Encrypt payload in caller buffer before writing to disk.
    mov bx, [fs_write_buf]
    mov ax, 0
    mov es, ax
    movzx cx, byte [fs_need_blocks]
    shl cx, 9
    mov dl, [fs_start_block]
    call fs_crypto_xor_region

    ; Write file payload blocks to disk.
    mov ax, 0
    mov es, ax
    mov bx, [fs_write_buf]
    mov al, [fs_need_blocks]
    mov ch, 0
    mov cl, INFS_DATA_START_SECTOR
    add cl, [fs_start_block]
    mov dh, 0
    call disk_write_chs
    pushf

    ; Restore plaintext back into caller buffer regardless of disk result.
    mov bx, [fs_write_buf]
    mov ax, 0
    mov es, ax
    movzx cx, byte [fs_need_blocks]
    shl cx, 9
    mov dl, [fs_start_block]
    call fs_crypto_xor_region

    popf
    jc .io_fail

    mov ax, [fs_write_len]
    mov [di + INFS_OFF_SIZE], ax

.save_all:
    call fs_save_bitmap
    jc .io_fail
    call fs_save_inode_table
    jc .io_fail

    xor ah, ah
    ret

.no_space:
    mov ah, 1
    ret

.io_fail:
    mov ah, 2
    ret

; fs_delete_by_path
; Input: DS:SI = path
; Output: AH=0 ok, AH=1 not found/invalid, AH=2 io, AH=3 dir not empty
fs_delete_by_path:
    cmp byte [fs_inode_ready], 1
    jne .io_fail ; jump if not equal/non-zero

    call fs_load_inode_table
    jc .io_fail
    call fs_load_bitmap
    jc .io_fail

    call fs_resolve_path_loaded
    cmp ah, 0
    jne .not_found ; jump if not equal/non-zero

    mov [fs_target_index], al

    cmp al, INFS_ROOT_INODE
    je .not_found ; jump if equal/zero

    cmp byte [di + INFS_OFF_TYPE], INFS_TYPE_DIR
    jne .free_delete ; jump if not equal/non-zero

    ; Directories must be empty before deletion.
    mov bl, 0
.check_child:
    cmp bl, INFS_MAX_INODES
    jae .free_delete
    mov ax, 0x10
    mov al, bl
    shl ax, 4
    mov bx, INFS_INODE_BUF
    add bx, ax
    cmp byte [bx + INFS_OFF_USED], 1
    jne .next_child ; jump if not equal/non-zero
    mov al, [fs_target_index]
    cmp byte [bx + INFS_OFF_PARENT], al
    je .dir_not_empty ; jump if equal/zero
.next_child:
    inc bl
    jmp .check_child ; jump unconditionally

.free_delete:
    mov dl, [di + INFS_OFF_START]
    mov dh, [di + INFS_OFF_COUNT]
    call fs_free_run_loaded

    ; Clear inode record.
    push di
    mov cx, INFS_INODE_SIZE
    xor al, al
    rep stosb
    pop di

    call fs_save_bitmap
    jc .io_fail
    call fs_save_inode_table
    jc .io_fail

    xor ah, ah
    ret

.dir_not_empty:
    mov ah, 3
    ret

.not_found:
    mov ah, 1
    ret

.io_fail:
    mov ah, 2
    ret

; fs_mkdir_by_path
; Input: DS:SI = path
; Output: AH=0 ok, AH=1 invalid/exist, AH=2 io
fs_mkdir_by_path:
    cmp byte [fs_inode_ready], 1
    jne .io_fail ; jump if not equal/non-zero

    mov [fs_path_ptr], si

    call fs_load_inode_table
    jc .io_fail

    ; Path must not already exist.
    push si
    call fs_resolve_path_loaded
    cmp ah, 0
    je .exists ; jump if equal/zero
    pop si

    ; Resolve parent directory and leaf.
    call fs_split_parent_leaf_loaded
    cmp ah, 0
    jne .invalid ; jump if not equal/non-zero

    call fs_alloc_inode_loaded
    cmp ah, 0
    jne .invalid ; jump if not equal/non-zero

    mov byte [di + INFS_OFF_USED], 1
    mov byte [di + INFS_OFF_TYPE], INFS_TYPE_DIR
    mov word [di + INFS_OFF_SIZE], 0
    mov byte [di + INFS_OFF_START], 0
    mov byte [di + INFS_OFF_COUNT], 0
    mov al, [fs_parent_index]
    mov [di + INFS_OFF_PARENT], al
    mov si, [fs_path_ptr]
    call fs_name_copy_path_tail_to_inode

    call fs_save_inode_table
    jc .io_fail
    xor ah, ah
    ret

.exists:
    pop si
.invalid:
    mov ah, 1
    ret

.io_fail:
    mov ah, 2
    ret

; fs_chdir_by_path
; Input: DS:SI = path
; Output: AH=0 ok, AH=1 invalid/not found, AH=2 io
fs_chdir_by_path:
    cmp byte [fs_inode_ready], 1
    jne .io_fail ; jump if not equal/non-zero
    call fs_load_inode_table
    jc .io_fail
    call fs_resolve_path_loaded
    cmp ah, 0
    jne .invalid ; jump if not equal/non-zero
    cmp byte [di + INFS_OFF_TYPE], INFS_TYPE_DIR
    jne .invalid ; jump if not equal/non-zero
    mov [fs_cwd_inode], al
    xor ah, ah
    ret

.invalid:
    mov ah, 1
    ret

.io_fail:
    mov ah, 2
    ret

; fs_load_inode_table
; Loads inode table sector to INFS_INODE_BUF. CF set on error.
fs_load_inode_table:
    mov ax, 0
    mov es, ax
    mov bx, INFS_INODE_BUF
    mov al, 1
    mov ch, 0
    mov cl, INFS_INODE_SECTOR
    mov dh, 0
    call disk_read_chs
    ret

; fs_save_inode_table
; Writes inode table sector from INFS_INODE_BUF. CF set on error.
fs_save_inode_table:
    mov ax, 0
    mov es, ax
    mov bx, INFS_INODE_BUF
    mov al, 1
    mov ch, 0
    mov cl, INFS_INODE_SECTOR
    mov dh, 0
    call disk_write_chs
    ret

; fs_load_bitmap
; Loads bitmap sector to INFS_BITMAP_BUF. CF set on error.
fs_load_bitmap:
    mov ax, 0
    mov es, ax
    mov bx, INFS_BITMAP_BUF
    mov al, 1
    mov ch, 0
    mov cl, INFS_BITMAP_SECTOR
    mov dh, 0
    call disk_read_chs
    ret

; fs_save_bitmap
; Writes bitmap sector from INFS_BITMAP_BUF. CF set on error.
fs_save_bitmap:
    mov ax, 0
    mov es, ax
    mov bx, INFS_BITMAP_BUF
    mov al, 1
    mov ch, 0
    mov cl, INFS_BITMAP_SECTOR
    mov dh, 0
    call disk_write_chs
    ret

; fs_get_inode_ptr
; Input: AL=index, Output: DI=inode pointer in INFS_INODE_BUF
fs_get_inode_ptr:
    xor ah, ah
    shl ax, 4
    mov di, INFS_INODE_BUF
    add di, ax
    ret

; fs_path_next_segment
; Input: DS:SI path cursor
; Output: AL=1 segment copied, AL=0 no more
;         AH=1 segment is last, AH=0 more remains
;         SI advanced to delimiter (0 or '/')
;         fs_seg_name filled with null-terminated segment
fs_path_next_segment:
.skip_slash:
    cmp byte [si], '/'
    jne .begin ; jump if not equal/non-zero
    inc si
    jmp .skip_slash ; jump unconditionally

.begin:
    cmp byte [si], 0
    jne .copy ; jump if not equal/non-zero
    xor al, al
    xor ah, ah
    ret

.copy:
    mov di, fs_seg_name
    mov cx, INFS_NAME_LEN
.copy_loop:
    mov al, [si]
    cmp al, 0
    je .finish_last ; jump if equal/zero
    cmp al, '/'
    je .finish_more ; jump if equal/zero
    cmp cx, 0
    je .skip_store ; jump if equal/zero
    mov [di], al
    inc di
    dec cx
.skip_store:
    inc si
    jmp .copy_loop ; jump unconditionally

.finish_more:
    mov byte [di], 0
    mov al, 1
    xor ah, ah
    ret

.finish_last:
    mov byte [di], 0
    mov al, 1
    mov ah, 1
    ret

; fs_find_inode_in_loaded
; Input: AL=parent index, DS:SI=leaf name
; Output: AH=0 found (BL=index, DI=ptr), AH=1 not found
fs_find_inode_in_loaded:
    mov [fs_parent_index], al
    xor bl, bl
.scan:
    cmp bl, INFS_MAX_INODES
    jae .nf
    mov ax, 0x10
    mov al, bl
    shl ax, 4
    mov di, INFS_INODE_BUF
    add di, ax
    cmp byte [di + INFS_OFF_USED], 1
    jne .next ; jump if not equal/non-zero
    mov al, [fs_parent_index]
    cmp byte [di + INFS_OFF_PARENT], al
    jne .next ; jump if not equal/non-zero
    push bx
    push di
    call fs_name_eq_inode_name
    pop di
    pop bx
    cmp al, 1
    je .ok ; jump if equal/zero
.next:
    inc bl
    jmp .scan ; jump unconditionally
.ok:
    xor ah, ah
    ret
.nf:
    mov ah, 1
    ret

; fs_resolve_path_loaded
; Input: DS:SI path
; Output: AH=0 found (AL=index, DI=ptr), AH=1 not found/invalid
fs_resolve_path_loaded:
    mov al, [si]
    cmp al, '/'
    jne .from_cwd ; jump if not equal/non-zero
    mov al, INFS_ROOT_INODE
    jmp .set_curr ; jump unconditionally
.from_cwd:
    mov al, [fs_cwd_inode]
.set_curr:
    mov [fs_curr_index], al

.seg_loop:
    call fs_path_next_segment
    cmp al, 0
    je .done ; jump if equal/zero
    mov [fs_inode_index], ah ; preserve "is last segment" flag from parser

    ; Handle . and ..
    cmp byte [fs_seg_name], '.'
    jne .not_dot ; jump if not equal/non-zero
    cmp byte [fs_seg_name + 1], 0
    je .advance ; jump if equal/zero
    cmp byte [fs_seg_name + 1], '.'
    jne .not_dot ; jump if not equal/non-zero
    cmp byte [fs_seg_name + 2], 0
    jne .not_dot ; jump if not equal/non-zero

    mov al, [fs_curr_index]
    call fs_get_inode_ptr
    mov al, [di + INFS_OFF_PARENT]
    cmp al, 0xFF
    je .advance ; jump if equal/zero
    mov [fs_curr_index], al
    jmp .advance ; jump unconditionally

.not_dot:
    mov [fs_path_ptr], si ; preserve original path cursor
    mov al, [fs_curr_index]
    mov si, fs_seg_name
    call fs_find_inode_in_loaded
    cmp ah, 0
    jne .not_found ; jump if not equal/non-zero
    mov [fs_curr_index], bl

.advance:
    cmp byte [fs_inode_index], 1
    je .done ; jump if equal/zero
    mov si, [fs_path_ptr] ; restore path cursor before delimiter checks
    cmp byte [si], '/'
    jne .seg_loop ; jump if not equal/non-zero
    inc si
    jmp .seg_loop ; jump unconditionally

.done:
    mov al, [fs_curr_index]
    call fs_get_inode_ptr
    xor ah, ah
    ret

.not_found:
    mov ah, 1
    ret

; fs_split_parent_leaf_loaded
; Input: DS:SI path
; Output: AH=0 ok (fs_parent_index + fs_leaf_name), AH=1 invalid
fs_split_parent_leaf_loaded:
    mov al, [si]
    cmp al, '/'
    jne .from_cwd ; jump if not equal/non-zero
    mov al, INFS_ROOT_INODE
    jmp .set_parent ; jump unconditionally
.from_cwd:
    mov al, [fs_cwd_inode]
.set_parent:
    mov [fs_parent_index], al

.next_seg:
    call fs_path_next_segment
    cmp al, 0
    je .invalid ; jump if equal/zero
    mov [fs_inode_index], ah ; preserve "is last segment" flag from parser

    ; Save this segment as candidate leaf.
    mov si, fs_seg_name
    mov di, fs_leaf_name
    mov cx, INFS_NAME_LEN
.copy_leaf:
    mov al, [si]
    mov [di], al
    inc si
    inc di
    cmp al, 0
    je .leaf_done ; jump if equal/zero
    loop .copy_leaf
    mov byte [di], 0
.leaf_done:

    cmp byte [fs_inode_index], 1
    je .ok ; jump if equal/zero

    ; Descend through directory segment.
    mov [fs_path_ptr], si ; preserve original path cursor
    mov al, [fs_parent_index]
    mov si, fs_seg_name
    call fs_find_inode_in_loaded
    cmp ah, 0
    jne .invalid ; jump if not equal/non-zero
    cmp byte [di + INFS_OFF_TYPE], INFS_TYPE_DIR
    jne .invalid ; jump if not equal/non-zero
    mov [fs_parent_index], bl

    mov si, [fs_path_ptr] ; restore path cursor before delimiter checks
    cmp byte [si], '/'
    jne .next_seg ; jump if not equal/non-zero
    inc si
    jmp .next_seg ; jump unconditionally

.ok:
    xor ah, ah
    ret

.invalid:
    mov ah, 1
    ret

; fs_alloc_inode_loaded
; Output: AH=0 and DI pointer on success, AH=1 if none
fs_alloc_inode_loaded:
    xor bl, bl
.find:
    cmp bl, INFS_MAX_INODES
    jae .none
    mov ax, 0x10
    mov al, bl
    shl ax, 4
    mov di, INFS_INODE_BUF
    add di, ax
    cmp byte [di + INFS_OFF_USED], 0
    je .ok ; jump if equal/zero
    inc bl
    jmp .find ; jump unconditionally
.ok:
    xor ah, ah
    ret
.none:
    mov ah, 1
    ret

; fs_name_copy_leaf_to_inode
; Input: DI inode ptr, fs_leaf_name source
fs_name_copy_leaf_to_inode:
    push di
    add di, INFS_OFF_NAME
    mov si, fs_leaf_name
    mov cx, INFS_NAME_LEN
.cpy:
    mov al, [si]
    mov [di], al
    inc si
    inc di
    cmp al, 0
    je .zero ; jump if equal/zero
    loop .cpy
    pop di
    ret
.zero:
    dec cx
    jz .done ; jump if equal/zero
.zl:
    mov byte [di], 0
    inc di
    dec cx
    jnz .zl ; jump if not equal/non-zero
.done:
    pop di
    ret

; fs_name_copy_path_tail_to_inode
; Input: DS:SI full path, DI inode ptr
; Copies only final path segment (after last '/') into inode name field.
fs_name_copy_path_tail_to_inode:
    push ax
    push bx
    push cx
    push si
    push di

    mov bx, si
.find_tail:
    mov al, [si]
    cmp al, 0
    je .tail_found
    cmp al, '/'
    jne .find_next
    mov bx, si
    inc bx
.find_next:
    inc si
    jmp .find_tail

.tail_found:
    mov si, bx
    mov cx, INFS_NAME_LEN
    mov bx, di
    add bx, INFS_OFF_NAME

.copy:
    cmp cx, 0
    je .finish
    mov al, [si]
    cmp al, 0
    je .terminate
    cmp al, '/'
    je .terminate
    mov [bx], al
    inc bx
    inc si
    dec cx
    jmp .copy

.terminate:
    mov byte [bx], 0
    inc bx
    dec cx

.zero_pad:
    cmp cx, 0
    je .finish
    mov byte [bx], 0
    inc bx
    dec cx
    jmp .zero_pad

.finish:
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

; fs_leaf_is_arc
; Output: AL=1 if leaf ends with ".arc", else 0
fs_leaf_is_arc:
    mov si, fs_leaf_name
    xor cx, cx
.len:
    cmp byte [si], 0
    je .check ; jump if equal/zero
    inc si
    inc cx
    jmp .len ; jump unconditionally
.check:
    cmp cx, 4
    jb .no
    mov si, fs_leaf_name
    add si, cx
    sub si, 4
    cmp byte [si + 0], '.'
    jne .no ; jump if not equal/non-zero
    cmp byte [si + 1], 'a'
    jne .no ; jump if not equal/non-zero
    cmp byte [si + 2], 'r'
    jne .no ; jump if not equal/non-zero
    cmp byte [si + 3], 'c'
    jne .no ; jump if not equal/non-zero
    mov al, 1
    ret
.no:
    xor al, al
    ret

; fs_free_run_loaded
; Input: DL start_block, DH count
fs_free_run_loaded:
    cmp dh, 0
    je .ret ; jump if equal/zero
    xor bx, bx
    mov bl, dl
.loop:
    cmp dh, 0
    je .ret ; jump if equal/zero
    mov byte [INFS_BITMAP_BUF + bx], 0
    inc bl
    dec dh
    jmp .loop ; jump unconditionally
.ret:
    ret

; fs_alloc_run_loaded
; Input: AL blocks needed
; Output: AH=0 and AL=start block, AH=1 no space
fs_alloc_run_loaded:
    mov [fs_need_blocks], al
    xor dl, dl
.search:
    mov al, [fs_need_blocks]
    mov bl, dl
    add bl, al
    cmp bl, INFS_MAX_BLOCKS
    ja .no

    mov bl, dl
    mov cl, [fs_need_blocks]
.probe:
    cmp byte [INFS_BITMAP_BUF + bx], 0
    jne .next ; jump if not equal/non-zero
    inc bl
    dec cl
    jnz .probe ; jump if not equal/non-zero

    mov bl, dl
    mov cl, [fs_need_blocks]
.mark:
    mov byte [INFS_BITMAP_BUF + bx], 1
    inc bl
    dec cl
    jnz .mark ; jump if not equal/non-zero

    mov al, dl
    xor ah, ah
    ret

.next:
    inc dl
    cmp dl, INFS_MAX_BLOCKS
    jb .search
.no:
    mov ah, 1
    ret

; fs_crypto_xor_region
; Input: ES:BX buffer, CX byte count, DL tweak byte
; In-place XOR transform used for both encrypt and decrypt.
fs_crypto_xor_region:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    cmp cx, 0
    je .done

    mov di, bx
    xor si, si

.xor_loop:
    mov al, [es:di]
    mov ah, [fs_crypto_key + si]
    xor al, ah
    xor al, dl
    mov [es:di], al
    inc di
    inc si
    and si, 3
    dec cx
    jnz .xor_loop

.done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ----------------------------------
; disk_read_chs scratch state (kernel globals)
; ----------------------------------
dr_count:
    db 0
dr_lba:
    db 0
dr_dest:
    dw 0
dr_retries:
    db 0
dr_last_status:
    db 0

kbd_shift_state:
    db 0
kbd_scancode_set:
    db 1
kbd_set2_break:
    db 0

; Set-1 keyboard scancode -> ASCII maps.
kbd_ascii:
    db 0, 27, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', 8, 9
    db 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', 13, 0, 'a', 's'
    db 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', 39, 96, 0, 92, 'z', 'x', 'c', 'v'
    db 'b', 'n', 'm', ',', '.', '/', 0, '*', 0, ' '
    times (128 - ($ - kbd_ascii)) db 0

kbd_ascii_shift:
    db 0, 27, '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+', 8, 9
    db 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}', 13, 0, 'A', 'S'
    db 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', 34, 126, 0, 124, 'Z', 'X', 'C', 'V'
    db 'B', 'N', 'M', '<', '>', '?', 0, '*', 0, ' '
    times (128 - ($ - kbd_ascii_shift)) db 0

prog_table_loaded:
    db 0
disk_available:
    db 1
prog_table_count:
    db 0
run_name_ptr:
    dw 0
pt_index:
    db 0

; InodeFS runtime state scratch
fs_inode_ready:
    db 0
fs_cwd_inode:
    db 0
fs_name_ptr:
    dw 0
fs_path_ptr:
    dw 0
fs_ordinal:
    db 0
fs_inode_index:
    db 0
fs_parent_index:
    db 0
fs_curr_index:
    db 0
fs_target_index:
    db 0
fs_need_blocks:
    db 0
fs_start_block:
    db 0
fs_write_len:
    dw 0
fs_write_buf:
    dw 0
fs_io_bx:
    dw 0
fs_io_es:
    dw 0
fs_seg_name:
    times INFS_NAME_LEN + 1 db 0
fs_leaf_name:
    times INFS_NAME_LEN + 1 db 0

fs_crypto_key:
    db 0x73, 0xC1, 0x2A, 0x9F


; --------------------------------DATA SECTION------------------------------------
; Minimal flat GDT for future protected-mode transition:
;   selector 0x08 -> code segment
;   selector 0x10 -> data segment
gdt_start:
    dq 0x0000000000000000
    dq 0x00CF9A000000FFFF
    dq 0x00CF92000000FFFF
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

; ========== INTERRUPT DESCRIPTOR TABLE (IDT) ==========
; 256 gates x 8 bytes each = 2048 bytes
idt_table:
    times 256 * 8 db 0

idt_descriptor:
    dw 256 * 8 - 1
    dd idt_table

logo_line_01:
    db "                         ######                         ", 0
logo_line_02:
    db "                     ####  ##  ####                     ", 0
logo_line_03:
    db "                   ##      ##      ##                   ", 0
logo_line_04:
    db "                 ##      ##  ##      ##                 ", 0
logo_line_05:
    db "               ##      ##      ##      ##               ", 0
logo_line_06:
    db "               ##    ##          ##    ##               ", 0
logo_line_07:
    db "             ##    ##              ##    ##             ", 0
logo_line_08:
    db "             ######                  ######             ", 0
logo_line_09:
    db "             ##    ##              ##    ##             ", 0
logo_line_10:
    db "               ##    ##          ##    ##               ", 0
logo_line_11:
    db "               ##      ##      ##      ##               ", 0
logo_line_12:
    db "                 ##      ##  ##      ##                 ", 0
logo_line_13:
    db "                   ##      ##      ##                   ", 0
logo_line_14:
    db "                     ####  ##  ####                     ", 0
logo_line_15:
    db "                         ######                         ", 0

welcome_msg:
    db "     Welcome to CircleOS v0.1.22!", 13, 10, 0

help_msg:
    db "Available kernel commands:", 13, 10
    db "  help   - show this message", 13, 10
    db "  csh    - launch Circle shell", 13, 10, 0

prompt:
    db "CircleOS Kernel > ", 0

unknown_msg:
    db "[E200] Unknown kernel command. Type 'csh' to open shell.", 13, 10, 0

boot_info_bad_msg:
    db "[E100] BOOT INFO INVALID", 13, 10, 0

prog_table_bad_msg:
    db "[E110] Program table load/validation failed", 0
prog_table_bad_code_msg:
    db " code=0x", 0
prog_table_bad_read_msg:
    db " (read fail)", 0
prog_table_bad_magic_msg:
    db " (bad magic)", 0
prog_table_bad_count_msg:
    db " (bad count)", 0
prog_table_bad_layout_msg:
    db " (bad layout)", 0
prog_table_bad_ata_msg:
    db " ata=0x", 0

debug_searching:
    db "[DEBUG] Searching for program: ", 0
debug_newline:
    db 13, 10, 0
debug_loaded_msg:
    db "[DEBUG] Program table loaded with ", 0
cmd_help_str:
    db "help", 0
cmd_csh_str:
    db "csh", 0

shell_load_fail_msg:
    db "[E120] Failed to load csh", 0
shell_disk_unavailable_msg:
    db "[E121] Storage unavailable; no userspace shell available", 0
ata_status_msg:
    db " ata=0x", 0
fs_mount_fail_msg:
    db "[E300] InodeFS mount/format failed", 0
fs_no_disk_msg:
    db "[E301] InodeFS unavailable (no storage)", 0
rescue_title_msg:
    db "[E900] Rescue UI", 0
rescue_hint_msg:
    db "userspace unavailable; choose an action", 0
rescue_menu_msg:
    db "[R]eboot [D]iag [K]bd-test [H]alt > ", 0
rescue_badkey_msg:
    db "[E901] invalid key", 0
rescue_halt_msg:
    db "[E902] halted by user", 0
rescue_diag_prefix:
    db "diag reason/ata/disk/pt_loaded/pt_count=0x", 0
rescue_diag_sep:
    db "/0x", 0
rescue_kbd_msg:
    db "keyboard test: press ESC to return", 0
command_buf:
    times 32 db 0
rescue_reason:
    db 0



