# TEAC USB floppy helper — status / list / copy / watch / eject
#
# Identifies the drive by /dev/floppy or usb-TEACV0.0-* (not /dev/sda).
# Copies photos into ~/Photos/floppy/<LABEL>/ so Mavica names don't collide.

function floppy --description 'TEAC USB floppy helper'
    set -l cmd ''
    if test (count $argv) -gt 0
        set cmd $argv[1]
        set -e argv[1]
    end

    switch "$cmd"
        case '' status st
            _floppy_status
        case ls list
            _floppy_ls
        case copy cp rip
            _floppy_copy
        case watch w
            _floppy_watch
        case eject umount unmount
            _floppy_eject
        case help h -h --help
            _floppy_help
        case '*'
            echo "unknown command: $cmd (try: floppy help)" >&2
            return 1
    end
end

function _floppy_help
    echo "floppy — TEAC USB floppy"
    echo ""
    echo "  floppy status|st     drive + disk label + mount"
    echo "  floppy ls            list files on the disk"
    echo "  floppy copy|cp|rip   copy photos to ~/Photos/floppy/<LABEL>/"
    echo "  floppy watch|w       copy, wait for the next disk, repeat"
    echo "  floppy eject         unmount so you can swap disks"
    echo ""
    echo "Mavica disks reuse MVC-001F.JPG etc. Each volume goes in its own"
    echo "subdir named after the FAT label (MY_PHOTO, 2020, ...)."
end

function _floppy_mnt
    echo /tmp/floppy
end

function _floppy_dest_root
    echo $HOME/Photos/floppy
end

function _floppy_dev
    if test -b /dev/floppy
        echo /dev/floppy
        return 0
    end
    for p in /dev/disk/by-id/usb-TEACV0.0*
        if test -b $p
            echo $p
            return 0
        end
    end
    return 1
end

function _floppy_sys_name --argument-names dev
    set -l real (readlink -f $dev)
    string replace -r '^/dev/' '' -- $real
end

function _floppy_sectors --argument-names dev
    set -l name (_floppy_sys_name $dev)
    if test -r /sys/block/$name/size
        cat /sys/block/$name/size
        return 0
    end
    return 1
end

function _floppy_has_media --argument-names dev
    set -l sz (_floppy_sectors $dev)
    or return 1
    test "$sz" -gt 0
end

function _floppy_label --argument-names dev
    set -l label (lsblk -ndo LABEL $dev 2>/dev/null | string trim)
    if test -z "$label"
        set label (blkid -s LABEL -o value $dev 2>/dev/null | string trim)
    end
    if test -z "$label"
        echo unlabeled
        return
    end
    string replace -a -r '[^A-Za-z0-9._-]+' '_' -- $label
end

function _floppy_need_dev
    set -l dev (_floppy_dev)
    if test -z "$dev"
        echo "no TEAC floppy drive (plug it in)" >&2
        return 1
    end
    echo $dev
end

function _floppy_need_media
    set -l dev (_floppy_need_dev)
    or return 1
    if not _floppy_has_media $dev
        echo "drive is empty — insert a disk" >&2
        return 1
    end
    echo $dev
end

function _floppy_mounted_on --argument-names mnt
    findmnt -n -o SOURCE --target $mnt 2>/dev/null
end

function _floppy_umount
    set -l mnt (_floppy_mnt)
    if mountpoint -q $mnt 2>/dev/null
        sudo -n umount $mnt
        or return 1
    end
    return 0
end

function _floppy_mount
    set -l dev (_floppy_need_media)
    or return 1
    set -l mnt (_floppy_mnt)
    set -l src (_floppy_mounted_on $mnt)
    set -l real (readlink -f $dev)

    if test -n "$src"
        if test (readlink -f $src) = $real
            return 0
        end
        _floppy_umount
        or return 1
    end

    mkdir -p $mnt
    sudo -n mount -o ro,uid=(id -u),gid=(id -g),umask=022 $dev $mnt
end

function _floppy_photos --argument-names mnt
    set -l out
    for f in $mnt/*.JPG $mnt/*.jpg $mnt/*.JPEG $mnt/*.jpeg $mnt/*.PNG $mnt/*.png $mnt/*.TIF $mnt/*.tif
        if test -f $f
            set -a out $f
        end
    end
    printf '%s\n' $out
end

function _floppy_status
    set -l dev (_floppy_dev)
    if test -z "$dev"
        echo "drive: not connected"
        return 0
    end
    set -l real (readlink -f $dev)
    echo "drive: $real  ($dev)"
    if not _floppy_has_media $dev
        echo "disk:  empty"
        return 0
    end
    set -l label (_floppy_label $dev)
    set -l size (lsblk -ndo SIZE $dev 2>/dev/null)
    echo "disk:  $label  ($size FAT)"
    set -l mnt (_floppy_mnt)
    set -l src (_floppy_mounted_on $mnt)
    if test -n "$src"
        echo "mount: $mnt"
    else
        echo "mount: (not mounted)"
    end
end

function _floppy_ls
    _floppy_mount
    or return 1
    set -l mnt (_floppy_mnt)
    ls -la $mnt
end

function _floppy_copy
    _floppy_mount
    or return 1

    set -l dev (_floppy_dev)
    set -l mnt (_floppy_mnt)
    set -l label (_floppy_label $dev)
    set -l dest (_floppy_dest_root)/$label
    mkdir -p $dest

    set -l photos (_floppy_photos $mnt)
    if test (count $photos) -eq 0
        echo "no photos on $label" >&2
        ls -la $mnt
        _floppy_umount
        return 1
    end

    set -l copied 0
    set -l skipped 0
    echo "disk $label → $dest"
    for f in $photos
        set -l base (basename $f)
        set -l out $dest/$base
        if test -f $out
            set -l a (md5sum $f | string split ' ')[1]
            set -l b (md5sum $out | string split ' ')[1]
            if test $a = $b
                echo "  skip $base (already copied)"
                set skipped (math $skipped + 1)
                continue
            end
            echo "  $base exists with different contents, not overwriting" >&2
            _floppy_umount
            return 1
        end
        echo "  $base"
        command cp -p $f $out
        or begin
            _floppy_umount
            return 1
        end
        set -l a (md5sum $f | string split ' ')[1]
        set -l b (md5sum $out | string split ' ')[1]
        if test $a != $b
            echo "  checksum mismatch on $base" >&2
            _floppy_umount
            return 1
        end
        set copied (math $copied + 1)
    end

    _floppy_umount
    or return 1
    echo "copied $copied, skipped $skipped. safe to swap."
    if command -q notify-send
        notify-send -a floppy "Floppy $label" "copied $copied photos → $dest"
    end
end

function _floppy_eject
    _floppy_umount
    or return 1
    echo "unmounted — swap or remove the disk"
end

function _floppy_wait --argument-names want msg
    echo $msg
    while true
        set -l dev (_floppy_dev)
        if test -z "$dev"
            if test $want = out
                return 0
            end
            sleep 0.5
            continue
        end
        if test $want = in
            _floppy_has_media $dev; and return 0
        else
            _floppy_has_media $dev; or return 0
        end
        sleep 0.5
    end
end

function _floppy_watch
    echo "watch mode — Ctrl-C to stop"
    while true
        set -l dev (_floppy_dev)
        if test -z "$dev"
            _floppy_wait in "waiting for the TEAC drive..."
        else if not _floppy_has_media $dev
            _floppy_wait in "insert a disk..."
        end
        _floppy_copy
        or return 1
        _floppy_wait out "remove the disk..."
    end
end
