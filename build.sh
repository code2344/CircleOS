#!/bin/bash
# build script for CircleOS v0.1.22

FS_TABLE_SECTOR=20
DEBUG=1
DATA_START_SECTOR=64
INODE_META_START_SECTOR=200
# Dynamic image input selection:
#   IMAGE_BASE=foo ./build.sh
#   IMAGE_PAL_FILE=foo.pal IMAGE_IMG_FILE=foo.img ./build.sh
IMAGE_BASE="${IMAGE_BASE:-meme}"
IMAGE_PAL_FILE="${IMAGE_PAL_FILE:-${IMAGE_BASE}.pal}"
IMAGE_IMG_FILE="${IMAGE_IMG_FILE:-${IMAGE_BASE}.img}"
IMAGE_SRC_FILE="${IMAGE_SRC_FILE:-${IMAGE_BASE}.png}"
AUTO_CONVERT_IMAGE="${AUTO_CONVERT_IMAGE:-1}"

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

cp todo.txt build/todo.bin
TODO_SIZE=$(stat -f%z "build/todo.bin")
TODO_SECTORS=$(( (TODO_SIZE + 511) / 512 ))
TODO_SECTOR=$DATA_START_SECTOR
echo "todo.txt packaged (size: $TODO_SIZE bytes = $TODO_SECTORS sectors, sector $TODO_SECTOR)"

# Auto-generate palette/image assets when source image + converter are present.
if [ "$AUTO_CONVERT_IMAGE" = "1" ] && [ -f "make_image_assets.py" ] && [ -f "$IMAGE_SRC_FILE" ]; then
    if python3 -c "import PIL" >/dev/null 2>&1; then
        echo "auto-converting $IMAGE_SRC_FILE -> $IMAGE_PAL_FILE / $IMAGE_IMG_FILE"
        python3 make_image_assets.py "$IMAGE_SRC_FILE" "$IMAGE_PAL_FILE" "$IMAGE_IMG_FILE"
        if [ $? -ne 0 ]; then
            echo "Error: make_image_assets.py failed"
            exit 1
        fi
    else
        echo "warning: Pillow (PIL) not installed; skipping auto-convert"
        echo "         using existing $IMAGE_PAL_FILE / $IMAGE_IMG_FILE if present"
    fi
fi

if [ ! -f "$IMAGE_PAL_FILE" ]; then
    echo "Error: missing palette file '$IMAGE_PAL_FILE'"
    exit 1
fi

if [ ! -f "$IMAGE_IMG_FILE" ]; then
    echo "Error: missing image file '$IMAGE_IMG_FILE'"
    exit 1
fi

cp "$IMAGE_PAL_FILE" build/splash.pal
cp "$IMAGE_IMG_FILE" build/splash.img

SPLASH_PAL_SIZE=$(stat -f%z "build/splash.pal")
SPLASH_IMG_SIZE=$(stat -f%z "build/splash.img")

if [ "$SPLASH_PAL_SIZE" -ne 768 ]; then
    echo "Layout error: splash palette must be exactly 768 bytes"
    exit 1
fi

if [ "$SPLASH_IMG_SIZE" -ne 64000 ]; then
    echo "Layout error: splash image must be exactly 64000 bytes"
    exit 1
fi

SPLASH_PAL_SECTORS=$(( (SPLASH_PAL_SIZE + 511) / 512 ))
SPLASH_IMG_SECTORS=$(( (SPLASH_IMG_SIZE + 511) / 512 ))
SPLASH_PAL_SECTOR=$((TODO_SECTOR + TODO_SECTORS))
SPLASH_IMG_SECTOR=$((SPLASH_PAL_SECTOR + SPLASH_PAL_SECTORS))

echo "$IMAGE_PAL_FILE packaged (size: $SPLASH_PAL_SIZE bytes = $SPLASH_PAL_SECTORS sectors, sector $SPLASH_PAL_SECTOR)"
echo "$IMAGE_IMG_FILE packaged (size: $SPLASH_IMG_SIZE bytes = $SPLASH_IMG_SECTORS sectors, sector $SPLASH_IMG_SECTOR)"

nasm -DLOG_SECTOR=$TODO_SECTOR -DLOG_SECTORS=$TODO_SECTORS write.asm -o build/write.bin
if [ $? -ne 0 ]; then
    echo "Error assembling write.asm"
    exit 1
fi
WRITE_SIZE=$(stat -f%z "build/write.bin")
WRITE_SECTORS=$(( (WRITE_SIZE + 511) / 512 ))
WRITE_SECTOR=$((CAT_SECTOR + CAT_SECTORS))
echo "write.asm assembled (size: $WRITE_SIZE bytes = $WRITE_SECTORS sectors, sector $WRITE_SECTOR)"

nasm -DSPLASH_PAL_SECTOR=$SPLASH_PAL_SECTOR -DSPLASH_PAL_SECTORS=$SPLASH_PAL_SECTORS \
    -DSPLASH_IMG_SECTOR=$SPLASH_IMG_SECTOR -DSPLASH_IMG_SECTORS=$SPLASH_IMG_SECTORS \
    img.asm -o build/img.bin
if [ $? -ne 0 ]; then
    echo "Error assembling img.asm"
    exit 1
fi
IMG_SIZE=$(stat -f%z "build/img.bin")
if [ "$IMG_SIZE" -le 0 ]; then
    echo "Error: img.asm produced empty binary"
    exit 1
fi
IMG_SECTORS=$(( (IMG_SIZE + 511) / 512 ))
IMG_SECTOR=$((WRITE_SECTOR + WRITE_SECTORS))
echo "img.asm assembled (size: $IMG_SIZE bytes = $IMG_SECTORS sectors, sector $IMG_SECTOR)"

nasm spheretui.asm -o build/spheretui.bin
if [ $? -ne 0 ]; then
    echo "Error assembling spheretui.asm"
    exit 1
fi
SPHERE_SIZE=$(stat -f%z "build/spheretui.bin")
SPHERE_SECTORS=$(( (SPHERE_SIZE + 511) / 512 ))
SPHERE_SECTOR=$((IMG_SECTOR + IMG_SECTORS))
echo "spheretui.asm assembled (size: $SPHERE_SIZE bytes = $SPHERE_SECTORS sectors, sector $SPHERE_SECTOR)"

# Place filesystem table right after executable region.
FS_TABLE_SECTOR_RUNTIME=$((SPHERE_SECTOR + SPHERE_SECTORS))

WRITE_END=$((WRITE_SECTOR + WRITE_SECTORS - 1))
IMG_END=$((IMG_SECTOR + IMG_SECTORS - 1))
SPHERE_END=$((SPHERE_SECTOR + SPHERE_SECTORS - 1))
TODO_END=$((TODO_SECTOR + TODO_SECTORS - 1))
SPLASH_PAL_END=$((SPLASH_PAL_SECTOR + SPLASH_PAL_SECTORS - 1))
SPLASH_IMG_END=$((SPLASH_IMG_SECTOR + SPLASH_IMG_SECTORS - 1))

if [ "$SPHERE_END" -ge "$FS_TABLE_SECTOR_RUNTIME" ]; then
    echo "Layout error: executable region overlaps filesystem table"
    exit 1
fi

if [ "$FS_TABLE_SECTOR_RUNTIME" -ge "$DATA_START_SECTOR" ]; then
    echo "Layout error: filesystem table must be before reserved data area"
    exit 1
fi

if [ "$TODO_SECTOR" -lt "$DATA_START_SECTOR" ]; then
    echo "Layout error: todo file must live in reserved data area"
    exit 1
fi

if [ "$SPLASH_PAL_SECTOR" -lt "$DATA_START_SECTOR" ] || [ "$SPLASH_IMG_SECTOR" -lt "$DATA_START_SECTOR" ]; then
    echo "Layout error: image assets must live in reserved data area"
    exit 1
fi

if [ "$SPLASH_IMG_END" -ge "$INODE_META_START_SECTOR" ]; then
    echo "Layout error: reserved data overlaps inode filesystem metadata"
    exit 1
fi

DIR_SECTOR=$LS_SECTOR
DIR_SECTORS=$LS_SECTORS

nasm -DFS_TABLE_SECTOR=$FS_TABLE_SECTOR_RUNTIME \
    -DLS_SECTOR=$LS_SECTOR -DLS_SECTORS=$LS_SECTORS \
    -DINFO_SECTOR=$INFO_SECTOR -DINFO_SECTORS=$INFO_SECTORS \
    -DSTAT_SECTOR=$STAT_SECTOR -DSTAT_SECTORS=$STAT_SECTORS \
    -DGREET_SECTOR=$GREET_SECTOR -DGREET_SECTORS=$GREET_SECTORS \
    -DCAT_SECTOR=$CAT_SECTOR -DCAT_SECTORS=$CAT_SECTORS \
    -DTODO_SECTOR=$TODO_SECTOR -DTODO_SECTORS=$TODO_SECTORS \
    -DDIR_SECTOR=$DIR_SECTOR -DDIR_SECTORS=$DIR_SECTORS \
    -DWRITE_SECTOR=$WRITE_SECTOR -DWRITE_SECTORS=$WRITE_SECTORS \
    -DIMG_SECTOR=$IMG_SECTOR -DIMG_SECTORS=$IMG_SECTORS \
    -DSPHERE_SECTOR=$SPHERE_SECTOR -DSPHERE_SECTORS=$SPHERE_SECTORS \
    fs_table.asm -o build/fs_table.bin
if [ $? -ne 0 ]; then
    echo "Error assembling fs_table.asm"
    exit 1
fi
echo "fs_table.asm assembled successfully"

# Step 6: Reassemble kernel with correct defines
nasm -DDEBUG=$DEBUG -DFS_TABLE_SECTOR=$FS_TABLE_SECTOR_RUNTIME -DSHELL_SECTORS=$SHELL_SECTORS kernel.asm -o build/kernel.bin
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

echo "writing filesystem table to disk image (sector $FS_TABLE_SECTOR_RUNTIME)"
dd if=build/fs_table.bin of=build/circleos.img bs=512 seek=$((FS_TABLE_SECTOR_RUNTIME - 1)) count=1 conv=notrunc 2>/dev/null

echo "writing programs to disk"
dd if=build/ls.bin of=build/circleos.img bs=512 seek=$((LS_SECTOR - 1)) count=$LS_SECTORS conv=notrunc 2>/dev/null
dd if=build/info.bin of=build/circleos.img bs=512 seek=$((INFO_SECTOR - 1)) count=$INFO_SECTORS conv=notrunc 2>/dev/null
dd if=build/stat.bin of=build/circleos.img bs=512 seek=$((STAT_SECTOR - 1)) count=$STAT_SECTORS conv=notrunc 2>/dev/null
dd if=build/greet.bin of=build/circleos.img bs=512 seek=$((GREET_SECTOR - 1)) count=$GREET_SECTORS conv=notrunc 2>/dev/null
dd if=build/cat.bin of=build/circleos.img bs=512 seek=$((CAT_SECTOR - 1)) count=$CAT_SECTORS conv=notrunc 2>/dev/null
dd if=build/todo.bin of=build/circleos.img bs=512 seek=$((TODO_SECTOR - 1)) count=$TODO_SECTORS conv=notrunc 2>/dev/null
dd if=build/splash.pal of=build/circleos.img bs=512 seek=$((SPLASH_PAL_SECTOR - 1)) count=$SPLASH_PAL_SECTORS conv=notrunc 2>/dev/null
dd if=build/splash.img of=build/circleos.img bs=512 seek=$((SPLASH_IMG_SECTOR - 1)) count=$SPLASH_IMG_SECTORS conv=notrunc 2>/dev/null
dd if=build/write.bin of=build/circleos.img bs=512 seek=$((WRITE_SECTOR - 1)) count=$WRITE_SECTORS conv=notrunc 2>/dev/null
dd if=build/img.bin of=build/circleos.img bs=512 seek=$((IMG_SECTOR - 1)) count=$IMG_SECTORS conv=notrunc 2>/dev/null
dd if=build/spheretui.bin of=build/circleos.img bs=512 seek=$((SPHERE_SECTOR - 1)) count=$SPHERE_SECTORS conv=notrunc 2>/dev/null

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
echo "  $TODO_SECTOR-$((TODO_SECTOR + TODO_SECTORS - 1)): todo text file"
echo "  $SPLASH_PAL_SECTOR-$SPLASH_PAL_END: image palette data ($IMAGE_PAL_FILE)"
echo "  $SPLASH_IMG_SECTOR-$SPLASH_IMG_END: image pixel data ($IMAGE_IMG_FILE)"
echo "  $WRITE_SECTOR-$((WRITE_SECTOR + WRITE_SECTORS - 1)): write program"
echo "  $IMG_SECTOR-$((IMG_SECTOR + IMG_SECTORS - 1)): img program"
echo "  $SPHERE_SECTOR-$((SPHERE_SECTOR + SPHERE_SECTORS - 1)): sphere tui program"
echo "  $DIR_SECTOR-$((DIR_SECTOR + DIR_SECTORS - 1)): dir/lsv alias (ls binary)"
echo "  $FS_TABLE_SECTOR_RUNTIME: filesystem table"
echo "  $DATA_START_SECTOR+: reserved writable data area"