; image.asm
; full screen image viewer for CircleOS
; CEX1 VERSION 1
; load 265-colour pallete and 320*200 pixel data from disk and display on screen
; shows using vga mode 0x13

[BITS 16]
[ORG 0xA000]

; -------
; Kernel syscall interface
; -------
SYSCALL_INT equ 0x80
SYS_PUTC equ 0x01
SYS_PUTS equ 0x02
SYS_NEWLINE equ 0x03
SYS_GETC equ 0x04
SYS_CLEAR equ 0x05
SYS_RUN equ 0x06
SYS_READ_RAW equ 0x07
CTRL_C equ 0x03

; -------
; build-time layout defines
; -------
; values from build.sh
%ifndef SPLASH_PAL_SECTOR
SPLASH_PAL_SECTOR equ 25
%endif

%ifndef SPLASH_PAL_SECTORS
SPLASH_PAL_SECTORS equ 2
%endif

%ifndef SPLASH_IMG_SECTOR
SPLASH_IMG_SECTOR equ 27
%endif
%ifndef SPLASH_IMG_SECTORS
SPLASH_IMG_SECTORS equ 125
%endif

; -------
; memory map for buffers
; -------
IMG_BUF_SEG equ 0x2000
PAL_BUF_SEG equ 0x3000

start:
    mov ax, 0
    mov ds, ax
    mov es, ax

    ; Load palette data from disk into PAL_BUF
    mov ax, PAL_BUF_SEG
    mov es, ax  ; set ES to PAL_BUF_SEG for disk read
    xor bx, bx  ; offset 0 in PAL_BUF
    mov al, SPLASH_PAL_SECTOR ; start sector
    mov ah, SPLASH_PAL_SECTORS ; total sectors to read
    call read_sectors_linear
    jc .read_fail

    ; read image data from disk into IMG_BUF
    mov ax, IMG_BUF_SEG
    mov es, ax  ; set ES to IMG_BUF_SEG for disk read
    xor bx, bx  ; offset 0 in IMG_BUF
    mov al, SPLASH_IMG_SECTOR ; start sector
    mov ah, SPLASH_IMG_SECTORS ; total sectors to read
    call read_sectors_linear
    jc .read_fail

    ; enter vga mode 0x13
    mov ax, 0x0013
    int 0x10

    ; push pallet into vga dac
    call vga_load_palette

    ;copy bytes to video memory
    call blit_image_to_vram

    ; wait for key press before exiting
    xor ax, ax
    int 0x16

    ; return to colour text mode
    mov ax, 0x0003
    int 0x10

    ret

.read_fail:
    mov si, msg_read_fail
    call sys_puts
    call sys_newline
    ret

; read_sectors_linear: read AL sectors starting from sector in AH into ES:BX
; Inputs:
; AL = start sector
; AH = number of sectors to read
; ES:BX = destination
; Output:
; cf cleared on success, set on failure
; Clobbers:

read_sectors_linear:
    mov [rs_sector], al
    mov [rs_left], ah

.loop:
    cmp byte [rs_left], 0
    je .ok

    mov ah, SYS_READ_RAW
    mov al, 1 ; read one sector at a time
    mov ch, 0
    mov cl, [rs_sector]
    mov dh, 0
    int SYSCALL_INT
    cmp ah, 0
    jne .fail

    inc byte [rs_sector]
    add bx, 512
    dec byte [rs_left]
    jmp .loop


.ok:
    clc
    ret

.fail:
    stc
    ret

; vga_load_palette
; reads 256 rgb triplets from pal buf and writes to dac
; dac protpcol:
; port 0x3c8 is starting pallete index
; port 0x3c9 is rgb data (3 writes per index)

vga_load_palette:
    mov ax, PAL_BUF_SEG
    mov ds, ax
    xor si, si ; offset 0 in pal buf

    mov dx, 0x3c8
    xor al, al ; start at palette index 0
    out dx, al

    inc dx ; now dx = 0x3c9 for rgb data
    mov cx, 256 ; 256 palette entries

.colour_loop:
    lodsb ; load red
    out dx, al
    lodsb ; load green
    out dx, al
    lodsb ; load blue
    out dx, al

    loop .colour_loop

    ; restore ds for program labels and syscalls
    xor ax, ax
    mov ds, ax
    ret

; blit_image_to_vram
; copies 320*200 bytes from IMG_BUF to vga memory at 0xa000
blit_image_to_vram:
    mov ax, IMG_BUF_SEG
    mov ds, ax
    mov ax, 0xA000
    mov es, ax

    xor si, si ; offset 0 in img buf
    xor di, di ; offset 0 in vram
    mov cx, 320*200 ; total pixels
    cld
    rep movsb

    ;restore ds for program labels and syscalls
    xor ax, ax
    mov ds, ax
    ret

sys_puts:
    mov ah, SYS_PUTS
    int SYSCALL_INT
    ret

sys_newline:
    mov ah, SYS_NEWLINE
    int SYSCALL_INT
    ret

msg_read_fail:
    db "img: Failed to read from disk", 0

rs_sector:
    db 0
rs_left:
    db 0