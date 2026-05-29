[BITS 16]
[ORG 0xA000]

SYSCALL_INT equ 0x80
SYS_PUTS equ 0x02
SYS_NEWLINE equ 0x03
SYS_PUTC equ 0x01

NE2K_BASE equ 0x300

NE2K_CMD    equ NE2K_BASE + 0x00
NE2K_PSTART equ NE2K_BASE + 0x01
NE2K_PSTOP  equ NE2K_BASE + 0x02
NE2K_BNRY   equ NE2K_BASE + 0x03
NE2K_TPSR   equ NE2K_BASE + 0x04
NE2K_TBCR0  equ NE2K_BASE + 0x05
NE2K_TBCR1  equ NE2K_BASE + 0x06
NE2K_ISR    equ NE2K_BASE + 0x07
NE2K_RSAR0  equ NE2K_BASE + 0x08
NE2K_RSAR1  equ NE2K_BASE + 0x09
NE2K_RBCR0  equ NE2K_BASE + 0x0A
NE2K_RBCR1  equ NE2K_BASE + 0x0B
NE2K_RCR    equ NE2K_BASE + 0x0C
NE2K_TCR    equ NE2K_BASE + 0x0D
NE2K_DCR    equ NE2K_BASE + 0x0E
NE2K_IMR    equ NE2K_BASE + 0x0F
NE2K_RESET  equ NE2K_BASE + 0x1F

CMD_STOP    equ 0x01
CMD_START   equ 0x02
CMD_TXP     equ 0x04
CMD_PAGE0   equ 0x00
CMD_PAGE1   equ 0x40

RX_START    equ 0x40
RX_STOP     equ 0x80
TX_PAGE     equ 0x40

start:
    mov ax, 0
    mov ds, ax
    call ne2k_init


hang:
    hlt
    jmp hang

ne2k_init:
    ;reset card
    mov dx, NE2K_RESET
    in al, dx

    ;stop nic and select page 0
    mov dx, NE2K_CMD
    mov al, CMD_STOP | CMD_PAGE0
    out dx, al

    ;set data configuration: 8-bit, loopback mode
    mov dx, NE2K_DCR
    mov al, 0x49
    out dx, al


    ; set recieve ring and tx page
    mov dx, NE2K_PSTART
    mov al, RX_START
    out dx, al

    mov dx, NE2K_PSTOP
    mov al, RX_STOP
    out dx, al

    mov dx, NE2K_TPSR
    mov al, TX_PAGE
    out dx, al

    ;switch to page 1 and load MAC and CURR
    mov dx, NE2K_CMD
    mov al, CMD_STOP | CMD_PAGE1
    out dx, al

    ;physical address registers PAR0-5
    mov si, mac_address
    mov dx, NE2K_BASE + 0x01
    mov cx, 6
.write_mac
    lodsb
    out dx, al
    inc dx
    loop .write_mac

    ;current page pointer for receive ring
    mov dx, NE2K_BASE + 7
    mov al, RX_START + 1
    out dx, al

    ; back to page 0
    mov dx, NE2K_CMD
    mov al, CMD_STOP | CMD_PAGE0
    out dx, al

    ;clear pending interrupts
    mov dx, NE2K_ISR
    mov al, 0xFF
    out dx, al

    ; accept physical + broadcast packets
    mov dx, NE2K_RCR
    mov al, 0x04
    out dx, al

    ; put tx in normal mode
    mov dx, NE2K_TCR
    xor al, al
    out dx, al

    ; enable interrupts (none should be pending)
    mov dx, NE2K_IMR
    mov al, 0x3F
    out dx, al

    ; start the card
    mov dx, NE2K_CMD
    mov al, CMD_START | CMD_PAGE0
    out dx, al

    ret

mac_address:
    db 0x52, 0x54, 0x00, 0x12, 0x34, 0x56 ; QEMU's default MAC address, should be unique on your network if you're using bridged networking

