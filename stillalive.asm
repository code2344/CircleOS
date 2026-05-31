[BITS 16]
[ORG 0xA000]

SYSCALL_INT equ 0x80
SYS_CLEAR   equ 0x05

LYRIC_WIDTH      equ 38
CREDITS_WIDTH    equ 38
CREDITS_HEIGHT   equ 2
LYRIC_HEIGHT     equ 22
CREDITS_POS_X    equ 42      ; 1-based
ASCII_ART_X      equ 41      ; 1-based
ASCII_ART_Y      equ 5       ; 1-based

EVENT_SIZE equ 8

set_flat_ds:
    mov ax, 0
    mov ds, ax
    ret

start:
    mov ax, 0
    mov ds, ax
    mov es, ax

    mov ah, SYS_CLEAR
    int SYSCALL_INT

    call draw_frame
    mov ax, 1000
    call wait_ms

    mov byte [lyric_x], 0
    mov byte [lyric_y], 0
    mov byte [credits_enabled], 0
    mov word [credits_index], 0
    mov byte [credits_have_two], 0
    mov byte [credit_line_len], 0

    call clear_credit_lines
    call mark_start_ticks

    mov bx, lyric_events

.event_loop:
    call set_flat_ds
    ; read event
    mov ax, [bx + 0]                  ; target time (centiseconds)
    mov [tmp_target_cs], ax

.wait_event:
    call update_credits
    call get_elapsed_cs
    cmp ax, [tmp_target_cs]
    jae .run_event
    mov ax, 10
    call wait_ms
    jmp .wait_event

.run_event:
    mov al, [bx + 2]                  ; mode
    cmp al, 9
    je .done

    cmp al, 0
    je .mode_lyric_newline
    cmp al, 1
    je .mode_lyric_inline
    cmp al, 2
    je .mode_art
    cmp al, 3
    je .mode_clear
    cmp al, 4
    je .next_event                     ; audio ignored by request
    cmp al, 5
    je .mode_credits_start
    jmp .next_event

.mode_lyric_newline:
    mov si, [bx + 4]
    mov ax, [bx + 6]
    mov [tmp_char_delay_ms], ax
    mov byte [tmp_newline_flag], 1
    call draw_lyric_text
    jmp .next_event

.mode_lyric_inline:
    mov si, [bx + 4]
    mov ax, [bx + 6]
    mov [tmp_char_delay_ms], ax
    mov byte [tmp_newline_flag], 0
    call draw_lyric_text
    jmp .next_event

.mode_art:
    mov al, [bx + 3]
    call draw_ascii_art
    jmp .next_event

.mode_clear:
    call clear_lyrics
    mov byte [lyric_x], 0
    mov byte [lyric_y], 0
    jmp .next_event

.mode_credits_start:
    mov byte [credits_enabled], 1
    call get_elapsed_cs
    mov [credits_start_cs], ax
    jmp .next_event

.next_event:
    add bx, EVENT_SIZE
    jmp .event_loop

.done:
    ret

; ------------------------
; Timing helpers
; ------------------------
mark_start_ticks:
    mov ah, 0x00
    int 0x1A
    mov [start_tick], dx
    ret

; AX = elapsed centiseconds
get_elapsed_cs:
    push bx
    push dx

    mov ah, 0x00
    int 0x1A
    sub dx, [start_tick]
    mov ax, dx
    mov bx, 549
    mul bx                             ; DX:AX = ticks * 549
    mov bx, 100
    div bx                             ; AX = centiseconds

    pop dx
    pop bx
    ret

; AX = milliseconds to wait
wait_ms:
    push ax
    push bx
    push dx

    ; Convert ms to centiseconds, rounding up for non-zero waits.
    ; This avoids int 15h AH=86, which may block on some emulators.
    xor dx, dx
    mov bx, 10
    div bx                             ; AX = ms/10, DX = ms%10
    test dx, dx
    jz .wm_have_cs
    inc ax
.wm_have_cs:
    mov [tmp_wait_cs], ax

    cmp ax, 0
    je .wm_done

    call get_elapsed_cs
    mov bx, ax                         ; start cs

.wm_loop:
    call get_elapsed_cs
    sub ax, bx
    cmp ax, [tmp_wait_cs]
    jae .wm_done
    jmp .wm_loop

.wm_done:
    pop dx
    pop bx
    pop ax
    ret

; ------------------------
; BIOS display primitives
; ------------------------
; input: DH=row(0-based), DL=col(0-based)
move_cursor:
    mov ah, 0x02
    mov bh, 0
    int 0x10
    ret

; input: AL=char
putc_tty:
    mov ah, 0x0E
    mov bh, 0
    mov bl, 0x07
    int 0x10
    ret

; input: DS:SI -> null-terminated string
puts_tty:
    call set_flat_ds
.ps_loop:
    lodsb
    test al, al
    jz .ps_done
    call putc_tty
    jmp .ps_loop
.ps_done:
    ret

; input: DH=row, DL=col, DS:SI string
print_at:
    push dx
    call move_cursor
    call puts_tty
    pop dx
    ret

; ------------------------
; UI drawing
; ------------------------
draw_frame:
    ; row 1
    mov dh, 0
    mov dl, 0
    mov si, top_border
    call print_at

    ; rows 2..3 credits area split
    mov dh, 1
    mov dl, 0
    mov si, credits_row
    call print_at

    mov dh, 2
    mov dl, 0
    mov si, credits_row
    call print_at

    ; row 4 separator
    mov dh, 3
    mov dl, 0
    mov si, split_row
    call print_at

    ; rows 5..23 lyric rows
    mov dh, 4
.df_loop:
    cmp dh, 23
    ja .df_bottom
    mov dl, 0
    mov si, lyric_row
    call print_at
    inc dh
    jmp .df_loop

.df_bottom:
    mov dh, 23
    mov dl, 0
    mov si, lyric_bottom
    call print_at
    ret

clear_lyrics:
    mov dh, 1                           ; row 2
.cl_loop:
    cmp dh, 22                          ; row 23
    ja .cl_done
    mov dl, 0
    mov si, lyric_row
    call print_at
    inc dh
    jmp .cl_loop
.cl_done:
    ret

clear_credit_lines:
    mov byte [credit_line0 + 0], 0
    mov byte [credit_line1 + 0], 0
    ret

; input: SI text ptr, [tmp_char_delay_ms], [tmp_newline_flag]
draw_lyric_text:
    call set_flat_ds
    ; cursor to lyric text area
    mov dh, [lyric_y]
    inc dh                              ; +1 for BIOS row from python y+2 => 0-based y+1
    mov dl, [lyric_x]
    inc dl
    call move_cursor

.dlt_loop:
    lodsb
    test al, al
    jz .dlt_done
    call putc_tty

    ; keep credits moving during char output
    call update_credits

    ; per-char delay
    mov ax, [tmp_char_delay_ms]
    test ax, ax
    jz .dlt_no_delay
    call wait_ms
.dlt_no_delay:

    inc byte [lyric_x]
    jmp .dlt_loop

.dlt_done:
    cmp byte [tmp_newline_flag], 0
    je .dlt_ret
    mov byte [lyric_x], 0
    inc byte [lyric_y]
.dlt_ret:
    ret

; input: AL art index 0..9
draw_ascii_art:
    call set_flat_ds
    push ax
    push bx
    push cx
    push dx
    push si

    xor ah, ah
    shl ax, 1
    mov si, art_table
    add si, ax
    mov si, [si]                        ; SI points to first row string

    mov cx, 20
    xor bx, bx
.da_row_loop:
    mov dh, ASCII_ART_Y - 1
    add dh, bl
    mov dl, ASCII_ART_X - 1
    call print_at

    ; advance SI to next row string
.da_next_str:
    cmp byte [si], 0
    je .da_advance
    inc si
    jmp .da_next_str
.da_advance:
    inc si

    mov ax, 10
    call wait_ms

    inc bl
    loop .da_row_loop

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ------------------------
; Credits update
; ------------------------
update_credits:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    cmp byte [credits_enabled], 1
    jne .uc_done

    call get_elapsed_cs
    sub ax, [credits_start_cs]
    mov bx, STILLALIVE_CREDITS_LEN
    mul bx                              ; DX:AX = elapsed_cs * len
    mov bx, 17400
    div bx                              ; AX = expected characters emitted
    mov [tmp_expected_credits], ax

.uc_emit_loop:
    mov ax, [credits_index]
    cmp ax, [tmp_expected_credits]
    jae .uc_done
    cmp ax, STILLALIVE_CREDITS_LEN
    jae .uc_done

    mov si, credits_text
    add si, ax
    mov al, [si]
    inc word [credits_index]

    cmp al, 10
    je .uc_newline

    ; regular character into current bottom line
    mov bl, [credit_line_len]
    cmp bl, CREDITS_WIDTH
    jae .uc_emit_loop

    mov di, credit_line1
    xor bh, bh
    add di, bx
    mov [di], al
    inc bl
    mov [credit_line_len], bl

    ; keep null terminator valid
    mov di, credit_line1
    xor bh, bh
    add di, bx
    mov byte [di], 0

    call redraw_credits_window
    jmp .uc_emit_loop

.uc_newline:
    ; shift line1 -> line0
    call shift_credit_lines
    mov byte [credits_have_two], 1
    call redraw_credits_window
    jmp .uc_emit_loop

.uc_done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

shift_credit_lines:
    push si
    push di
    mov si, credit_line1
    mov di, credit_line0
.scl_copy0:
    mov al, [si]
    mov [di], al
    inc si
    inc di
    cmp al, 0
    jne .scl_copy0

    mov byte [credit_line1], 0
    mov byte [credit_line_len], 0

    pop di
    pop si
    ret

redraw_credits_window:
    ; top row (row 2 => BIOS 1)
    cmp byte [credits_have_two], 1
    je .rcw_top_line
    mov dh, 1
    mov dl, CREDITS_POS_X - 1
    mov si, blank_credits
    call print_at
    jmp .rcw_bottom

.rcw_top_line:
    mov dh, 1
    mov dl, CREDITS_POS_X - 1
    mov si, credit_line0
    call print_at
    mov dh, 1
    mov dl, CREDITS_POS_X - 1
    mov si, blank_credits
    call print_at
    mov dh, 1
    mov dl, CREDITS_POS_X - 1
    mov si, credit_line0
    call print_at

.rcw_bottom:
    mov dh, 2
    mov dl, CREDITS_POS_X - 1
    mov si, blank_credits
    call print_at
    mov dh, 2
    mov dl, CREDITS_POS_X - 1
    mov si, credit_line1
    call print_at
    ret

; ------------------------
; Static layout strings
; ------------------------
top_border:
    db " --------------------------------------  -------------------------------------- ", 0
credits_row:
    db "|                                      ||                                      |", 0
split_row:
    db "|                                      | -------------------------------------- ", 0
lyric_row:
    db "|                                      |", 0
lyric_bottom:
    db " -------------------------------------- ", 0
blank_credits:
    db "                                      ", 0

; ------------------------
; Runtime state
; ------------------------
start_tick:             dw 0
tmp_target_cs:          dw 0
tmp_char_delay_ms:      dw 0
tmp_wait_cs:            dw 0
tmp_expected_credits:   dw 0
credits_start_cs:       dw 0
credits_index:          dw 0
lyric_x:                db 0
lyric_y:                db 0
tmp_newline_flag:       db 0
credits_enabled:        db 0
credits_have_two:       db 0
credit_line_len:        db 0
credit_line0:           times (CREDITS_WIDTH + 1) db 0
credit_line1:           times (CREDITS_WIDTH + 1) db 0

%include "stillalive_data.inc"
