; CircleOS 512-byte initial bootloader
; Made by Ruben Sutton
; Last updated: 17 March 2026
; Find me at https://scstudios.tech

[BITS 16]           ; 16 bit real mode
[ORG 0x7C00]        ; code loaded at address 0x7C00
%ifndef KERNEL_SECTORS
KERNEL_SECTORS equ 4
%endif

BOOT_INFO_ADDR equ 0x0500
BOOT_SIG0_OFF equ BOOT_INFO_ADDR + 0
BOOT_SIG1_OFF equ BOOT_INFO_ADDR + 1
BOOT_VER_OFF equ BOOT_INFO_ADDR + 2
BOOT_DRIVE_OFF equ BOOT_INFO_ADDR + 3
BOOT_KSECT_OFF equ BOOT_INFO_ADDR + 4


; OS Versions for debugging
%assign VER_MAJOR 0 
%assign VER_MINOR 1
%assign VER_PATCH 15
%assign VER_BOOTLOADER 15


;   convert the version numbers to strings
; versions of OS
%defstr VER_MAJOR_STR VER_MAJOR
%defstr VER_MINOR_STR VER_MINOR
%defstr VER_PATCH_STR VER_PATCH

; bootloader release
%defstr VER_BOOTLOADER_STR VER_BOOTLOADER

start:
    mov ax, 0                         ; initialize segment registers
    mov ds, ax
    mov es, ax
    
    mov [BOOT_DRIVE_OFF], dl           ; save BIOS boot drive (DL) for all future disk calls
    mov byte [BOOT_SIG0_OFF], 'C'       ; signature byte 0
    mov byte [BOOT_SIG1_OFF], 'B'       ; signature byte 1
    mov byte [BOOT_VER_OFF], 1          ; boot info struct version
    mov byte [BOOT_KSECT_OFF], KERNEL_SECTORS

    mov si, boot_msg
    call print_string

    ; reset retry counter at boot
    mov byte [retry_count], 1         ; one retry after first failure

.read_kernel:
    mov ah, 0x02                      ; function 02h = read sectors
    mov al, KERNEL_SECTORS            ; number of sectors to read
    mov bx, 0x7E00                    ; ES:BX destination buffer
    mov cx, 0x0002                    ; CH=0 (cylinder), CL=2 (sector starts at 1)
    xor dh, dh                        ; head = 0
    mov dl, [BOOT_DRIVE_OFF]          ; drive number from BIOS
    int 0x13                          ; perform disk read

    jnc .read_ok                      ; CF=0 means success
    jmp .read_failed                  ; CF=1 means error (AH has status code)

.read_failed:
    ; save BIOS error code now before any other INT can overwrite AH
    mov [disk_status], ah

    cmp byte [retry_count], 0           ; if no retries left, print error and halt
    je .disk_error

    ; consume one retry and reset disk controller
    dec byte [retry_count]
    mov ah, 0x00                      ; function 00h = reset disk system
    mov dl, [BOOT_DRIVE_OFF]
    int 0x13

    ; try the kernel read again
    jmp .read_kernel

.read_ok:
    mov si, kernel_msg
    call print_string
    jmp 0x7E00                        ; transfer control to loaded kernel

.disk_error:
    mov si, disk_error_msg            ; "DISK ERROR ... AH=0x"
    call print_string
    mov al, [disk_status]             ; print BIOS error status in hex
    call print_hex8

    ; print newline (CRLF)
    mov ah, 0x0E
    mov al, 13
    int 0x10
    mov al, 10
    int 0x10
    jmp halt

; command for bootloader to print text to console
print_string:
    lodsb               ; Load byte from [ds:si] into al, increment si, ds is data segment default for reading data
    cmp al, 0           ; is the byte the null terminator?
    je .done            ; if it's yes then the program's done

    mov ah, 0x0E        ; BIOS teletype output
    int 0x10            ; Call bios video interrupt
    jmp print_string    ; loop to the next character

.done:
    ret                 ; return from subroutine

print_hex8:
    push ax             ; push ax to disk
    mov ah, al
    shr al, 4
    call print_hex_nibble
    mov al, ah
    and al, 0x0F
    call print_hex_nibble
    pop ax
    ret


print_hex_nibble:
    and al, 0x0F
    cmp al, 9
    jbe .digit
    add al, 7

.digit:
    add al, '0'
    mov ah, 0x0E
    int 0x10
    ret





halt:
    hlt                 ; halt the cpu
    jmp halt            ; infinite loop just in case


boot_msg:
    db "CircleOS v", VER_MAJOR_STR, ".", VER_MINOR_STR, ".", VER_PATCH_STR, " by SuperCode Studios", 13, 10        ; Dynamic OS version numbering
    db "BOOTLOADER v", VER_BOOTLOADER_STR, 13, 10           ; output bootloader version
    db "Loading interactive kernel...", 13, 10, 0 

kernel_msg:
    db "Kernel successfully loaded. Jumping...", 13, 10, 0          ; kernel loaded message

disk_error_msg:
    db "DISK ERROR: Failed to load kernel.", 13, 10
    db "ERROR AH=0x", 0

disk_status:
    db 0

retry_count:
    db 1

; padding to fill space with zeros so it is 510 bytes
times (510 - ($ - $$)) db 0


; boot signature to tell BIOS this is bootable
dw 0xAA55