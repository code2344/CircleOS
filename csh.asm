; csh.asm - CIRCLE SHELL - Interactive command interpreter and script executor
; Load address: 0x9000 (loaded by kernel after boot)
; Purpose: Main user interface for CircleOS, dispatching commands and managing filesystem
; Commands: help, clear, echo, run, mkdir, rm, cd, arc (script), exit
;
; ARCHITECTURE:
; - Main REPL loop: prompt user, read command, dispatch to handler
; - Command dispatch: string matching against built-in command names
; - Filesystem operations: mkdir, rm, cd via kernel syscalls (SYS_FS_*)
; - Script execution: ARC interpreter loads script file, executes line-by-line
; - All commands fall back to sys_run for builtin/program execution

[BITS 16]
[ORG 0x9000]

SYSCALL_INT equ 0x80
SYS_PUTC equ 0x01
SYS_PUTS equ 0x02
SYS_NEWLINE equ 0x03
SYS_GETC equ 0x04
SYS_CLEAR equ 0x05
SYS_RUN equ 0x06
SYS_FS_READ equ 0x09
SYS_FS_DELETE equ 0x0C
SYS_FS_MKDIR equ 0x0D
SYS_FS_CHDIR equ 0x0E
CTRL_C equ 0x03
ARC_BUF_SIZE equ 1024

start:
    xor ax, ax
    mov ds, ax              ; DS = 0: direct memory access to entire address space

    mov si, shell_banner    ; SI -> welcome message
    call sys_puts           ; print "Circle Shell interactive mode v0.1.22"
    call sys_newline

.shell_loop:                ; MAIN LOOP: wait for user input and dispatch commands
    mov si, shell_prompt    ; SI -> prompt string "csh> "
    call sys_puts           ; display prompt

    ; Read command line from keyboard with editing support
    xor cx, cx              ; CX = number of characters typed (0 to 31)
    mov bx, cmd_buf         ; BX -> 32-byte command buffer at 0x9000+offset

.read_loop:                 ; CHARACTER INPUT LOOP: read one keystroke at a time
    call sys_getc           ; kernel INT 0x04: wait for key into AL

    cmp al, CTRL_C          ; user pressed Ctrl+C?
    je .cancel_input        ; discard buffer and prompt again

    cmp al, 13              ; carriage return (Enter key)?
    je .command_ready       ; input complete, dispatch command

    cmp al, 8               ; backspace key?
    je .backspace           ; erase last character

    call sys_putc           ; echo character to console

    cmp cx, 31              ; already 31 characters in buffer?
    jge .read_loop          ; yes, ignore further input (buffer full)
    
    mov si, cx              ; SI = current position in buffer
    mov byte [bx + si], al  ; write character to buffer[CX]
    inc cx                  ; increment character count
    jmp .read_loop          ; wait for next keystroke

.cancel_input:
    call sys_newline        ; visual feedback for abort
    jmp .shell_loop         ; restart with new prompt

.backspace:
    cmp cx, 0               ; no characters to delete?
    je .read_loop           ; ignore if buffer empty

    ; Send VT100 backspace sequence to terminal: BS, space, BS
    mov al, 8               ; backspace character
    call sys_putc           ; move cursor left
    mov al, ' '             ; overwrite with space
    call sys_putc
    mov al, 8               ; backspace again
    call sys_putc           ; cursor now back to previous position

    dec cx                  ; decrement character count
    jmp .read_loop          ; continue input loop

.command_ready:
    mov si, cx              ; SI = length of input (position after last char)
    mov byte [bx + si], 0   ; null-terminate command string
    call sys_newline        ; move cursor to next line

    cmp byte [cmd_buf], 0   ; did user just press Enter with no input?
    je .shell_loop          ; yes, show prompt again

    ; ================== BUILT-IN COMMAND DISPATCH ==================
    ; Each command is checked via string comparison (exact match or prefix)
    
    ; "help" - show available commands
    mov si, cmd_buf         ; SI -> user-entered command
    mov di, cmd_help        ; DI -> "help" string
    call str_eq             ; compare for exact match
    cmp al, 1
    je .cmd_help            ; match found, jump to help handler

    ; "clear" - clear screen
    mov si, cmd_buf
    mov di, cmd_clear
    call str_eq
    cmp al, 1
    je .cmd_clear           ; exact match with "clear"

    ; "echo <text>" - print text (handle both "echo" prefix and standalone)
    mov si, cmd_buf
    mov di, cmd_echo_prefix ; check for "echo " (with space)
    call str_startswith     ; check if command starts with "echo "
    cmp al, 1
    je .cmd_echo            ; prefix matched, print text after "echo "

    ; "echo" alone - just newline
    mov si, cmd_buf
    mov di, cmd_echo        ; check for exact "echo"
    call str_eq
    cmp al, 1
    je .cmd_echo_empty      ; exact match, print nothing

    ; "exit" - return to kernel
    mov si, cmd_buf
    mov di, cmd_exit
    call str_eq
    cmp al, 1
    je .cmd_exit            ; jump to exit handler

    ; ================== PROGRAM LAUNCHING ==================
    ; "run" command family: runs programs from the program table
    
    ; "run <name>" - explicitly run a program
    mov si, cmd_buf
    mov di, cmd_run_prefix  ; check for "run " prefix
    call str_startswith
    cmp al, 1
    je .cmd_run             ; prefix matched, run specified program

    ; "run" alone - show usage
    mov si, cmd_buf
    mov di, cmd_run         ; exact match for "run"
    call str_eq
    cmp al, 1
    je .cmd_run_usage       ; show usage message

    ; "cat <path>" - print file contents directly from filesystem
    ; (plain "cat" still falls through to program launch behavior)
    mov si, cmd_buf
    mov di, cmd_cat_prefix
    call str_startswith
    cmp al, 1
    je .cmd_cat

    ; "ls <path>" - run ls program (path currently ignored by ls.asm)
    mov si, cmd_buf
    mov di, cmd_ls_prefix
    call str_startswith
    cmp al, 1
    je .cmd_ls

    ; "ls" alone - run ls program
    mov si, cmd_buf
    mov di, cmd_ls
    call str_eq
    cmp al, 1
    je .cmd_ls

    ; ================== FILESYSTEM OPERATIONS (USER'S NEW ADDITIONS) ==================
    ; These commands interface with kernel filesystem syscalls (SYS_FS_*)
    
    ; "mkdir <path>" - create directory via SYS_FS_MKDIR (0x0D)
    ; NEW ADDITION: Wraps sys_fs_mkdir kernel syscall
    mov si, cmd_buf
    mov di, cmd_mkdir_prefix ; check for "mkdir " prefix
    call str_startswith
    cmp al, 1
    je .cmd_mkdir           ; prefix matched

    ; "mkdir" alone - show usage
    mov si, cmd_buf
    mov di, cmd_mkdir
    call str_eq
    cmp al, 1
    je .cmd_mkdir_usage

    ; "rm <path>" - delete file/directory via SYS_FS_DELETE (0x0C)
    ; NEW ADDITION: Wraps sys_fs_delete kernel syscall
    mov si, cmd_buf
    mov di, cmd_rm_prefix   ; check for "rm " prefix
    call str_startswith
    cmp al, 1
    je .cmd_rm              ; prefix matched

    ; "rm" alone - show usage
    mov si, cmd_buf
    mov di, cmd_rm
    call str_eq
    cmp al, 1
    je .cmd_rm_usage

    ; "cd <path>" - change working directory via SYS_FS_CHDIR (0x0E)
    ; NEW ADDITION: Wraps sys_fs_chdir kernel syscall
    mov si, cmd_buf
    mov di, cmd_cd_prefix   ; check for "cd " prefix
    call str_startswith
    cmp al, 1
    je .cmd_cd              ; prefix matched

    ; "cd" alone - show usage
    mov si, cmd_buf
    mov di, cmd_cd
    call str_eq
    cmp al, 1
    je .cmd_cd_usage

    ; ================== SCRIPT EXECUTION ==================
    ; "arc <script.arc>" - Execute ARC script (one command per line, # for comments)
    ; ARC = Arc Runtime Compiler (simple line-by-line command executor)
    ; Uses kernel SYS_FS_READ to load file, then parses and executes each line
    
    mov si, cmd_buf
    mov di, cmd_arc_prefix  ; check for "arc " prefix
    call str_startswith
    cmp al, 1
    je .cmd_arc             ; prefix matched, run script

    ; "arc" alone - show usage
    mov si, cmd_buf
    mov di, cmd_arc
    call str_eq
    cmp al, 1
    je .cmd_arc_usage

    ; ================== FALLBACK: PROGRAM NAME ==================
    ; If no built-in matched, try running as a program name directly
    ; This allows "ls" to work without "run ls" (sys_run searches program table)
    mov si, cmd_buf         ; SI -> command entered by user
    call sys_run            ; kernel searches program table for matching entry
    cmp ah, 0               ; sys_run returns status in AH (0=success)
    je .shell_loop          ; success, return to prompt

    ; Unknown command or sys_run failed - display error
    mov si, msg_unknown     ; SI -> "unknown command" message
    call sys_puts           ; print error
    call sys_newline
    jmp .shell_loop         ; return to main loop

.cmd_help:
    mov si, msg_help        ; SI -> help message listing all commands
    call sys_puts           ; print available commands
    call sys_newline
    jmp .shell_loop         ; return to main loop

.cmd_clear:
    call sys_clear          ; kernel syscall (SYS_CLEAR 0x05) to clear screen
    jmp .shell_loop

.cmd_echo:
    ; "echo " is 5 bytes, print the remainder of buffer
    mov si, cmd_buf         ; SI -> command buffer
    add si, 5               ; SI += 5: skip "echo " prefix
    call sys_puts           ; print text argument
    call sys_newline
    jmp .shell_loop

.cmd_echo_empty:
    ; plain "echo" with no argument just prints newline
    call sys_newline
    jmp .shell_loop

.cmd_exit:
    mov si, msg_exit        ; SI -> goodbye message
    call sys_puts           ; print "returning to kernel"
    call sys_newline
    ret                     ; return to kernel caller (end shell)

.cmd_run:
    mov si, cmd_buf         ; SI -> command buffer
    add si, 4               ; SI += 4: skip "run " (4 bytes)
    cmp byte [si], 0        ; anything after "run "?
    je .cmd_run_usage       ; no argument, show usage

    call sys_run            ; kernel SYS_RUN (0x05): search program table for SI
    cmp ah, 0               ; AH = status code from kernel
    je .shell_loop          ; AH=0: success, return to prompt
    cmp ah, 1
    je .cmd_run_not_found   ; AH=1: program not found in table
    cmp ah, 2
    je .cmd_run_load_fail   ; AH=2: disk read error
    cmp ah, 3
    je .cmd_run_fs_fail     ; AH=3: program table not loaded

    mov si, msg_run_failed  ; unknown error code
    call sys_puts
    call sys_newline
    jmp .shell_loop

.cmd_run_usage:
    mov si, msg_run_usage   ; "usage: run <name>"
    call sys_puts
    call sys_newline
    jmp .shell_loop

.cmd_run_not_found:
    mov si, msg_run_not_found ; "program not found"
    call sys_puts
    call sys_newline
    jmp .shell_loop

.cmd_run_load_fail:
    mov si, msg_run_load_fail ; "program load failed"
    call sys_puts
    call sys_newline
    jmp .shell_loop

.cmd_run_fs_fail:
    mov si, msg_run_fs_fail  ; "filesystem unavailable"
    call sys_puts
    call sys_newline
    jmp .shell_loop

.cmd_ls:
    ; Run the built-in ls program entry from the program table.
    ; For compatibility, both "ls" and "ls <anything>" route here.
    mov si, cmd_ls
    call sys_run
    cmp ah, 0
    je .shell_loop
    mov si, msg_run_not_found
    call sys_puts
    call sys_newline
    jmp .shell_loop

.cmd_cat:
    ; Read and print file contents by path.
    ; Input command format: "cat <path>"
    mov si, cmd_buf
    add si, 4               ; skip "cat " prefix
    cmp byte [si], 0
    je .cmd_cat_usage       ; path missing

    mov bx, arc_buf         ; reuse script buffer as file read buffer
    call sys_fs_read        ; AH=status, CX=bytes read on success
    cmp ah, 0
    je .cmd_cat_print
    cmp ah, 1
    je .cmd_cat_not_found

    mov si, msg_cat_read_fail
    call sys_puts
    call sys_newline
    jmp .shell_loop

.cmd_cat_print:
    ; Ensure null termination for console_puts-style printing.
    mov di, arc_buf
    add di, cx
    mov byte [di], 0
    mov si, arc_buf
    call sys_puts
    call sys_newline
    jmp .shell_loop

.cmd_cat_usage:
    mov si, msg_cat_usage
    call sys_puts
    call sys_newline
    jmp .shell_loop

.cmd_cat_not_found:
    mov si, msg_cat_not_found
    call sys_puts
    call sys_newline
    jmp .shell_loop

.cmd_mkdir:
    ; Create directory via SYS_FS_MKDIR (syscall 0x0D)
    ; USER'S NEW ADDITION: Integrated filesystem command
    mov si, cmd_buf         ; SI -> command buffer
    add si, 6               ; SI += 6: skip "mkdir " (6 bytes)
    cmp byte [si], 0        ; path argument present?
    je .cmd_mkdir_usage     ; no, show usage
    call sys_fs_mkdir       ; kernel syscall: create directory at path in SI
    cmp ah, 0               ; AH = status (0=success)
    je .shell_loop          ; success, return to prompt
    mov si, msg_mkdir_fail  ; error occurred
    call sys_puts
    call sys_newline
    jmp .shell_loop

.cmd_mkdir_usage:
    mov si, msg_mkdir_usage ; "usage: mkdir <path>"
    call sys_puts
    call sys_newline
    jmp .shell_loop

.cmd_rm:
    ; Delete file or directory via SYS_FS_DELETE (syscall 0x0C)
    ; USER'S NEW ADDITION: Integrated filesystem command
    mov si, cmd_buf         ; SI -> command buffer
    add si, 3               ; SI += 3: skip "rm " (3 bytes)
    cmp byte [si], 0        ; path argument present?
    je .cmd_rm_usage        ; no, show usage
    call sys_fs_delete      ; kernel syscall: delete file/dir at path in SI
    cmp ah, 0               ; AH = status (0=success)
    je .shell_loop          ; success, return to prompt
    mov si, msg_rm_fail     ; error occurred
    call sys_puts
    call sys_newline
    jmp .shell_loop

.cmd_rm_usage:
    mov si, msg_rm_usage    ; "usage: rm <path>"
    call sys_puts
    call sys_newline
    jmp .shell_loop

.cmd_cd:
    ; Change working directory via SYS_FS_CHDIR (syscall 0x0E)
    ; USER'S NEW ADDITION: Integrated filesystem command
    mov si, cmd_buf         ; SI -> command buffer
    add si, 3               ; SI += 3: skip "cd " (3 bytes)
    cmp byte [si], 0        ; path argument present?
    je .cmd_cd_usage        ; no, show usage
    call sys_fs_chdir       ; kernel syscall: change directory to path in SI
    cmp ah, 0               ; AH = status (0=success)
    je .shell_loop          ; success, return to prompt
    mov si, msg_cd_fail     ; error occurred
    call sys_puts
    call sys_newline
    jmp .shell_loop

.cmd_cd_usage:
    mov si, msg_cd_usage    ; "usage: cd <path>"
    call sys_puts
    call sys_newline
    jmp .shell_loop

.cmd_arc:
    ; Execute ARC script file via run_arc_script function
    ; Script format: one command per line, # for comments (comment lines skipped)
    mov si, cmd_buf         ; SI -> command buffer
    add si, 4               ; SI += 4: skip "arc " (4 bytes)
    cmp byte [si], 0        ; script filename argument present?
    je .cmd_arc_usage       ; no, show usage
    call run_arc_script     ; load script file and execute command-by-command
    cmp ah, 0               ; AH = status (0=success)
    je .shell_loop          ; success, return to prompt
    cmp ah, 1
    je .cmd_arc_not_found   ; AH=1: script file not found
    mov si, msg_arc_fail    ; AH=2: command execution failed
    call sys_puts
    call sys_newline
    jmp .shell_loop

.cmd_arc_usage:
    mov si, msg_arc_usage   ; "usage: arc <file.arc>"
    call sys_puts
    call sys_newline
    jmp .shell_loop

.cmd_arc_not_found:
    mov si, msg_arc_not_found ; "script not found"
    call sys_puts
    call sys_newline
    jmp .shell_loop

; run_arc_script - Execute ARC script file (Arc Runtime Compiler)
; Script format: text file with one shell command per line
; Comment lines start with '#' and are skipped
; Each non-comment line is executed as if typed at the shell prompt
;
; Input: DS:SI = script file path (null-terminated string)
; Output: AH = 0 success, 1 file not found, 2 command execution failed
run_arc_script:
    mov bx, arc_buf         ; BX -> output buffer (1024 bytes)
    call sys_fs_read        ; kernel SYS_FS_READ (0x09): load file into arc_buf
    cmp ah, 0               ; AH = status
    jne .arc_read_fail      ; non-zero means error

    ; Null-terminate buffer to enable safe string walking
    mov di, arc_buf         ; DI = buffer start
    add di, cx              ; DI = point after last byte read (CX=bytes read)
    mov byte [di], 0        ; add null terminator for safety

    ; Parse and execute each non-empty, non-comment line as a command
    ; Lines starting with '#' are comment lines and are skipped
    mov si, arc_buf         ; SI = current position in script buffer

.arc_next:
    mov al, [si]            ; AL = current byte
    cmp al, 0               ; reached end of file (null terminator)?
    je .arc_ok              ; yes, execution complete, return success
    cmp al, 13              ; carriage return (CR)?
    je .arc_skip            ; skip blank/whitespace lines
    cmp al, 10              ; line feed (LF)?
    je .arc_skip            ; skip blank/whitespace lines

    ; Found start of a command line; find end of line (CR, LF, or null)
    mov di, si              ; DI = line start position

.arc_find_end:
    mov al, [si]            ; AL = current byte
    cmp al, 0               ; end of file?
    je .arc_have_line       ; yes, process this line
    cmp al, 13              ; carriage return (CR)?
    je .arc_have_line       ; yes, end of line
    cmp al, 10              ; line feed (LF)?
    je .arc_have_line       ; yes, end of line
    inc si                  ; advance SI to next byte
    jmp .arc_find_end       ; continue scanning for line end

.arc_have_line:
    ; Found end of line. Save delimiter and replace with null to isolate line.
    mov al, [si]            ; AL = CR/LF/null (the delimiter)
    mov [arc_delim], al     ; save delimiter for later restoration
    mov byte [si], 0        ; null-terminate the line

    ; Skip lines starting with '#' (comment lines)
    cmp byte [di], '#'      ; does line start with '#'?
    je .arc_restore         ; yes, skip this line

    ; Execute this line as a shell command (dispatch to sys_run)
    push si                 ; save position in script buffer
    mov si, di              ; SI = line content (for command execution)
    call sys_run            ; kernel SYS_RUN (0x05): run command
    pop si                  ; restore file position
    cmp ah, 0               ; execution success?
    jne .arc_exec_fail      ; non-zero means error, abort script

.arc_restore:
    ; Restore the original delimiter to continue parsing next line
    mov al, [arc_delim]     ; AL = saved delimiter (CR/LF/null)
    mov [si], al            ; restore to script buffer
    cmp al, 0               ; was it null (EOF)?
    je .arc_ok              ; yes, end of script
    inc si                  ; skip delimiter, move to next line
    jmp .arc_next           ; continue processing next line

.arc_skip:
    ; Skip pure whitespace lines (CR, LF)
    inc si                  ; advance to next byte
    jmp .arc_next           ; continue parsing

.arc_ok:
    xor ah, ah              ; AH = 0 (success)
    ret                     ; return to caller

.arc_read_fail:
    cmp ah, 1               ; sys_fs_read: AH=1 means "file not found"
    je .arc_not_found       ; jump to not-found handler
    mov ah, 2               ; other errors = command execution failure
    ret

.arc_not_found:
    mov ah, 1               ; file not found
    ret                     ; return to caller

.arc_exec_fail:
    mov ah, 2               ; command execution failed
    ret                     ; return to caller

; ================== SYSCALL WRAPPER FUNCTIONS ==================
; Each wrapper sets AH to the syscall code and invokes INT 0x80
; The kernel dispatcher in kernel.asm receives the interrupt and executes requested service
; These wrappers abstract syscall details from the shell command handlers

; sys_putc - Print single character to console
; Input: AL = ASCII character code
; Output: none (kernel handles printing)
sys_putc:
    mov ah, SYS_PUTC        ; AH = 0x01: syscall code for character output
    int SYSCALL_INT         ; INT 0x80: call kernel, kernel prints character from AL
    ret

; sys_puts - Print null-terminated string to console
; Input: DS:SI = address of null-terminated string
; Output: none (kernel prints string and advances position)
sys_puts:
    mov ah, SYS_PUTS        ; AH = 0x02: syscall code for string output
    int SYSCALL_INT         ; INT 0x80: call kernel, kernel prints from DS:SI
    ret

; sys_newline - Print carriage return + line feed (move cursor to next line)
; Input: none
; Output: none (kernel prints CR+LF)
sys_newline:
    mov ah, SYS_NEWLINE     ; AH = 0x03: syscall code for newline
    int SYSCALL_INT         ; INT 0x80: kernel prints 0x0D (CR) + 0x0A (LF)
    ret

; sys_getc - Wait for and read single keystroke from keyboard
; Input: none (blocking call - waits for user keypress)
; Output: AL = ASCII character code of key pressed
sys_getc:
    mov ah, SYS_GETC        ; AH = 0x04: syscall code for character input
    int SYSCALL_INT         ; INT 0x80: kernel waits for key, returns in AL
    ret

; sys_clear - Clear entire screen and reset cursor to top-left
; Input: none
; Output: none (kernel clears video memory)
sys_clear:
    mov ah, SYS_CLEAR       ; AH = 0x05: syscall code for screen clear
    int SYSCALL_INT         ; INT 0x80: kernel clears video memory (INT VIDEO_CLEAR?)
    ret

; sys_run - Load and execute a program from the program table
; Input: DS:SI = program name (null-terminated string, max 8 chars)
; Output: AH = status code:
;   0 = success (program executed)
;   1 = program not found in table  
;   2 = disk read error during load
;   3 = program table not available
sys_run:
    mov ah, SYS_RUN         ; AH = 0x05: syscall code for program execution
    int SYSCALL_INT         ; INT 0x80: kernel searches table, loads, executes
    ret

; sys_fs_read - Read entire file from filesystem into memory
; Input: DS:SI = file path (null-terminated), ES:BX = output buffer address
; Output: AH = status (0=success, 1=not found, 2=read error)
;         CX = number of bytes read (on success)
; Note: Reads entire file - buffer must be large enough
sys_fs_read:
    mov ah, SYS_FS_READ     ; AH = 0x09: syscall code for filesystem read
    int SYSCALL_INT         ; INT 0x80: kernel reads file into ES:BX buffer
    ret

; sys_fs_delete - Delete file or directory from filesystem
; Input: DS:SI = file/directory path (null-terminated)
; Output: AH = status (0=success, 1=not found, 2=error)
; NEW ADDITION: User requested filesystem command support
sys_fs_delete:
    mov ah, SYS_FS_DELETE   ; AH = 0x0C: syscall code for delete operation
    int SYSCALL_INT         ; INT 0x80: kernel deletes file/directory
    ret

; sys_fs_mkdir - Create new directory in filesystem
; Input: DS:SI = directory path (null-terminated)
; Output: AH = status (0=success, 1=already exists, 2=error)
; NEW ADDITION: User requested filesystem command support
sys_fs_mkdir:
    mov ah, SYS_FS_MKDIR    ; AH = 0x0D: syscall code for mkdir operation
    int SYSCALL_INT         ; INT 0x80: kernel creates new directory
    ret

; sys_fs_chdir - Change current working directory
; Input: DS:SI = directory path (null-terminated)
; Output: AH = status (0=success, 1=not found, 2=error)
; NEW ADDITION: User requested filesystem command support
sys_fs_chdir:
    mov ah, SYS_FS_CHDIR    ; AH = 0x0E: syscall code for chdir operation
    int SYSCALL_INT         ; INT 0x80: kernel changes working directory
    ret

; ================== STRING COMPARISON UTILITIES ==================
; Used by command dispatcher to match user input against known commands

; str_eq - String equality comparison (exact match)
; Compares two null-terminated strings byte-by-byte
; Strings must match exactly at every position
;
; Input: DS:SI = string A (null-terminated)
;        DS:DI = string B (null-terminated)
; Output: AL = 1 if strings are identical, 0 otherwise
str_eq:
.eq_loop:
    mov al, [si]            ; AL = next byte from string A
    mov bl, [di]            ; BL = next byte from string B
    cmp al, bl              ; bytes differ?
    jne .no                 ; yes, strings don't match
    cmp al, 0               ; both at null terminator?
    je .yes                 ; yes, both strings ended - perfect match
    inc si                  ; advance both pointers
    inc di
    jmp .eq_loop            ; continue comparing next byte
.yes:
    mov al, 1               ; AL = 1: exact match
    ret
.no:
    mov al, 0               ; AL = 0: mismatch
    ret

; str_startswith - Prefix matching
; Checks if full string (SI) starts with prefix string (DI)
; If DI is empty string, always matches (prefix matches anything)
;
; Input: DS:SI = full string (null-terminated)
;        DS:DI = prefix to check for (null-terminated)
; Output: AL = 1 if SI starts with DI, 0 otherwise
str_startswith:
.sw_loop:
    mov al, [di]            ; AL = next byte of prefix
    cmp al, 0               ; reached end of prefix (null terminator)?
    je .yes                 ; yes, entire prefix matched
    mov bl, [si]            ; BL = next byte from full string
    cmp bl, al              ; bytes match?
    jne .no                 ; no, prefix mismatch
    inc si                  ; advance both pointers
    inc di
    jmp .sw_loop            ; continue comparing next byte
.yes:
    mov al, 1               ; AL = 1: prefix match
    ret
.no:
    mov al, 0               ; AL = 0: prefix mismatch
    ret

; ================== MESSAGE STRINGS ==================
; All user-visible messages and prompts

shell_banner:
    db "Circle Shell interactive mode v0.1.22", 0  ; displayed on startup

shell_prompt:
    db "csh> ", 0          ; command prompt shown before each input

msg_help:
    db "commands: help, clear, echo <text>, run <name>, mkdir <p>, rm <p>, cd <p>, arc <f>, exit", 0

msg_unknown:
    db "unknown command", 0  ; shown when user enters unrecognized command

msg_exit:
    db "returning to kernel", 0  ; goodbye message

msg_run_usage:
    db "usage: run <name>", 0

msg_run_not_found:
    db "program not found", 0

msg_run_load_fail:
    db "program load failed", 0  ; disk error reading program

msg_run_failed:
    db "program failed", 0

msg_run_fs_fail:
    db "filesystem unavailable", 0  ; program table not loaded

msg_cat_usage:
    db "usage: cat <path>", 0

msg_cat_not_found:
    db "file not found", 0

msg_cat_read_fail:
    db "file read failed", 0

msg_mkdir_usage:
    db "usage: mkdir <path>", 0  ; user's new filesystem command

msg_mkdir_fail:
    db "mkdir failed", 0     ; user's new filesystem command

msg_rm_usage:
    db "usage: rm <path>", 0  ; user's new filesystem command

msg_rm_fail:
    db "rm failed", 0        ; user's new filesystem command

msg_cd_usage:
    db "usage: cd <path>", 0  ; user's new filesystem command

msg_cd_fail:
    db "cd failed", 0        ; user's new filesystem command

msg_arc_usage:
    db "usage: arc <file.arc>", 0

msg_arc_not_found:
    db "script not found", 0  ; ARC script file not in filesystem

msg_arc_fail:
    db "script execution failed", 0  ; command in script failed

; ================== COMMAND STRING LITERALS ==================
; Strings used for command dispatch (string matching)

cmd_help:
    db "help", 0            ; exact match for help command

cmd_clear:
    db "clear", 0           ; exact match for clear command

cmd_echo:
    db "echo", 0            ; exact match for standalonesudo echo (no text)

cmd_echo_prefix:
    db "echo ", 0           ; prefix match for "echo <text>"

cmd_run:
    db "run", 0             ; exact match for standalone "run" (show usage)

cmd_run_prefix:
    db "run ", 0            ; prefix match for "run <name>"

cmd_cat_prefix:
    db "cat ", 0            ; prefix match for "cat <path>"

cmd_ls:
    db "ls", 0              ; exact match for ls command

cmd_ls_prefix:
    db "ls ", 0             ; prefix match for "ls <path>"

cmd_mkdir:
    db "mkdir", 0           ; exact match for standalone mkdir (show usage)

cmd_mkdir_prefix:
    db "mkdir ", 0          ; prefix match for "mkdir <path>" (user's addition)

cmd_rm:
    db "rm", 0              ; exact match for standalone rm (show usage)

cmd_rm_prefix:
    db "rm ", 0             ; prefix match for "rm <path>" (user's addition)

cmd_cd:
    db "cd", 0              ; exact match for standalone cd (show usage)

cmd_cd_prefix:
    db "cd ", 0             ; prefix match for "cd <path>" (user's addition)

cmd_arc:
    db "arc", 0             ; exact match for standalone arc (show usage)

cmd_arc_prefix:
    db "arc ", 0            ; prefix match for "arc <script>"

cmd_exit:
    db "exit", 0            ; exact match for exit command

; ================== WORKING BUFFERS ==================

cmd_buf:
    times 32 db 0           ; 32-byte buffer for command input (31 chars + null)

arc_buf:
    times ARC_BUF_SIZE db 0  ; 1024-byte buffer for ARC script file content

arc_delim:
    db 0                    ; temporary storage for line delimiter during parsing
