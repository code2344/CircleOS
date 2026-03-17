; SuperCodeOS 512-byte initial bootloader
; Made by Ruben Sutton
; Last updated: 17 March 2026
; Find me at https://scstudios.tech

[BITS 16]           ; 16 bit real mode
[ORG 0x7C00]        ; code loaded at address 0x7C00

start:
    mov ax, 0           ; set up registers for the data segment
    mov ds, ax
    mov es, ax
    
    mov si, boot message     ; SI is the address of the message string
    call print_string

    ; load the kernel from disk sector 2, 1 is bootloader
    mov ax, 0x0201              ; AH = 0x02 (read), AL=0x01 (1 sector)
    mov bx, 0x7E00              ; Load the kernel at 0x7E00 (right after the bootloader which is at 7c00)
    mov cx, 0x0002
    mov dx, 0x0000
    int 0x13



print_string:
    lodsb               ; Load byte from [ds:si] into al, increment si
    cmp al, 0           ; is the byte the null terminator?
    je .done            ; if it's yes then the program's done

    mov ah, 0x0E        ; BIOS teletype output
    int 0x10            ; Call bios video interrupt
    jmp print_string    ; loop to the next character

.done:
    ret                 ; return from subroutine


halt:
    hlt                 ; halt the cpu
    jmp halt            ; infinite loop just in case


message:
    db "Hello from SuperCodeOS", 0      ; Null-terminated string

; padding to fill space with zeros
times (510 - ($ - $$)) db 0


; boot signature to tell BIOS this is bootable
dw 0xAA55