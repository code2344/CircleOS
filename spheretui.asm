; spheretui.asm - Sphere GUI launcher scaffold (graphics-first stub)
; Purpose:
;   - Replaces old text TUI implementation.
;   - Enters VGA mode 13h (320x200x256).
;   - Provides TODO hooks for GUI render/update/input/launcher logic.
;   - Returns safely to text mode (0x03) on exit.
;
; Notes:
;   - This file intentionally does NOT implement widgets/windows/desktop yet.
;   - Backbuffer is a fixed RAM region at DS:BACKBUFFER_OFF.
;   - Kernel syscalls used:
;       0x10 set video mode (AL = 0x03 text, AL = 0x13 graphics)
;       0x11 present framebuffer (DS:SI -> 64000-byte buffer)

[BITS 16]
[ORG 0xA000]

SYSCALL_INT equ 0x80
SYS_PUTC equ 0x01
SYS_PUTS equ 0x02
SYS_NEWLINE equ 0x03
SYS_GETC equ 0x04
SYS_RUN equ 0x06
SYS_SET_VIDEO_MODE equ 0x10
SYS_PRESENT_FRAMEBUFFER equ 0x11

KEY_ESC equ 27

; Mode 13h geometry.
SCREEN_W equ 320
SCREEN_H equ 200
SCREEN_BYTES equ 64000

; Backbuffer location in low RAM (segment 0x0000).
; Keep this away from kernel FS scratch buffers at 0x1200..0x16FF.
BACKBUFFER_OFF equ 0x2000

start:
    ; Programs run with DS=0 convention in CircleOS userland.
    xor ax, ax
    mov ds, ax
    mov es, ax

    ; Switch from text mode to graphics mode 13h.
    mov al, 0x13
    call sys_set_video_mode

    ; Initial clear so first frame is predictable.
    call clear_backbuffer

    ; TODO: Draw your initial GUI frame here.
    ; Example ideas:
    ;   - desktop background
    ;   - launcher bar
    ;   - app tiles / shortcut dock
    ;   - status text
    call gui_draw_frame

    ; Present once before entering loop.
    mov si, BACKBUFFER_OFF
    call sys_present_framebuffer

.gui_loop:
    ; Poll one key (blocking for now).
    call sys_getc

    ; ESC exits GUI launcher back to shell.
    cmp al, KEY_ESC
    je .exit_gui

    ; TODO: Route keyboard commands into your GUI input handler.
    ; You can map keys to launcher actions here (e.g., Enter = launch selected).
    call gui_handle_input

    ; TODO: Update animations, selection, focus, cursor, etc.
    call gui_update

    ; TODO: Render full frame into RAM backbuffer.
    call gui_draw_frame

    ; Blit backbuffer to VGA once per frame (prevents flicker).
    mov si, BACKBUFFER_OFF
    call sys_present_framebuffer

    jmp .gui_loop

.exit_gui:
    ; Always restore text mode so csh remains usable.
    mov al, 0x03
    call sys_set_video_mode

    ; Optional text confirmation after mode restore.
    mov si, msg_exit
    call sys_puts
    call sys_newline
    ret

; -----------------------------------------------------------------------------
; GUI TODO hooks (intentionally empty scaffolding)
; -----------------------------------------------------------------------------

gui_handle_input:
    ; TODO:
    ;   - map keys to launcher commands
    ;   - map numeric shortcuts to app IDs
    ;   - trigger launch_selected_app when needed
    ret

gui_update:
    ; TODO:
    ;   - animation timing
    ;   - focus/selection updates
    ;   - app/task state bookkeeping
    ret

gui_draw_frame:
    ; TODO:
    ;   - draw background into backbuffer
    ;   - draw panels/windows
    ;   - draw text via your upcoming font renderer
    ;   - keep all drawing inside your desired viewport contract
    ;
    ; Current placeholder: solid color clear only.
    call clear_backbuffer
    ret

launch_selected_app:
    ; TODO:
    ;   - set SI to selected app program name string
    ;   - call sys_run
    ;   - handle AH status (0=ok, 1=not found, 2=load fail, 3=unavailable)
    ;
    ; Example template:
    ;   mov si, app_name_example
    ;   call sys_run
    ;   cmp ah, 0
    ;   jne .launch_fail
    ;   ret
    ; .launch_fail:
    ;   ; TODO: surface error in GUI status bar
    ;   ret
    ret

; -----------------------------------------------------------------------------
; Low-level helpers
; -----------------------------------------------------------------------------

clear_backbuffer:
    ; Fill 64000 bytes at DS:BACKBUFFER_OFF with color 0x00 (black).
    ; Uses ES:DI for stosb destination.
    push es
    push di
    push cx
    push ax

    xor ax, ax
    mov es, ax
    mov di, BACKBUFFER_OFF
    xor al, al
    mov cx, SCREEN_BYTES
    rep stosb

    pop ax
    pop cx
    pop di
    pop es
    ret

sys_set_video_mode:
    ; Input: AL = BIOS video mode.
    ; Uses syscall 0x10 implemented in kernel.
    mov ah, SYS_SET_VIDEO_MODE
    int SYSCALL_INT
    ret

sys_present_framebuffer:
    ; Input: DS:SI = source backbuffer pointer (64000 bytes).
    ; Uses syscall 0x11 implemented in kernel.
    mov ah, SYS_PRESENT_FRAMEBUFFER
    int SYSCALL_INT
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

sys_run:
    mov ah, SYS_RUN
    int SYSCALL_INT
    ret

; -----------------------------------------------------------------------------
; Data
; -----------------------------------------------------------------------------

msg_exit:
    db "sphere gui launcher exited", 0

; TODO: define launcher app names here.
; app_name_example:
;     db "calculator", 0
