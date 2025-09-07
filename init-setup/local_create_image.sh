#!/bin/bash

# Enable debugging
set -ex

# Set default values if not provided
: "${IMAGE_PATH:="./disk/image.ext4"}"
: "${IMAGE_SIZE:=1G}"
: "${BUILD_TEST:=false}"
: "${CONTAINER_IMAGE_NAME:=dozman99/lab-custom-initrd-os:0b51c75}"

# Determine the folder where the image is stored
IMAGE_FOLDER=$(dirname "$IMAGE_PATH")

# Output the variables
echo "IMAGE_FOLDER=$IMAGE_FOLDER"
echo "IMAGE_PATH=$IMAGE_PATH"
echo "IMAGE_SIZE=$IMAGE_SIZE"

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

# I will put this in a container because of permision
# Create disk image
create_image() {
    echo "Creating disk image..."
    rm -f "$IMAGE_PATH" || true
    fallocate -l "$IMAGE_SIZE" "$IMAGE_PATH"
    mkfs.ext4 "$IMAGE_PATH"

    TMP=$(mktemp -d)
    echo "Mounting image at $TMP..."
    mount -o loop "$IMAGE_PATH" "$TMP"
    tar -xvf rootfs.tar -C "$TMP"
    echo "Unmounting image..."
    umount "$TMP"
}

# Execute functions
extract
create_image