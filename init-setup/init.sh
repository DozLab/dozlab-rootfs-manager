#!/bin/sh
# Puts the VM rootfs at IMAGE_PATH and grows it to IMAGE_SIZE. The rootfs comes from, in order:
#   1. an image already at IMAGE_PATH (init container re-run on the same volume: keep the VM's disk)
#   2. IMAGE_DOWNLOAD_URL, if set
#   3. the image baked into this container at LOCAL_DEV_IMAGE_PATH (make build-init)
# Then, if the session sets SSH_AUTHORIZED_KEY or USER_DATA, it writes a cloud-init NoCloud seed
# into the rootfs for per-session setup (see write_seed).
# Any failure exits non-zero, so the pod never starts Firecracker on a missing or unresized disk.
set -eu

: "${IMAGE_PATH:=/srv/vm/kernels/image.ext4}"
: "${LOCAL_DEV_IMAGE_PATH:=/app/image.ext4}"
: "${IMAGE_DOWNLOAD_URL:=}"
: "${IMAGE_SIZE:=1G}"
# Per-session setup
: "${SSH_AUTHORIZED_KEY:=}"   # public key(s) for root, one per line
: "${USER_DATA:=}"            # a complete #cloud-config; replaces the generated one
: "${SESSION_ID:=}"
: "${VM_HOSTNAME:=dozlab-vm}"

SEED_DIR=/var/lib/cloud/seed/nocloud

# Writes meta-data and user-data into $SEED_DIR inside the rootfs, where cloud-init's NoCloud
# datasource reads them on first boot. debugfs edits the ext4 without mounting it, so this
# needs no privileges.
write_seed() {
    seed=$(mktemp -d)
    printf 'instance-id: dozlab-%s\nlocal-hostname: %s\n' "${SESSION_ID:-vm}" "$VM_HOSTNAME" > "$seed/meta-data"
    if [ -n "$USER_DATA" ]; then
        printf '%s\n' "$USER_DATA" > "$seed/user-data"
    else
        {
            echo '#cloud-config'
            echo 'disable_root: false'
            echo 'users: []   # no default "ubuntu" user: the keys go to root'
            echo 'manage_etc_hosts: localhost'
            echo 'ssh_authorized_keys:'
            printf '%s\n' "$SSH_AUTHORIZED_KEY" | while IFS= read -r key; do
                [ -n "$key" ] && printf "  - '%s'\n" "$(printf '%s' "$key" | sed "s/'/''/g")"
            done
        } > "$seed/user-data"
    fi
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

IMAGE_FOLDER=$(dirname "$IMAGE_PATH")

echo "IMAGE_FOLDER=$IMAGE_FOLDER"
echo "IMAGE_PATH=$IMAGE_PATH"
echo "IMAGE_SIZE=$IMAGE_SIZE"

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

echo "Checking filesystem"
e2fsck -fy "$IMAGE_PATH" || [ $? -le 1 ]   # 1 = errors corrected; anything higher is fatal

echo "Resizing image to $IMAGE_SIZE"
resize2fs "$IMAGE_PATH" "$IMAGE_SIZE"

if [ -n "$SSH_AUTHORIZED_KEY" ] || [ -n "$USER_DATA" ]; then
    echo "Writing per-session cloud-init seed to $SEED_DIR (instance dozlab-${SESSION_ID:-vm}, hostname $VM_HOSTNAME)"
    write_seed
fi
