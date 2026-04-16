; csh.asm - CIRCLE SHELL - Interactive command interpreter and script executor
; Load address: 0xB000 (loaded by kernel after boot)
; Purpose: Main user interface for CircleOS, dispatching commands and managing filesystem
; Commands: help, clear, echo, run, mkdir, rm, cd, arc (script), exit
;
; ARCHITECTURE:
; - Main REPL loop: prompt user, read command, dispatch to handler
; - Command dispatch: string matching against built-in command names
; - Filesystem operations: mkdir, rm, cd via kernel syscalls (SYS_FS_*)
; - Script execution: ARC interpreter loads script file, executes line-by-line
; - All commands fall back to sys_run for builtin/program execution

[BITS 32]
%ifndef SHELL_LOAD_ADDR
SHELL_LOAD_ADDR equ 0xB000
%endif
[ORG SHELL_LOAD_ADDR]

SYSCALL_INT equ 0x80
SYS_PUTC equ 0x01
SYS_PUTS equ 0x02
SYS_NEWLINE equ 0x03
SYS_GETC equ 0x04
SYS_CLEAR equ 0x05
SYS_RUN equ 0x06
SYS_FS_READ equ 0x09
SYS_FS_WRITE equ 0x0A
SYS_FS_DELETE equ 0x0C
SYS_FS_MKDIR equ 0x0D
SYS_FS_CHDIR equ 0x0E
SYS_REBOOT equ 0x0F
CTRL_C equ 0x03
ARC_BUF_SIZE equ 1024

%ifndef DEBUG_SHELL
DEBUG_SHELL equ 1
%endif

%ifndef ENABLE_AUTH_LOGIN
ENABLE_AUTH_LOGIN equ 0
%endif

start:
    mov ax, 0x10
    mov ds, ax              ; DS = 0x10: direct memory access to entire address space

%if ENABLE_AUTH_LOGIN
    call auth_bootstrap_and_login
%endif

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

    cmp al, 10              ; line feed (some terminals/keyboards)
    je .command_ready

    cmp al, 8               ; backspace key?
    je .backspace           ; erase last character

    mov dl, al              ; preserve typed byte across syscall
    call sys_putc           ; echo character to console

    cmp cx, 31              ; already 31 characters in buffer?
    jge .read_loop          ; yes, ignore further input (buffer full)
    
    mov si, cx              ; SI = current position in buffer
    mov byte [bx + si], dl  ; write original typed byte to buffer[CX]
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

    ; Normalize command buffer to lowercase so command dispatch
    ; remains stable even if keyboard shift state is noisy.
    mov si, cmd_buf
.lower_loop:
    mov al, [si]
    cmp al, 0
    je .lower_done
    cmp al, 'A'
    jb .lower_next
    cmp al, 'Z'
    ja .lower_next
    add al, 32
    mov [si], al
.lower_next:
    inc si
    jmp .lower_loop
.lower_done:

    ; Remove control bytes from input and trim leading spaces.
    ; Some emulators inject non-printable keyboard bytes that should
    ; not participate in command matching.
    mov si, cmd_buf
    mov di, cmd_buf
    mov dx, 0               ; DX=0 while trimming leading spaces
.sanitize_loop:
    mov al, [si]
    cmp al, 0
    je .sanitize_done

    ; Some keyboard paths can set bit 7 while still rendering a glyph.
    ; Normalize to 7-bit ASCII for command parsing.
    and al, 0x7F

    ; Keep printable ASCII only.
    cmp al, 32
    jb .sanitize_skip
    cmp al, 126
    ja .sanitize_skip

    ; Trim leading spaces.
    cmp dx, 0
    jne .sanitize_store
    cmp al, ' '
    je .sanitize_skip

.sanitize_store:
    mov [di], al
    inc di
    mov dx, 1

.sanitize_skip:
    inc si
    jmp .sanitize_loop

.sanitize_done:
    mov byte [di], 0

    ; Truncate at first unexpected byte so key-release artifacts
    ; cannot poison command dispatch.
    mov si, cmd_buf
.truncate_invalid_loop:
    mov al, [si]
    cmp al, 0
    je .truncate_invalid_done

    cmp al, 'a'
    jb .check_digit
    cmp al, 'z'
    jbe .truncate_next

.check_digit:
    cmp al, '0'
    jb .check_space
    cmp al, '9'
    jbe .truncate_next

.check_space:
    cmp al, ' '
    je .truncate_next
    cmp al, '-'
    je .truncate_next
    cmp al, '_'
    je .truncate_next
    cmp al, '/'
    je .truncate_next
    cmp al, '.'
    je .truncate_next

    mov byte [si], 0
    jmp .truncate_invalid_done

.truncate_next:
    inc si
    jmp .truncate_invalid_loop

.truncate_invalid_done:
    ; Trim trailing spaces for exact-match commands like "help".
    mov si, cmd_buf
.find_cmd_end:
    mov al, [si]
    cmp al, 0
    je .trim_trailing_start
    inc si
    jmp .find_cmd_end

.trim_trailing_start:
    cmp si, cmd_buf
    je .trim_trailing_done
    dec si

.trim_trailing_loop:
    cmp si, cmd_buf
    jb .trim_trailing_done
    cmp byte [si], ' '
    jne .trim_trailing_done
    mov byte [si], 0
    dec si
    jmp .trim_trailing_loop

.trim_trailing_done:

%if DEBUG_SHELL
    call dbg_print_cmd
%endif

    cmp byte [cmd_buf], 0   ; did user just press Enter with no input?
    je .shell_loop          ; yes, show prompt again

    ; ================== BUILT-IN COMMAND DISPATCH ==================
    ; Each command is checked via string comparison (exact match or prefix)
    
    ; === DEBUG ONLY: test if dispatch works at all ===
    mov si, cmd_buf
    mov di, test_cmd
    call str_eq
    cmp al, 1
    je .cmd_test

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

    ; "reboot" - reboot machine
    mov si, cmd_buf
    mov di, cmd_reboot
    call str_eq
    cmp al, 1
    je .cmd_reboot

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
    mov [last_run_status], ah
%if DEBUG_SHELL
    mov al, [last_run_status]
    call dbg_print_run_status
%endif
    cmp byte [last_run_status], 0 ; sys_run returns status in AH (0=success)
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

.cmd_test:
    mov si, msg_test_ok
    call sys_puts
    call sys_newline
    jmp .shell_loop

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

.cmd_reboot:
    mov si, msg_reboot
    call sys_puts
    call sys_newline
    call sys_reboot
    jmp .shell_loop

.cmd_run:
    mov si, cmd_buf         ; SI -> command buffer
    add si, 4               ; SI += 4: skip "run " (4 bytes)
    cmp byte [si], 0        ; anything after "run "?
    je .cmd_run_usage       ; no argument, show usage

    call sys_run            ; kernel SYS_RUN (0x05): search program table for SI
    mov [last_run_status], ah
    cmp byte [last_run_status], 0  ; AH = status code from kernel
    je .shell_loop          ; AH=0: success, return to prompt
    cmp byte [last_run_status], 1
    je .cmd_run_not_found   ; AH=1: program not found in table
    cmp byte [last_run_status], 2
    je .cmd_run_load_fail   ; AH=2: disk read error
    cmp byte [last_run_status], 3
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
    mov [last_run_status], ah
    cmp byte [last_run_status], 0
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

    mov ax, 0x10              ; SYS_FS_READ expects output buffer in ES:BX
    mov es, ax              ; ensure ES points at segment 0 (where arc_buf lives)
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
    ; Print exactly CX bytes from buffer, skipping embedded NUL padding.
    ; This avoids empty output if file blocks contain zero-filled regions.
    mov si, arc_buf
    mov dx, cx
.cmd_cat_emit_loop:
    cmp dx, 0
    je .cmd_cat_emit_done
    mov al, [si]
    cmp al, 0
    je .cmd_cat_emit_next
    call sys_putc
.cmd_cat_emit_next:
    inc si
    dec dx
    jmp .cmd_cat_emit_loop
.cmd_cat_emit_done:
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

; ================== FIRST-BOOT ACCOUNT + LOGIN ==================
; Account file format (stored in InodeFS):
;   U=<username>\n
;   H=<8-hex hash>\n
; Passwords are never stored plaintext; only hash text is persisted.

auth_bootstrap_and_login:
    call auth_read_config
    cmp ah, 0
    je .have_config
    cmp ah, 1
    je .first_boot

    ; Storage unavailable or read error: allow shell usage without auth lockout.
    mov si, msg_auth_unavailable
    call sys_puts
    call sys_newline
    xor ah, ah
    ret

.first_boot:
    mov si, msg_first_boot
    call sys_puts
    call sys_newline
    call auth_create_account
    cmp ah, 0
    jne .skip_auth

    call auth_read_config
    cmp ah, 0
    jne .skip_auth

.have_config:
    call auth_parse_record
    cmp ah, 0
    jne .skip_auth

.login_loop:
    mov si, msg_login_intro
    call sys_puts
    call sys_newline
    call auth_login_once
    cmp ah, 0
    je .login_ok

    mov si, msg_login_failed
    call sys_puts
    call sys_newline
    jmp .login_loop

.login_ok:
    mov si, msg_login_ok
    call sys_puts
    call sys_newline
    xor ah, ah
    ret

.skip_auth:
    mov si, msg_auth_unavailable
    call sys_puts
    call sys_newline
    xor ah, ah
    ret

auth_read_config:
    mov si, auth_file_path
    mov bx, auth_buf
    call sys_fs_read
    ret

auth_create_account:
.ask_user:
    mov si, msg_setup_user
    call sys_puts
    mov bx, auth_username_in
    mov cx, 31
    mov dl, 1
    call auth_read_line
    cmp byte [auth_username_in], CTRL_C
    je .cancel
    cmp byte [auth_username_in], 0
    je .ask_user

.ask_pass:
    mov si, msg_setup_pass
    call sys_puts
    mov bx, auth_password_in
    mov cx, 31
    mov dl, 0
    call auth_read_line
    cmp byte [auth_password_in], CTRL_C
    je .cancel
    cmp byte [auth_password_in], 0
    je .ask_pass

    mov si, auth_username_in
    mov di, auth_password_in
    call auth_hash_username_password
    mov di, auth_hash_calc
    call auth_hash_to_hex

    mov di, auth_buf
    mov byte [di], 'U'
    inc di
    mov byte [di], '='
    inc di

    mov si, auth_username_in
.copy_user:
    mov al, [si]
    cmp al, 0
    je .user_done
    mov [di], al
    inc di
    inc si
    jmp .copy_user

.user_done:
    mov byte [di], 10
    inc di
    mov byte [di], 'H'
    inc di
    mov byte [di], '='
    inc di

    mov si, auth_hash_calc
    mov cx, 8
.copy_hash:
    mov al, [si]
    mov [di], al
    inc di
    inc si
    dec cx
    jnz .copy_hash

    mov byte [di], 10
    inc di
    mov byte [di], 0

    mov ax, di
    sub ax, auth_buf
    mov cx, ax
    mov si, auth_file_path
    mov bx, auth_buf
    call sys_fs_write
    cmp ah, 0
    jne .write_fail

    mov si, msg_setup_done
    call sys_puts
    call sys_newline
    xor ah, ah
    ret

.write_fail:
    mov si, msg_setup_write_fail
    call sys_puts
    call sys_newline
    mov ah, 1
    ret

.cancel:
    mov ah, 1
    ret

auth_parse_record:
    mov si, auth_buf
    cmp byte [si], 'U'
    jne .bad
    cmp byte [si + 1], '='
    jne .bad
    add si, 2

    mov di, auth_username_stored
    mov cx, 31
.parse_user:
    mov al, [si]
    cmp al, 0
    je .bad
    cmp al, 10
    je .user_done
    cmp al, 13
    je .user_done
    mov [di], al
    inc di
    inc si
    dec cx
    jnz .parse_user
    jmp .bad

.user_done:
    mov byte [di], 0

.skip_user_eol:
    mov al, [si]
    cmp al, 10
    je .after_user_line
    cmp al, 13
    je .next_user_eol
    cmp al, 0
    je .bad
    jmp .after_user_line

.next_user_eol:
    inc si
    jmp .skip_user_eol

.after_user_line:
    cmp byte [si], 10
    je .consume_user_lf
    cmp byte [si], 13
    je .consume_user_cr
    jmp .check_hash_tag

.consume_user_cr:
    inc si
    cmp byte [si], 10
    jne .check_hash_tag
.consume_user_lf:
    inc si

.check_hash_tag:
    cmp byte [si], 'H'
    jne .bad
    cmp byte [si + 1], '='
    jne .bad
    add si, 2

    mov di, auth_hash_stored
    mov cx, 8
.parse_hash:
    mov al, [si]
    cmp al, 0
    je .bad
    cmp al, 'A'
    jb .hash_store
    cmp al, 'F'
    ja .hash_store
    add al, 32
.hash_store:
    mov [di], al
    inc di
    inc si
    dec cx
    jnz .parse_hash

    mov byte [di], 0
    xor ah, ah
    ret

.bad:
    mov ah, 1
    ret

auth_login_once:
    mov si, msg_login_user
    call sys_puts
    mov bx, auth_username_in
    mov cx, 31
    mov dl, 1
    call auth_read_line
    cmp byte [auth_username_in], CTRL_C
    je .fail

    mov si, msg_login_pass
    call sys_puts
    mov bx, auth_password_in
    mov cx, 31
    mov dl, 0
    call auth_read_line
    cmp byte [auth_password_in], CTRL_C
    je .fail

    mov si, auth_username_in
    mov di, auth_username_stored
    call str_eq
    cmp al, 1
    jne .fail

    mov si, auth_username_in
    mov di, auth_password_in
    call auth_hash_username_password
    mov di, auth_hash_calc
    call auth_hash_to_hex

    mov si, auth_hash_calc
    mov di, auth_hash_stored
    call str_eq
    cmp al, 1
    jne .fail

    xor ah, ah
    ret

.fail:
    mov ah, 1
    ret

; auth_hash_username_password
; Input: DS:SI username, DS:DI password
; Output: EAX 32-bit FNV-1a based hash
auth_hash_username_password:
    push ebx
    mov eax, 0x811C9DC5

.hash_user:
    movzx ebx, byte [si]
    cmp bl, 0
    je .hash_sep
    xor eax, ebx
    imul eax, eax, 16777619
    inc si
    jmp .hash_user

.hash_sep:
    movzx ebx, byte [auth_hash_sep]
    xor eax, ebx
    imul eax, eax, 16777619

.hash_pass:
    movzx ebx, byte [di]
    cmp bl, 0
    je .hash_done
    xor eax, ebx
    imul eax, eax, 16777619
    inc di
    jmp .hash_pass

.hash_done:
    xor eax, 0x9E3779B9
    pop ebx
    ret

; auth_hash_to_hex
; Input: EAX hash, DS:DI output buffer (>=9 bytes)
; Output: 8 lowercase hex chars + null terminator
auth_hash_to_hex:
    push eax
    push ebx
    push ecx
    push edx

    mov ecx, 8
.hex_loop:
    mov edx, eax
    shr edx, 28
    and edx, 0x0F
    mov bl, [auth_hex_digits + edx]
    mov [di], bl
    inc di
    shl eax, 4
    dec ecx
    jnz .hex_loop

    mov byte [di], 0
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; auth_read_line
; Input: DS:BX buffer, CX max chars, DL echo mode (1=echo char, 0=echo '*')
; Output: null-terminated string in buffer, CTRL_C writes 0x03 at buffer[0]
auth_read_line:
    xor di, di

.read_char:
    call sys_getc
    cmp al, CTRL_C
    je .cancel

    cmp al, 13
    je .done
    cmp al, 10
    je .done

    cmp al, 8
    je .backspace

    cmp di, cx
    jae .read_char

    mov [bx + di], al
    inc di

    cmp dl, 1
    je .echo_real
    mov al, '*'
    call sys_putc
    jmp .read_char

.echo_real:
    mov al, [bx + di - 1]
    call sys_putc
    jmp .read_char

.backspace:
    cmp di, 0
    je .read_char
    dec di
    mov byte [bx + di], 0
    mov al, 8
    call sys_putc
    mov al, ' '
    call sys_putc
    mov al, 8
    call sys_putc
    jmp .read_char

.cancel:
    mov byte [bx], CTRL_C
    call sys_newline
    ret

.done:
    mov byte [bx + di], 0
    call sys_newline
    ret

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
    movzx esi, si           ; syscall path uses ESI, not SI
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
    movzx esi, si           ; pass pointer in full ESI
    int SYSCALL_INT         ; INT 0x80: kernel searches table, loads, executes
    ret

; sys_fs_read - Read entire file from filesystem into memory
; Input: DS:SI = file path (null-terminated), ES:BX = output buffer address
; Output: AH = status (0=success, 1=not found, 2=read error)
;         CX = number of bytes read (on success)
; Note: Reads entire file - buffer must be large enough
sys_fs_read:
    mov ah, SYS_FS_READ     ; AH = 0x09: syscall code for filesystem read
    movzx esi, si           ; pathname pointer
    movzx ebx, bx           ; output buffer offset
    int SYSCALL_INT         ; INT 0x80: kernel reads file into ES:BX buffer
    ret

; sys_fs_write - Write file to filesystem from memory buffer
; Input: DS:SI = file path (null-terminated), ES:BX = input buffer, CX = bytes
; Output: AH = status (0=success, 1=full/error, 2=I/O)
sys_fs_write:
    mov ah, SYS_FS_WRITE    ; AH = 0x0A: syscall code for filesystem write
    movzx esi, si           ; pathname pointer
    movzx ebx, bx           ; input buffer offset
    int SYSCALL_INT         ; INT 0x80: kernel writes file from ES:BX buffer
    ret

; sys_fs_delete - Delete file or directory from filesystem
; Input: DS:SI = file/directory path (null-terminated)
; Output: AH = status (0=success, 1=not found, 2=error)
; NEW ADDITION: User requested filesystem command support
sys_fs_delete:
    mov ah, SYS_FS_DELETE   ; AH = 0x0C: syscall code for delete operation
    movzx esi, si           ; pathname pointer
    int SYSCALL_INT         ; INT 0x80: kernel deletes file/directory
    ret

; sys_fs_mkdir - Create new directory in filesystem
; Input: DS:SI = directory path (null-terminated)
; Output: AH = status (0=success, 1=already exists, 2=error)
; NEW ADDITION: User requested filesystem command support
sys_fs_mkdir:
    mov ah, SYS_FS_MKDIR    ; AH = 0x0D: syscall code for mkdir operation
    movzx esi, si           ; pathname pointer
    int SYSCALL_INT         ; INT 0x80: kernel creates new directory
    ret

; sys_fs_chdir - Change current working directory
; Input: DS:SI = directory path (null-terminated)
; Output: AH = status (0=success, 1=not found, 2=error)
; NEW ADDITION: User requested filesystem command support
sys_fs_chdir:
    mov ah, SYS_FS_CHDIR    ; AH = 0x0E: syscall code for chdir operation
    movzx esi, si           ; pathname pointer
    int SYSCALL_INT         ; INT 0x80: kernel changes working directory
    ret

; sys_reboot - Reboot machine via kernel reboot syscall
; Input: none
; Output: none (system restarts)
sys_reboot:
    mov ah, SYS_REBOOT      ; AH = 0x0F: syscall code for reboot
    int SYSCALL_INT         ; INT 0x80: kernel reboots the machine
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

%if DEBUG_SHELL
dbg_print_cmd:
    pushad
    mov si, msg_dbg_cmd_prefix
    call sys_puts
    mov si, cmd_buf
    call sys_puts
    mov si, msg_dbg_cmd_suffix
    call sys_puts
    call sys_newline
    popad
    ret

dbg_print_run_status:
    pushad
    mov bl, al
    mov si, msg_dbg_run_prefix
    call sys_puts
    mov al, bl
    call dbg_print_hex8
    call sys_newline
    popad
    ret

dbg_print_hex8:
    push eax
    mov ah, al
    shr al, 4
    call dbg_print_hex_nibble
    mov al, ah
    and al, 0x0F
    call dbg_print_hex_nibble
    pop eax
    ret

dbg_print_hex_nibble:
    and al, 0x0F
    cmp al, 9
    jbe .hex_digit
    add al, 7
.hex_digit:
    add al, '0'
    call sys_putc
    ret
%endif

; ================== MESSAGE STRINGS ==================
; All user-visible messages and prompts

shell_banner:
    db "Circle Shell interactive mode v0.1.24", 0  ; displayed on startup

shell_prompt:
    db "csh> ", 0          ; command prompt shown before each input

msg_help:
    db "commands: help, clear, echo <text>, run <name>, mkdir <p>, rm <p>, cd <p>, arc <f>, reboot, exit", 0

msg_test_ok:
    db "[TEST] dispatch and handler execution working!", 0

msg_unknown:
    db "unknown command", 0  ; shown when user enters unrecognized command

msg_exit:
    db "returning to kernel", 0  ; goodbye message

msg_reboot:
    db "rebooting...", 0

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

msg_first_boot:
    db "first boot setup: create your account", 0

msg_setup_user:
    db "new username: ", 0

msg_setup_pass:
    db "new password: ", 0

msg_setup_done:
    db "account created", 0

msg_setup_write_fail:
    db "failed to save account", 0

msg_auth_unavailable:
    db "auth unavailable (storage read/write failed)", 0

msg_login_intro:
    db "login required", 0

msg_login_user:
    db "username: ", 0

msg_login_pass:
    db "password: ", 0

msg_login_failed:
    db "login failed", 0

msg_login_ok:
    db "login successful", 0

%if DEBUG_SHELL
msg_dbg_cmd_prefix:
    db "[dbg] cmd='", 0

msg_dbg_cmd_suffix:
    db "'", 0

msg_dbg_run_prefix:
    db "[dbg] sys_run ah=0x", 0
%endif

; ================== COMMAND STRING LITERALS ==================
; Strings used for command dispatch (string matching)

cmd_help:
    db "help", 0            ; exact match for help command

test_cmd:
    db "test", 0            ; debug test command

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

cmd_reboot:
    db "reboot", 0          ; exact match for reboot command

; ================== WORKING BUFFERS ==================

auth_file_path:
    db "/authcfg", 0

auth_hex_digits:
    db "0123456789abcdef", 0

auth_hash_sep:
    db ':', 0

cmd_buf:
    times 32 db 0           ; 32-byte buffer for command input (31 chars + null)

arc_buf:
    times ARC_BUF_SIZE db 0  ; 1024-byte buffer for ARC script file content

arc_delim:
    db 0                    ; temporary storage for line delimiter during parsing

last_run_status:
    db 0                    ; cached SYS_RUN AH result for stable branching/debug

auth_buf:
    times 256 db 0

auth_username_stored:
    times 32 db 0

auth_hash_stored:
    times 9 db 0

auth_username_in:
    times 32 db 0

auth_password_in:
    times 32 db 0

auth_hash_calc:
    times 9 db 0
