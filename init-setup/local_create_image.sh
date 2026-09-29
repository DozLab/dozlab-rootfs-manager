#!/bin/bash
# Turns a lab container image (e.g. labs/vm_lab) into the ext4 rootfs that init-setup bakes in.
# Needs root for the loop mount: `make -C init-setup build` runs it with sudo.

# Enable debugging
set -ex

# Set default values if not provided
: "${IMAGE_PATH:="./disk/image.ext4"}"
: "${IMAGE_SIZE:=2G}"   # build space only; the image is shrunk to its contents afterwards
: "${CONTAINER_IMAGE_NAME:=dozman99/dozlab-vm:test}"
# Optional public key file baked into /root/.ssh/authorized_keys. For local clusters only:
# don't bake a key into an image you push.
: "${AUTHORIZED_KEYS:=}"

# Determine the folder where the image is stored
IMAGE_FOLDER=$(dirname "$IMAGE_PATH")

# Output the variables
echo "IMAGE_FOLDER=$IMAGE_FOLDER"
echo "IMAGE_PATH=$IMAGE_PATH"
echo "IMAGE_SIZE=$IMAGE_SIZE"
echo "CONTAINER_IMAGE_NAME=$CONTAINER_IMAGE_NAME"

# Ensure the image folder exists
echo "Ensuring image folder $IMAGE_FOLDER"
mkdir -p "$IMAGE_FOLDER"

# Extract rootfs.tar from Docker image
extract() {
    echo "Extracting rootfs.tar from Docker image..."
    docker rm -f extract || true
    rm -f rootfs.tar || true
    docker create --name extract "$CONTAINER_IMAGE_NAME"
    docker export extract -o rootfs.tar
    docker rm -f extract
}

# docker export captures files Docker bind-mounts at runtime, so the rootfs ends up with an
# empty /etc/hostname, /etc/hosts and /etc/resolv.conf, and a /.dockerenv that makes systemd
# in the VM believe it is in a container (skipping units such as haveged).
fix_exported_rootfs() {
    local root="$1"
    rm -f "$root/.dockerenv"
    echo "${VM_HOSTNAME:-dozlab-vm}" > "$root/etc/hostname"
    printf '127.0.0.1 localhost\n127.0.1.1 %s\n::1 localhost ip6-localhost ip6-loopback\n' \
        "${VM_HOSTNAME:-dozlab-vm}" > "$root/etc/hosts"
    ln -sf ../run/systemd/resolve/stub-resolv.conf "$root/etc/resolv.conf"
}

bake_authorized_keys() {
    local root="$1"
    [ -n "$AUTHORIZED_KEYS" ] || return 0
    echo "Baking $AUTHORIZED_KEYS into /root/.ssh/authorized_keys"
    install -d -m 0700 "$root/root/.ssh"
    install -m 0600 "$AUTHORIZED_KEYS" "$root/root/.ssh/authorized_keys"
}

# Create disk image
create_image() {
    echo "Creating disk image..."
    rm -f "$IMAGE_PATH" || true
    truncate -s "$IMAGE_SIZE" "$IMAGE_PATH"   # sparse: only written blocks take space
    mkfs.ext4 -F "$IMAGE_PATH"

    TMP=$(mktemp -d)
    echo "Mounting image at $TMP..."
    mount -o loop "$IMAGE_PATH" "$TMP"
    tar -xf rootfs.tar -C "$TMP"
    fix_exported_rootfs "$TMP"
    bake_authorized_keys "$TMP"
    echo "Unmounting image..."
    umount "$TMP"
    rmdir "$TMP"
    rm -f rootfs.tar
}

# Shrink the filesystem (and file) to its contents. init.sh copies the image into the pod on
# every session start and then grows it to IMAGE_SIZE there, so a smaller image starts faster
# (vm_lab: ~350M instead of the full build size).
shrink_image() {
    echo "Shrinking image to its contents..."
    e2fsck -fy "$IMAGE_PATH" || [ $? -le 1 ]   # 1 = errors corrected
    resize2fs -M "$IMAGE_PATH"
    ls -lh "$IMAGE_PATH"
}

# Execute functions
extract
create_image
shrink_image
