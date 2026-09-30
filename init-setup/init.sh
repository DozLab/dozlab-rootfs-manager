#!/bin/sh
# Puts the VM rootfs at IMAGE_PATH and grows it to IMAGE_SIZE. The rootfs comes from, in order:
#   1. an image already at IMAGE_PATH (init container re-run on the same volume: keep the VM's disk)
#   2. IMAGE_DOWNLOAD_URL, if set
#   3. the image baked into this container at LOCAL_DEV_IMAGE_PATH (make build-init)
# Any failure exits non-zero, so the pod never starts Firecracker on a missing or unresized disk.
set -eu

: "${IMAGE_PATH:=/srv/vm/kernels/image.ext4}"
: "${LOCAL_DEV_IMAGE_PATH:=/app/image.ext4}"
: "${IMAGE_DOWNLOAD_URL:=}"
: "${IMAGE_SIZE:=1G}"

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
