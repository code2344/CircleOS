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
