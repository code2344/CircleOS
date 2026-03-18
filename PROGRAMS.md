# CircleOS v0.1.1 - Program Management System

## Overview
CircleOS now includes a complete program management system with 5 user-accessible programs that demonstrate external program execution from the filesystem.

## Programs Available

### 1. **demo** - Demo Program
- Simple program that prints "demo program executed"
- Located at sector 7
- **Usage:** `run demo`

### 2. **ls** - List Programs  
- Lists all available programs from the filesystem table
- Reads the program table at 0x0600 (loaded by kernel at boot)
- Located at sector 8
- **Usage:** `run ls`

### 3. **info** - System Information
- Displays boot information: signature, version, drive number, sector count
- Reads boot info structure from 0x0500
- Located at sector 9
- **Usage:** `run info`

### 4. **stat** - Program Statistics
- Shows total program count and memory layout
- Located at sector 10
- **Usage:** `run stat`

### 5. **greet** - Greeting Message
- Displays a welcome message
- Located at sector 11
- **Usage:** `run greet`

## Version Changes in v0.1.1

### Version Numbers Updated
- Boot loader: v0 → v1
- Kernel: v0.1.0 → v0.1.1
- Shell (csh): No version → v0.1.1

### Debug Output Added
- Program table entry count prints after load
- Program name being searched prints when "run <name>" is executed
- Helps diagnose program lookup issues

## Disk Layout

```
Sector 1     : Bootloader
Sectors 2-4  : Kernel (3 sectors)
Sectors 5-6  : Shell - csh (2 sectors)
Sector 7     : demo program
Sector 8     : ls program
Sector 9     : info program
Sector 10    : stat program
Sector 11    : greet program
Sector 17    : Filesystem table (CFS1 format)
```

## Filesystem Table Format (CFS1)

The filesystem table is stored at sector 17 and contains:
- **Header (16 bytes)**
  - Bytes 0-3: Magic "CFS1"
  - Byte 4: Entry count (5 programs)
  - Bytes 5-15: Reserved

- **Program Entries (16 bytes each, max 8)**
  - Bytes 0-7: Program name (zero-padded)
  - Byte 8: Start sector
  - Byte 9: Sector count
  - Bytes 10-11: Load offset (0xA000)
  - Bytes 12-13: Entry offset (0x0000)
  - Bytes 14-15: Reserved

## Usage Examples

```
csh> help
commands: help, clear, echo <text>, run <name>, exit

csh> ls
[lists all available programs]

csh> run info
[displays system information]

csh> run stat
[shows program statistics]

csh> run greet
[displays greeting]

csh> exit
[returns to kernel prompt]
```

## Technical Details

### Syscall Interface
All user programs use INT 0x80 (SYSCALL_INT) to communicate with the kernel:
- SYS_PUTC (0x00): Output single character
- SYS_PUTS (0x02): Output string
- SYS_NEWLINE (0x03): Output newline
- SYS_GETC (0x04): Read character
- SYS_CLEAR (0x05): Clear screen
- SYS_RUN (0x06): Run another program

### Memory Layout
- 0x0500: Boot information (16 bytes)
- 0x0600: Program table (512 bytes max)
- 0x7C00: Bootloader
- 0x7E00: Kernel
- 0x9000: Shell (csh)
- 0xA000: User program execution area

### Build System
The build script automatically:
1. Calculates program binary sizes
2. Computes sector positions dynamically
3. Assembles filesystem table with correct sector numbers
4. Places all binaries in correct disk locations
5. Generates proper CFS1 format metadata

## Debugging Tips

If "program not found" error occurs:
1. Check that `run ls` works (it reads the program table)
2. Look for "[DEBUG] Program table loaded with X entries" message
3. Watch for "[DEBUG] Searching for program: <name>" output
4. Verify program names match exactly (case-sensitive)

---
**CircleOS v0.1.1** - by SuperCode Studios
