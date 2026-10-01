#!/bin/sh
# Puts the VM rootfs at IMAGE_PATH. The rootfs comes from, in order:
#   1. an image already at IMAGE_PATH (init container re-run on the same volume: keep the VM's disk)
#   2. IMAGE_DOWNLOAD_URL, if set
#   3. the image baked into this container at LOCAL_DEV_IMAGE_PATH (make build-init)
#
# With WRITABLE_DISK_PATH set, the rootfs is a read-only base that this script never changes,
# and the session gets its own writable disk of WRITABLE_DISK_SIZE at that path. The VM boots
# with the writable disk over the base (labs/vm_lab/files/overlay-init). A disk already at
# WRITABLE_DISK_PATH is kept, so a session on a persistent volume continues where it left off.
# Without WRITABLE_DISK_PATH, the rootfs is the VM's one read-write disk and is grown to IMAGE_SIZE.
#
# If the session sets SSH_AUTHORIZED_KEY or USER_DATA, a cloud-init NoCloud seed for per-session
# setup goes onto the writable disk, or into the rootfs when there isn't one (see make_seed).
# Any failure exits non-zero, so the pod never starts Firecracker on a missing or unprepared disk.
set -eu
umask 022

: "${IMAGE_PATH:=/srv/vm/kernels/image.ext4}"
: "${LOCAL_DEV_IMAGE_PATH:=/app/image.ext4}"
: "${IMAGE_DOWNLOAD_URL:=}"
: "${IMAGE_SIZE:=1G}"
: "${WRITABLE_DISK_PATH:=}"
: "${WRITABLE_DISK_SIZE:=1G}"
# Per-session setup
: "${SSH_AUTHORIZED_KEY:=}"   # public key(s) for root, one per line
: "${USER_DATA:=}"            # a complete #cloud-config; replaces the generated one
: "${SESSION_ID:=}"
: "${VM_HOSTNAME:=dozlab-vm}"

SEED_DIR=/var/lib/cloud/seed/nocloud

# Writes meta-data and user-data into directory $1. cloud-init's NoCloud datasource reads them
# from $SEED_DIR in the VM on first boot.
make_seed() {
    printf 'instance-id: dozlab-%s\nlocal-hostname: %s\n' "${SESSION_ID:-vm}" "$VM_HOSTNAME" > "$1/meta-data"
    if [ -n "$USER_DATA" ]; then
        printf '%s\n' "$USER_DATA" > "$1/user-data"
    else
        {
            echo '#cloud-config'
            echo 'disable_root: false'
            echo 'users: []   # no default "ubuntu" user: the keys go to root'
            echo 'manage_etc_hosts: localhost'
            echo 'ssh_authorized_keys:'
            # Skip blank lines (a key from a Secret ends with a newline). An `if`, not `&&`: a
            # false test as the loop's last command would fail the script under set -e.
            printf '%s\n' "$SSH_AUTHORIZED_KEY" | while IFS= read -r key; do
                if [ -n "$key" ]; then
                    printf "  - '%s'\n" "$(printf '%s' "$key" | sed "s/'/''/g")"
                fi
            done
        } > "$1/user-data"
    fi
}

# Puts the seed into $SEED_DIR inside the rootfs. debugfs edits the ext4 without mounting it, so
# this needs no privileges.
write_seed_to_rootfs() {
    seed=$(mktemp -d)
    make_seed "$seed"
    # mkdir of an existing directory, or rm of a missing file, only prints a warning
    for d in /var/lib/cloud /var/lib/cloud/seed "$SEED_DIR"; do
        debugfs -w -R "mkdir $d" "$IMAGE_PATH" >/dev/null 2>&1 || true
    done
    for f in meta-data user-data; do
        debugfs -w -R "rm $SEED_DIR/$f" "$IMAGE_PATH" >/dev/null 2>&1 || true
        debugfs -w -R "write $seed/$f $SEED_DIR/$f" "$IMAGE_PATH" >/dev/null 2>&1
        # debugfs exits 0 even when a command fails, so check the file is there
        debugfs -R "stat $SEED_DIR/$f" "$IMAGE_PATH" 2>/dev/null | grep -q '^Inode:' ||
            { echo "Error: could not write $SEED_DIR/$f into $IMAGE_PATH" >&2; exit 1; }
    done
    rm -rf "$seed"
}

# Makes the session's writable disk: a sparse ext4 with the two directories overlay-init uses
# (upper/ holds the VM's changes, work/ is the overlay's scratch space). The seed is put in
# upper/, so the VM sees it at $SEED_DIR. `mkfs.ext4 -d` fills the filesystem as it creates it:
# no mount, no privileges.
create_writable_disk() {
    stage=$(mktemp -d)
    mkdir -p "$stage/upper" "$stage/work"
    chmod 0755 "$stage" "$stage/upper"   # upper/ is the VM's / directory
    if [ -n "$SSH_AUTHORIZED_KEY" ] || [ -n "$USER_DATA" ]; then
        echo "Writing per-session cloud-init seed to the writable disk (instance dozlab-${SESSION_ID:-vm}, hostname $VM_HOSTNAME)"
        mkdir -p "$stage/upper$SEED_DIR"
        make_seed "$stage/upper$SEED_DIR"
    fi
    # Temp file and rename, as for the image: a partial disk must never be picked up as existing
    tmp_disk="$WRITABLE_DISK_PATH.partial"
    rm -f "$tmp_disk"
    mkfs.ext4 -q -F -E lazy_itable_init=1,lazy_journal_init=1 -d "$stage" "$tmp_disk" "$WRITABLE_DISK_SIZE"
    mv "$tmp_disk" "$WRITABLE_DISK_PATH"
    rm -rf "$stage"
}

IMAGE_FOLDER=$(dirname "$IMAGE_PATH")

echo "IMAGE_FOLDER=$IMAGE_FOLDER"
echo "IMAGE_PATH=$IMAGE_PATH"
if [ -n "$WRITABLE_DISK_PATH" ]; then
    echo "WRITABLE_DISK_PATH=$WRITABLE_DISK_PATH"
    echo "WRITABLE_DISK_SIZE=$WRITABLE_DISK_SIZE"
else
    echo "IMAGE_SIZE=$IMAGE_SIZE"
fi

echo "Ensuring image folder $IMAGE_FOLDER"
mkdir -p "$IMAGE_FOLDER"

# Write to a temp file and rename, so an interrupted copy never leaves a partial image that
# step 1 would pick up next time.
TMP_IMAGE="$IMAGE_PATH.partial"
rm -f "$TMP_IMAGE"

if [ -f "$IMAGE_PATH" ]; then
    echo "Using existing image at $IMAGE_PATH"
elif [ -n "$IMAGE_DOWNLOAD_URL" ]; then
    echo "Downloading rootfs from $IMAGE_DOWNLOAD_URL"
    wget -O "$TMP_IMAGE" "$IMAGE_DOWNLOAD_URL"
    mv "$TMP_IMAGE" "$IMAGE_PATH"
elif [ -f "$LOCAL_DEV_IMAGE_PATH" ]; then
    echo "Using baked-in image $LOCAL_DEV_IMAGE_PATH"
    # A different filesystem (image layer -> volume), so this is a full copy
    mv "$LOCAL_DEV_IMAGE_PATH" "$TMP_IMAGE"
    mv "$TMP_IMAGE" "$IMAGE_PATH"
else
    echo "Error: no rootfs at $IMAGE_PATH, no IMAGE_DOWNLOAD_URL, and no baked-in image at $LOCAL_DEV_IMAGE_PATH" >&2
    exit 1
fi

if [ -n "$WRITABLE_DISK_PATH" ]; then
    # The base stays as built: no check, no resize, no seed. All of that is on the writable disk.
    mkdir -p "$(dirname "$WRITABLE_DISK_PATH")"
    if [ -f "$WRITABLE_DISK_PATH" ]; then
        echo "Using existing writable disk at $WRITABLE_DISK_PATH"
    else
        echo "Creating $WRITABLE_DISK_SIZE writable disk at $WRITABLE_DISK_PATH"
        create_writable_disk
    fi
    exit 0
fi

echo "Checking filesystem"
e2fsck -fy "$IMAGE_PATH" || [ $? -le 1 ]   # 1 = errors corrected; anything higher is fatal

echo "Resizing image to $IMAGE_SIZE"
resize2fs "$IMAGE_PATH" "$IMAGE_SIZE"

if [ -n "$SSH_AUTHORIZED_KEY" ] || [ -n "$USER_DATA" ]; then
    echo "Writing per-session cloud-init seed to $SEED_DIR (instance dozlab-${SESSION_ID:-vm}, hostname $VM_HOSTNAME)"
    write_seed_to_rootfs
fi
