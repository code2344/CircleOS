; cat.asm - Read and print text files from filesystem
; User program at 0xA000. Takes filename as input and prints file contents.

[BITS 16]               ; 16-bit x86 real-mode
[ORG 0xA000]            ; Loaded at this address by kernel

SYSCALL_INT equ 0x80
SYS_PUTC equ 0x01       ; print single character
SYS_PUTS equ 0x02       ; print null-terminated string
SYS_NEWLINE equ 0x03    ; print CR+LF
SYS_GETC equ 0x04       ; read keystroke
SYS_READ_RAW equ 0x07   ; read sectors by CHS
CTRL_C equ 0x03         ; user abort key

; Program table in kernel memory
PROG_TABLE_ADDR equ 0x0600 ; where kernel stores program entries
PROG_ENTRY_SIZE equ 16     ; bytes per table entry
PROG_NAME_LEN equ 8        ; filename max length in table
ENTRY_TYPE_TEXT equ 2      ; type code for text files

start:
    mov ax, 0
    mov ds, ax              ; DS = 0: direct memory access (real mode absolute addresses)
    mov es, ax              ; ES = 0: for accessing kernel program table at 0x0600

    mov si, msg_title       ; SI -> greeting message
    call sys_puts           ; print welcome message

    mov si, msg_prompt      ; SI -> "Enter filename:" prompt
    call sys_puts           ; display prompt to user
    call read_line          ; read filename from keyboard (up to 31 chars + null terminator)

    ; Check for user abort: read_line sets name_buf[0]=0x03 if Ctrl-C was pressed
    cmp byte [name_buf], CTRL_C
    je .cancelled            ; user cancelled input, exit cleanly

    ; Check for empty input: read_line left null terminator at name_buf[0] if user hit Enter
    cmp byte [name_buf], 0
    je .usage                ; no filename provided, show usage instructions

    ; Search kernel's program table for a matching text file entry
    ; The kernel maintains a 10-entry table at 0x0600 with file metadata:
    ; Each entry: 8-byte name, 1-byte type, 1-byte sector, 1-byte count, 5-byte reserved
    mov si, name_buf        ; SI -> user-entered filename (null-terminated)
    call find_text_entry    ; search for matching entry in table
    cmp al, 1               ; AL=1 if found and is text type, AL=0 if not found
    jne .not_found          ; jump if file not in table or wrong type

    ; Load file content from disk using CHS (Cylinder/Head/Sector) addressing
    ; Note: CHS is legacy floppy/IDE addressing - kernel abstracts sector numbers
    mov bx, file_buf        ; BX -> destination buffer (1024 bytes allocated)
    mov al, [file_count]    ; AL = number of sectors to read (from table entry)
    mov ch, 0               ; CH = cylinder number (ignored by kernel, set to 0)
    mov cl, [file_sector]   ; CL = starting sector number from table (1-based numbering)
    mov dh, 0               ; DH = head number (ignored by kernel, set to 0)
    mov ah, SYS_READ_RAW    ; prepare syscall 0x07: kernel reads sectors to buffer
    int SYSCALL_INT         ; call kernel, kernel reads AL sectors starting at CL
    cmp ah, 0               ; kernel returns error code in AH (0=success)
    jne .read_fail          ; non-zero AH means read error

    ; Display file contents: kernel read data into buffer, now print to console
    mov si, file_buf        ; SI -> file data loaded into memory
    call sys_puts           ; print buffer contents as null-terminated string
    call sys_newline        ; terminate output with newline
    ret                     ; return to shell

.cancelled:
    ret                     ; return to shell

.usage:
    mov si, msg_usage
    call sys_puts
    call sys_newline
    ret

.not_found:
    mov si, msg_not_found
    call sys_puts
    call sys_newline
    ret

.read_fail:
    mov si, msg_read_fail
    call sys_puts
    call sys_newline
    ret

; read_line - Read filename from keyboard with editing support
; The user can type up to 31 characters, with backspace to delete and Ctrl-C to abort.
; Input: (none - uses global name_buf buffer)
; Output: name_buf = null-terminated string (max 31 chars + null)
;         name_buf[0] = 0x03 if user pressed Ctrl-C (special abort signal)
;         name_buf[0] = 0x00 if user hit Enter with no input
read_line:
    xor cx, cx              ; CX = input position counter (start at 0)
    mov bx, name_buf        ; BX -> write position in name_buf

.read_loop:
    call sys_getc           ; kernel INT 0x04: wait for keystroke, return ASCII in AL

    ; Handle Ctrl+C (0x03): user abort signal
    cmp al, CTRL_C
    je .cancel              ; jump to cancel handler

    ; Handle Enter (0x0D): end of input
    cmp al, 13
    je .done                ; jump to finalization

    ; Handle Backspace (0x08): delete previous character
    cmp al, 8
    je .backspace           ; jump to backspace handler

    ; Regular character: echo to console and store in buffer
    call sys_putc           ; echo character back to user
    cmp cx, 31              ; already read 31 characters?
    jae .read_loop          ; yes, ignore this character (buffer full)

    mov si, cx              ; SI = position in buffer
    mov [bx + si], al       ; write character to buffer[position]
    inc cx                  ; increment character count
    jmp .read_loop          ; loop for next character

.backspace:
    cmp cx, 0               ; is buffer empty (no characters typed yet)?
    je .read_loop           ; yes, backspace is no-op

    ; Send VT100 backspace sequence to terminal: BS, space, BS
    ; This moves cursor back, overwrites char with space, moves back again
    mov al, 8               ; send backspace (0x08)
    call sys_putc           ; move cursor left
    mov al, ' '             ; send space character
    call sys_putc           ; overwrite the char position
    mov al, 8               ; send backspace again
    call sys_putc           ; move cursor back to previous position

    dec cx                  ; decrement position counter
    mov si, cx              ; SI = new end position
    mov byte [bx + si], 0   ; null-terminate string at new length
    jmp .read_loop          ; continue input loop

.cancel:
    mov byte [name_buf], CTRL_C  ; mark abort: set name_buf[0] to Ctrl-C (0x03)
    call sys_newline        ; newline for visual closure
    ret                     ; return to caller (main will detect CTRL_C)

.done:
    mov si, cx              ; SI = position after last character entered
    mov byte [bx + si], 0   ; null-terminate the string at position CX
    call sys_newline        ; print newline  to move to next line
    ret                     ; return to caller with name_buf ready

; find_text_entry - Search kernel's program table for matching filename
; The kernel maintains a 10-entry program table starting at 0x0600:
;   Offset 0-3: header info (count at offset 4)
;   Offset 16+: entry array (16 bytes per entry)
;   Each entry: [0-7]=name(8), [8]=sector, [9]=count, [14]=type
; Input: DS:SI -> user-entered filename (null-terminated)
; Output: AL = 1 if found and is TEXT type (file_sector/file_count set)
;         AL = 0 if not found or wrong type
find_text_entry:
    mov [name_ptr], si      ; save input filename pointer for comparison
    mov byte [entry_index], 0 ; initialize search position to 0

    mov bx, PROG_TABLE_ADDR ; BX -> program table base at 0x0600
    mov al, [es:bx + 4]     ; read entry count from table header (offset 4)
    mov [entry_count], al   ; store count for loop termination check

.search_loop:
    mov al, [entry_index]   ; AL = current entry being checked
    cmp al, [entry_count]   ; have we checked all entries in table?
    jae .no                 ; yes, exit with "not found" (AL=0)

    ; Calculate address of current table entry in memory
    ; Entry address = PROG_TABLE_ADDR (0x0600) + 16 (skip header) + (index * 16)
    xor ax, ax              ; clear AX for clean multiplication
    mov al, [entry_index]   ; AL = entry index (0, 1, 2, ...)
    shl ax, 4               ; AX = index << 4 = index * 16 (16 bytes per entry)
    mov di, PROG_TABLE_ADDR + 16 ; DI = base address of first entry
    add di, ax              ; DI -> current entry at 0x0600 + 16 + (index*16)

    ; Compare user's input filename with table entry's 8-byte name field
    mov si, [name_ptr]      ; SI -> user-entered filename from name_buf
    push di                 ; save DI (current entry pointer)
    call str_eq_entry_name  ; compare strings, returns AL=1 if match
    pop di                  ; restore DI
    cmp al, 1               ; did the filenames match?
    jne .next               ; no match, continue searching next entry

    ; Filename matched! Now check if this entry is a text file (type=2)
    mov bx, di              ; BX -> current entry
    cmp byte [es:bx + 14], ENTRY_TYPE_TEXT ; check type field at offset 14
    jne .next               ; type is not TEXT, skip this entry and continue searching

    ; Found a text-type file with matching name. Extract disk location metadata.
    mov al, [es:bx + 8]     ; read starting sector from entry offset 8
    mov [file_sector], al   ; save to file_sector variable
    mov al, [es:bx + 9]     ; read sector count from entry offset 9
    mov [file_count], al    ; save to file_count variable
    mov al, 1               ; AL = 1: success signal
    ret                     ; return with AL=1 (found)

.next:
    inc byte [entry_index]  ; move to next entry in table
    jmp .search_loop        ; continue searching

.no:
    xor al, al              ; AL = 0 (not found)
    ret

; str_eq_entry_name - Compare two filenames accounting for table field padding
; User's filename is null-terminated (variable length).
; Table entry name is 8-byte fixed field, padded with nulls if shorter.
; Input: DS:SI -> user-entered filename (null-terminated)
;        ES:DI -> table entry's name field (fixed 8-byte field at entry+0)
; Output: AL = 1 if names match, 0 if different
str_eq_entry_name:
    mov cx, PROG_NAME_LEN   ; CX = comparison limit (8 bytes max for name field)

.cmp_loop:
    mov al, [si]            ; AL = next byte from user input
    mov bl, [es:di]         ; BL = next byte from table entry name field
    cmp al, bl              ; compare bytes
    jne .no                 ; bytes differ, names don't match

    ; Bytes match. Check for null terminator (end of string).
    cmp al, 0               ; is AL == 0 (null terminator found)?
    je .yes                 ; yes, both strings end here - perfect match

    ; Both bytes matched and not null, continue comparing next positions
    inc si                  ; advance user string pointer
    inc di                  ; advance table field pointer
    dec cx                  ; decrement remaining bytes in 8-byte field
    jnz .cmp_loop           ; continue comparing if field not exhausted

    ; Reached 8-byte field limit. User string must be null-terminated here.
    cmp byte [si], 0        ; is next byte of user string a null terminator?
    je .yes                 ; yes, user string ends at field boundary

.no:
    xor al, al              ; AL = 0: not found (clear AL register)
    ret                     ; return to caller

.yes:
    mov al, 1               ; AL = 1: match found (set AL to 1)
    ret                     ; return to caller

; ================== SYSCALL WRAPPER FUNCTIONS ==================
; These are thin wrappers around kernel syscalls (INT 0x80).
; Each syscall requires specific register setup before INT 0x80.

; sys_putc - Print single character to console
; Input: AL = ASCII code to print
sys_putc:
    mov ah, SYS_PUTC        ; AH = 0x01: syscall for single character output
    int SYSCALL_INT         ; INT 0x80: call kernel, kernel prints from AL
    ret                     ; return to caller

; sys_puts - Print null-terminated string to console
; Input: DS:SI = address of null-terminated string
sys_puts:
    mov ah, SYS_PUTS        ; AH = 0x02: syscall for string output
    int SYSCALL_INT         ; INT 0x80: call kernel, kernel prints from DS:SI
    ret                     ; return to caller

; sys_newline - Print carriage return + line feed
sys_newline:
    mov ah, SYS_NEWLINE     ; AH = 0x03: syscall for newline
    int SYSCALL_INT         ; INT 0x80: call kernel, kernel prints CR+LF
    ret

; sys_getc - Wait for and read keystroke from keyboard
; Output: AL = ASCII character code of key pressed (blocking call)
sys_getc:
    mov ah, SYS_GETC        ; AH = 0x04: syscall for character input
    int SYSCALL_INT         ; INT 0x80: call kernel, kernel waits for key, returns in AL
    ret                     ; return with character in AL

; ================== MESSAGES AND DATA ==================

msg_title:
    db "cat - print text file", 13, 10, 0  ; greeting: "cat - print text file" + CR+LF + null
msg_prompt:
    db "file> ", 0          ; prompt message: "file> " + null terminator
msg_usage:
    db "usage: cat then enter <name>", 0  ; usage info: displays when user enters nothing
msg_not_found:
    db "file not found", 0  ; error: filename not in program table
msg_read_fail:
    db "file read failed", 0  ; error: disk read operation failed

; ================== WORKING VARIABLES ==================

entry_count: db 0           ; number of entries in program table (0-10)
entry_index: db 0           ; current position while searching program table
file_sector: db 0           ; starting sector for file (read from table entry offset 8)
file_count: db 0            ; number of sectors to read (read from table entry offset 9)
name_ptr: dw 0              ; pointer to user-entered filename (16-bit far pointer)

; ================== BUFFERS ==================

name_buf:
    times 32 db 0           ; 32-byte buffer for user-entered filename (31 chars + null)

file_buf:
    times 1024 db 0         ; 1024-byte buffer for file content loaded from disk
    db "cat - print text file", 13, 10, 0
