#!/bin/bash
# build script

FS_TABLE_SECTOR=21
DEBUG=1

echo "Building CircleOS..."

echo "clearing old version"
rm -rf build
mkdir build

echo "assembling CircleOS..."

# Step 1: Assemble shell to get size
nasm csh.asm -o build/csh.bin
if [ $? -ne 0 ]; then
    echo "Error assembling csh.asm"
    exit 1
fi
echo "csh.asm assembled successfully"

SHELL_SIZE=$(stat -f%z "build/csh.bin")
SHELL_SECTORS=$(( (SHELL_SIZE + 511) / 512 ))
echo "Shell size: $SHELL_SIZE bytes, which is $SHELL_SECTORS sectors"

# Step 2: Assemble kernel (without fancy defines, just basic)
nasm kernel.asm -o build/kernel.bin 2>/dev/null || {
    # If it fails without defines, use defaults
    nasm -DDEBUG=$DEBUG -DFS_TABLE_SECTOR=$FS_TABLE_SECTOR -DSHELL_SECTORS=$SHELL_SECTORS kernel.asm -o build/kernel.bin
}

KERNEL_SIZE=$(stat -f%z "build/kernel.bin")
KERNEL_SECTORS=$(( (KERNEL_SIZE + 511) / 512 ))
echo "Kernel size: $KERNEL_SIZE bytes, which is $KERNEL_SECTORS sectors"

# Step 3: Calculate program start sector
# Boot(1) + Kernel(KERNEL_SECTORS) + Shell(SHELL_SECTORS) = first $((1 + KERNEL_SECTORS + SHELL_SECTORS))
# Next sector available = $((1 + KERNEL_SECTORS + SHELL_SECTORS + 1))
PROGRAM_START_SECTOR=$((1 + KERNEL_SECTORS + SHELL_SECTORS + 1))
echo "Programs start at sector $PROGRAM_START_SECTOR"

nasm ls.asm -o build/ls.bin
if [ $? -ne 0 ]; then
    echo "Error assembling ls.asm"
    exit 1
fi
LS_SIZE=$(stat -f%z "build/ls.bin")
LS_SECTORS=$(( (LS_SIZE + 511) / 512 ))
LS_SECTOR=$PROGRAM_START_SECTOR
echo "ls.asm assembled (size: $LS_SIZE bytes = $LS_SECTORS sectors, sector $LS_SECTOR)"

nasm info.asm -o build/info.bin
if [ $? -ne 0 ]; then
    echo "Error assembling info.asm"
    exit 1
fi
INFO_SIZE=$(stat -f%z "build/info.bin")
INFO_SECTORS=$(( (INFO_SIZE + 511) / 512 ))
INFO_SECTOR=$((LS_SECTOR + LS_SECTORS))
echo "info.asm assembled (size: $INFO_SIZE bytes = $INFO_SECTORS sectors, sector $INFO_SECTOR)"

nasm stat.asm -o build/stat.bin
if [ $? -ne 0 ]; then
    echo "Error assembling stat.asm"
    exit 1
fi
STAT_SIZE=$(stat -f%z "build/stat.bin")
STAT_SECTORS=$(( (STAT_SIZE + 511) / 512 ))
STAT_SECTOR=$((INFO_SECTOR + INFO_SECTORS))
echo "stat.asm assembled (size: $STAT_SIZE bytes = $STAT_SECTORS sectors, sector $STAT_SECTOR)"

nasm greet.asm -o build/greet.bin
if [ $? -ne 0 ]; then
    echo "Error assembling greet.asm"
    exit 1
fi
GREET_SIZE=$(stat -f%z "build/greet.bin")
GREET_SECTORS=$(( (GREET_SIZE + 511) / 512 ))
GREET_SECTOR=$((STAT_SECTOR + STAT_SECTORS))
echo "greet.asm assembled (size: $GREET_SIZE bytes = $GREET_SECTORS sectors, sector $GREET_SECTOR)"

nasm cat.asm -o build/cat.bin
if [ $? -ne 0 ]; then
    echo "Error assembling cat.asm"
    exit 1
fi
CAT_SIZE=$(stat -f%z "build/cat.bin")
CAT_SECTORS=$(( (CAT_SIZE + 511) / 512 ))
CAT_SECTOR=$((GREET_SECTOR + GREET_SECTORS))
echo "cat.asm assembled (size: $CAT_SIZE bytes = $CAT_SECTORS sectors, sector $CAT_SECTOR)"

WRITE_SECTOR=$((CAT_SECTOR + CAT_SECTORS))

if [ ! -f badapple.asm ]; then
    echo "Error: badapple.asm not found"
    exit 1
fi

nasm badapple.asm -o build/badapple.bin
if [ $? -ne 0 ]; then
    echo "Error assembling badapple.asm"
    exit 1
fi
BADAPPLE_SIZE=$(stat -f%z "build/badapple.bin")
BADAPPLE_SECTORS=$(( (BADAPPLE_SIZE + 511) / 512 ))
echo "badapple.asm assembled (size: $BADAPPLE_SIZE bytes = $BADAPPLE_SECTORS sectors)"

DATE_SECTOR=$((FS_TABLE_SECTOR + 1))

nasm date.asm -o build/date.bin
if [ $? -ne 0 ]; then
    echo "Error assembling date.asm"
    exit 1
fi
DATE_SIZE=$(stat -f%z "build/date.bin")
DATE_SECTORS=$(( (DATE_SIZE + 511) / 512 ))
echo "date.asm assembled (size: $DATE_SIZE bytes = $DATE_SECTORS sectors, sector $DATE_SECTOR)"

COUNT_SECTOR=$((DATE_SECTOR + DATE_SECTORS))

nasm count.asm -o build/count.bin
if [ $? -ne 0 ]; then
    echo "Error assembling count.asm"
    exit 1
fi
COUNT_SIZE=$(stat -f%z "build/count.bin")
COUNT_SECTORS=$(( (COUNT_SIZE + 511) / 512 ))
echo "count.asm assembled (size: $COUNT_SIZE bytes = $COUNT_SECTORS sectors, sector $COUNT_SECTOR)"

python3 tools/gen_stillalive_assets.py
if [ $? -ne 0 ]; then
    echo "Error generating stillalive_data.inc"
    exit 1
fi

STILLALIVE_SECTOR=$((COUNT_SECTOR + COUNT_SECTORS))

nasm stillalive.asm -o build/stillalive.bin
if [ $? -ne 0 ]; then
    echo "Error assembling stillalive.asm"
    exit 1
fi
STILLALIVE_SIZE=$(stat -f%z "build/stillalive.bin")
STILLALIVE_SECTORS=$(( (STILLALIVE_SIZE + 511) / 512 ))
echo "stillalive.asm assembled (size: $STILLALIVE_SIZE bytes = $STILLALIVE_SECTORS sectors, sector $STILLALIVE_SECTOR)"

cp todo.txt build/todo.bin
TODO_SIZE=$(stat -f%z "build/todo.bin")
TODO_SECTORS=$(( (TODO_SIZE + 511) / 512 ))
TODO_SECTOR=$((STILLALIVE_SECTOR + STILLALIVE_SECTORS))
echo "todo.txt packaged (size: $TODO_SIZE bytes = $TODO_SECTORS sectors, sector $TODO_SECTOR)"

nasm -DLOG_SECTOR=$TODO_SECTOR -DLOG_SECTORS=$TODO_SECTORS write.asm -o build/write.bin
if [ $? -ne 0 ]; then
    echo "Error assembling write.asm"
    exit 1
fi
WRITE_SIZE=$(stat -f%z "build/write.bin")
WRITE_SECTORS=$(( (WRITE_SIZE + 511) / 512 ))
echo "write.asm assembled (size: $WRITE_SIZE bytes = $WRITE_SECTORS sectors, sector $WRITE_SECTOR)"

BADAPPLE_SECTOR=$((TODO_SECTOR + TODO_SECTORS))
echo "badapple.bin will be written at sector $BADAPPLE_SECTOR"

WRITE_END=$((WRITE_SECTOR + WRITE_SECTORS - 1))
if [ "$WRITE_END" -ge "$FS_TABLE_SECTOR" ]; then
    echo "Layout error: executable region overlaps filesystem table"
    exit 1
fi

if [ "$TODO_SECTOR" -gt 255 ]; then
    echo "Layout error: todo sector exceeds 1-byte filesystem table limit"
    exit 1
fi

DIR_SECTOR=$LS_SECTOR
DIR_SECTORS=$LS_SECTORS

nasm -DFS_TABLE_SECTOR=$FS_TABLE_SECTOR \
    -DLS_SECTOR=$LS_SECTOR -DLS_SECTORS=$LS_SECTORS \
    -DINFO_SECTOR=$INFO_SECTOR -DINFO_SECTORS=$INFO_SECTORS \
    -DSTAT_SECTOR=$STAT_SECTOR -DSTAT_SECTORS=$STAT_SECTORS \
    -DGREET_SECTOR=$GREET_SECTOR -DGREET_SECTORS=$GREET_SECTORS \
    -DCAT_SECTOR=$CAT_SECTOR -DCAT_SECTORS=$CAT_SECTORS \
    -DTODO_SECTOR=$TODO_SECTOR -DTODO_SECTORS=$TODO_SECTORS \
    -DDIR_SECTOR=$DIR_SECTOR -DDIR_SECTORS=$DIR_SECTORS \
    -DWRITE_SECTOR=$WRITE_SECTOR -DWRITE_SECTORS=$WRITE_SECTORS \
    -DDATE_SECTOR=$DATE_SECTOR -DDATE_SECTORS=$DATE_SECTORS \
    -DCOUNT_SECTOR=$COUNT_SECTOR -DCOUNT_SECTORS=$COUNT_SECTORS \
    -DSTILLALIVE_SECTOR=$STILLALIVE_SECTOR -DSTILLALIVE_SECTORS=$STILLALIVE_SECTORS \
    fs_table.asm -o build/fs_table.bin
if [ $? -ne 0 ]; then
    echo "Error assembling fs_table.asm"
    exit 1
fi
echo "fs_table.asm assembled successfully"

# Step 6: Reassemble kernel with correct defines
nasm -DDEBUG=$DEBUG \
    -DFS_TABLE_SECTOR=$FS_TABLE_SECTOR \
    -DSHELL_SECTORS=$SHELL_SECTORS \
    -DBADAPPLE_SECTOR=$BADAPPLE_SECTOR \
    -DBADAPPLE_SECTORS=$BADAPPLE_SECTORS \
    kernel.asm -o build/kernel.bin
if [ $? -ne 0 ]; then
    echo "Error assembling kernel.asm"
    exit 1
fi
echo "kernel.asm assembled successfully"

# Step 7: Assemble bootloader with sector info
nasm -DKERNEL_SECTORS=$KERNEL_SECTORS -DSHELL_SECTORS=$SHELL_SECTORS boot.asm -o build/boot.bin
if [ $? -ne 0 ]; then
    echo "Error assembling boot.asm"
    exit 1
fi
echo "boot.asm assembled successfully"

# Step 8: Create disk image and write all components
echo "creating disk image"
dd if=/dev/zero of=build/circleos.img bs=512 count=2880 2>/dev/null

echo "writing bootloader to disk image (sector 1)"
dd if=build/boot.bin of=build/circleos.img bs=512 count=1 conv=notrunc 2>/dev/null

echo "writing kernel to disk image (sectors 2-$((1 + KERNEL_SECTORS)))"
dd if=build/kernel.bin of=build/circleos.img bs=512 seek=1 count=$KERNEL_SECTORS conv=notrunc 2>/dev/null

echo "writing shell to disk image (sectors $((2 + KERNEL_SECTORS))-$((1 + KERNEL_SECTORS + SHELL_SECTORS)))"
dd if=build/csh.bin of=build/circleos.img bs=512 seek=$((1 + KERNEL_SECTORS)) count=$SHELL_SECTORS conv=notrunc 2>/dev/null

echo "writing filesystem table to disk image (sector $FS_TABLE_SECTOR)"
dd if=build/fs_table.bin of=build/circleos.img bs=512 seek=$((FS_TABLE_SECTOR - 1)) count=1 conv=notrunc 2>/dev/null

echo "writing programs to disk"
dd if=build/ls.bin of=build/circleos.img bs=512 seek=$((LS_SECTOR - 1)) count=$LS_SECTORS conv=notrunc 2>/dev/null
dd if=build/info.bin of=build/circleos.img bs=512 seek=$((INFO_SECTOR - 1)) count=$INFO_SECTORS conv=notrunc 2>/dev/null
dd if=build/stat.bin of=build/circleos.img bs=512 seek=$((STAT_SECTOR - 1)) count=$STAT_SECTORS conv=notrunc 2>/dev/null
dd if=build/greet.bin of=build/circleos.img bs=512 seek=$((GREET_SECTOR - 1)) count=$GREET_SECTORS conv=notrunc 2>/dev/null
dd if=build/cat.bin of=build/circleos.img bs=512 seek=$((CAT_SECTOR - 1)) count=$CAT_SECTORS conv=notrunc 2>/dev/null
dd if=build/todo.bin of=build/circleos.img bs=512 seek=$((TODO_SECTOR - 1)) count=$TODO_SECTORS conv=notrunc 2>/dev/null
dd if=build/write.bin of=build/circleos.img bs=512 seek=$((WRITE_SECTOR - 1)) count=$WRITE_SECTORS conv=notrunc 2>/dev/null
dd if=build/badapple.bin of=build/circleos.img bs=512 seek=$((BADAPPLE_SECTOR - 1)) count=$BADAPPLE_SECTORS conv=notrunc 2>/dev/null
dd if=build/date.bin of=build/circleos.img bs=512 seek=$((DATE_SECTOR - 1)) count=$DATE_SECTORS conv=notrunc 2>/dev/null
dd if=build/count.bin of=build/circleos.img bs=512 seek=$((COUNT_SECTOR - 1)) count=$COUNT_SECTORS conv=notrunc 2>/dev/null
dd if=build/stillalive.bin of=build/circleos.img bs=512 seek=$((STILLALIVE_SECTOR - 1)) count=$STILLALIVE_SECTORS conv=notrunc 2>/dev/null

echo "CircleOS built successfully! Disk image created at build/circleos.img"
echo ""
echo "Sector layout:"
echo "  1: bootloader"
echo "  2-$((1 + KERNEL_SECTORS)): kernel"
echo "  $((2 + KERNEL_SECTORS))-$((1 + KERNEL_SECTORS + SHELL_SECTORS)): shell (csh)"
echo "  $LS_SECTOR-$((LS_SECTOR + LS_SECTORS - 1)): ls program"
echo "  $INFO_SECTOR-$((INFO_SECTOR + INFO_SECTORS - 1)): info program"
echo "  $STAT_SECTOR-$((STAT_SECTOR + STAT_SECTORS - 1)): stat program"
echo "  $GREET_SECTOR-$((GREET_SECTOR + GREET_SECTORS - 1)): greet program"
echo "  $CAT_SECTOR-$((CAT_SECTOR + CAT_SECTORS - 1)): cat program"
echo "  $DATE_SECTOR-$((DATE_SECTOR + DATE_SECTORS - 1)): date program"
echo "  $COUNT_SECTOR-$((COUNT_SECTOR + COUNT_SECTORS - 1)): count program"
echo "  $STILLALIVE_SECTOR-$((STILLALIVE_SECTOR + STILLALIVE_SECTORS - 1)): alive (still alive) program"
echo "  $TODO_SECTOR-$((TODO_SECTOR + TODO_SECTORS - 1)): todo text file"
echo "  $WRITE_SECTOR-$((WRITE_SECTOR + WRITE_SECTORS - 1)): write program"
echo "  $BADAPPLE_SECTOR-$((BADAPPLE_SECTOR + BADAPPLE_SECTORS - 1)): badapple direct-load program"
echo "  $DIR_SECTOR-$((DIR_SECTOR + DIR_SECTORS - 1)): dir/lsv alias (ls binary)"
echo "  $FS_TABLE_SECTOR: filesystem table"
echo "  $TODO_SECTOR+: reserved writable data area"