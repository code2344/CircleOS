; img.asm - VGA image viewer for CircleOS
; Displays 320x200 256-color image loaded from disk
; Uses VGA mode 0x13 (320x200, 256 colors, linear VRAM at 0xA000)

[BITS 32]               ; 32-bit protected mode
[ORG 0xA000]            ; Loaded by kernel at this address

; ================== KERNEL SYSCALL INTERFACE ==================
SYSCALL_INT equ 0x80
SYS_PUTC equ 0x01       ; print character
SYS_PUTS equ 0x02       ; print string
SYS_NEWLINE equ 0x03    ; print CR+LF
SYS_GETC equ 0x04       ; read keystroke
SYS_CLEAR equ 0x05      ; clear screen
SYS_RUN equ 0x06        ; launch program
SYS_READ_RAW equ 0x07   ; read disk sectors
SYS_GETC equ 0x04       ; read keystroke
SYS_SET_VIDEO_MODE equ 0x10 ; set video mode through kernel
SYS_PRESENT_FRAMEBUFFER equ 0x11 ; copy backbuffer to VGA memory
CTRL_C equ 0x03         ; user abort

; ================== BUILD-TIME CONSTANTS ==================
; These are set by build.sh based on disk layout
%ifndef SPLASH_PAL_SECTOR
SPLASH_PAL_SECTOR equ 25 ; disk sector where palette data starts
%endif

%ifndef SPLASH_PAL_SECTORS
SPLASH_PAL_SECTORS equ 2 ; number of sectors for palette
%endif

%ifndef SPLASH_IMG_SECTOR
SPLASH_IMG_SECTOR equ 27 ; disk sector where image data starts
%endif

%ifndef SPLASH_IMG_SECTORS
SPLASH_IMG_SECTORS equ 125 ; number of sectors for image (320*200 = 64KB)
%endif

; ================== MEMORY LAYOUT ==================
; Image buffers are placed above kernel and shell in memory
IMG_BUF_SEG equ 0x2000  ; buffer for image pixel data (64KB)
PAL_BUF_SEG equ 0x3000  ; buffer for palette (768 bytes = 256 colors * 3 RGB bytes)

start:
    mov ax, 0
    mov ds, ax              ; DS = 0 for absolute addressing
    mov es, ax              ; ES = 0 initially

    ; Load palette from disk into memory buffer
    mov ax, PAL_BUF_SEG     ; ES = segment for palette buffer
    mov es, ax
    xor bx, bx              ; BX = offset 0 in palette buffer
    mov al, SPLASH_PAL_SECTOR ; sector to start reading from
    mov ah, SPLASH_PAL_SECTORS ; number of sectors to read
    call read_sectors_linear ; load palette data
    jc .read_fail           ; if error, show message and exit

    ; Load image from disk into memory buffer
    mov ax, IMG_BUF_SEG     ; ES = segment for image buffer
    mov es, ax
    xor bx, bx              ; BX = offset 0 in image buffer
    mov al, SPLASH_IMG_SECTOR ; sector to start reading from
    mov ah, SPLASH_IMG_SECTORS ; number of sectors to read
    call read_sectors_linear ; load image data
    jc .read_fail           ; if error, show message and exit

    ; Switch to VGA 256-color mode 0x13 through the kernel
    mov al, 0x13
    mov ah, SYS_SET_VIDEO_MODE
    int SYSCALL_INT

    ; Load palette into VGA DAC (Digital-to-Analog Converter)
    call vga_load_palette   ; write 256-color palette to hardware

    ; Copy image data from buffer to VRAM (0xA000)
    push ds
    mov ax, IMG_BUF_SEG
    mov ds, ax
    mov si, 0
    mov ah, SYS_PRESENT_FRAMEBUFFER
    int SYSCALL_INT
    pop ds

    ; Wait for user to press a key before exiting
    mov ah, SYS_GETC
    int SYSCALL_INT

    ; Return to text mode (80x25 color text)
    mov al, 0x03
    mov ah, SYS_SET_VIDEO_MODE
    int SYSCALL_INT

    ret                     ; return to shell

.read_fail:
    mov si, msg_read_fail
    call sys_puts
    call sys_newline
    ret

; read_sectors_linear - Read multiple disk sectors into memory
; Input:
;   AL = starting sector number (1-based)
;   AH = number of sectors to read  
;   ES:BX = destination buffer address
; Output:
;   CF = 0 on success, 1 on failure
read_sectors_linear:
    mov [rs_sector], al     ; save starting sector
    mov [rs_left], ah       ; save count of sectors left to read

.loop:
    cmp byte [rs_left], 0   ; all sectors read?
    je .ok                  ; yes, success

    ; Call kernel syscall SYS_READ_RAW to read one sector
    mov ah, SYS_READ_RAW    ; syscall 0x07
    mov al, 1               ; read exactly 1 sector per call
    mov ch, 0               ; cylinder (not used, set to 0)
    mov cl, [rs_sector]     ; sector number
    mov dh, 0               ; head (not used, set to 0)
    int SYSCALL_INT         ; call kernel
    cmp ah, 0               ; AH=0 means success
    jne .fail               ; AH!=0 means error

    ; Advance to next sector and buffer position
    inc byte [rs_sector]    ; next sector number
    add bx, 512             ; advance buffer pointer by 1 sector
    dec byte [rs_left]      ; one less sector to read
    jmp .loop

.ok:
    clc                     ; CF=0 (success)
    ret

.fail:
    stc                     ; CF=1 (error)
    ret

; vga_load_palette - Write 256 RGB colors to VGA DAC
; This implements the VGA DAC protocol:
; Port 0x3C8: write palette index (0-255)
; Port 0x3C9: write RGB values (3 sequential OUTs = R, G, B)
; Inputs: Palette buffer at PAL_BUF_SEG contains 768 bytes (256 * 3 RGB)
vga_load_palette:
    mov ax, PAL_BUF_SEG     ; set DS to palette buffer segment
    mov ds, ax
    xor si, si              ; SI = offset 0 (start of palette data)

    mov dx, 0x3c8           ; DX = DAC write index port
    xor al, al              ; AL = 0 (start at palette index 0)
    out dx, al              ; write starting index

    inc dx                  ; DX = 0x3c9 (DAC data port, for RGB values)
    mov cx, 256             ; load all 256 colors

.colour_loop:
    lodsb                   ; load red component from palette buffer
    out dx, al              ; write red to DAC
    lodsb                   ; load green component
    out dx, al              ; write green to DAC
    lodsb                   ; load blue component
    out dx, al              ; write blue to DAC

    loop .colour_loop       ; repeat for all 256 colors

    ; Restore DS for program's normal memory access
    mov ax, 0x10
    mov ds, ax
    ret

; blit_image_to_vram - Copy image pixel data to VGA VRAM
; Copies 320*200 = 64000 bytes from IMG_BUF to graphics memory
; In VGA mode 0x13, VRAM is at segment 0xA000, linear addressing 0-63999
blit_image_to_vram:
    mov ax, IMG_BUF_SEG     ; DS = image buffer segment
    mov ds, ax
    mov ax, 0xA000          ; ES = VGA VRAM segment
    mov es, ax

    xor si, si              ; SI = offset 0 in image buffer
    xor di, di              ; DI = offset 0 in VRAM
    mov cx, 320*200         ; CX = total pixel count (320 width * 200 height)
    cld                     ; clear direction flag (auto-increment addresses)
    rep movsb               ; bulk copy SI->DI, CX times (copies bytes)

    ; Restore DS for program labels and syscalls
    mov ax, 0x10
    mov ds, ax
    ret

; ================== SYSCALL WRAPPER FUNCTIONS ==================

; sys_puts - Print null-terminated string to console
; Input: DS:SI = string address  
sys_puts:
    mov ah, SYS_PUTS        ; syscall 0x02
    int SYSCALL_INT
    ret

; sys_newline - Print carriage return and line feed  
sys_newline:
    mov ah, SYS_NEWLINE     ; syscall 0x03
    int SYSCALL_INT
    ret

; ================== ERROR MESSAGES ==================

msg_read_fail:
    db "img: Failed to read from disk", 0

; ================== WORKING DATA ================

rs_sector:              db 0    ; current sector number during sequential reads
rs_left:                db 0    ; number of sectors remaining to read
