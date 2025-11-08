#!/bin/sh

: ${IMAGE_PATH="/srv/vm/kernels/image.ext4"}
: ${LOCAL_DEV_IMAGE_PATH="/app/image.ext4"}
: ${IMAGE_DOWNLOAD_URL=""}
: ${IMAGE_SIZE="1G"}

IMAGE_FOLDER=$(dirname $IMAGE_PATH)

echo "IMAGE_FOLDER=$IMAGE_FOLDER"
echo "IMAGE_PATH=$IMAGE_PATH"
# echo "IMAGE_DOWNLOAD_URL=$IMAGE_DOWNLOAD_URL"
echo "IMAGE_SIZE=$IMAGE_SIZE"

echo "Ensuring image folder $IMAGE_FOLDER"
mkdir -p $IMAGE_FOLDER
mv ${LOCAL_DEV_IMAGE_PATH} ${IMAGE_PATH} || echo "No resource found locally, validate download process"

# If image exists locally and no download URL specified, resize the existing image
if [ -f "$IMAGE_PATH" ] && [ -z "$IMAGE_DOWNLOAD_URL" ]; then
    echo "Resizing existing local image"
    e2fsck -y -f ${IMAGE_PATH}
    resize2fs $IMAGE_PATH $IMAGE_SIZE
    exit 0
fi

# If image doesn't exist, download it
if [ ! -f "$IMAGE_PATH" ]; then
    if [ -z "$IMAGE_DOWNLOAD_URL" ]; then
        echo "Error: RootFS image not found at $IMAGE_PATH and no IMAGE_DOWNLOAD_URL provided"
        exit 1
    fi

    echo "RootFS image not found: $IMAGE_PATH"
    echo "Downloading from $IMAGE_DOWNLOAD_URL"
    wget $IMAGE_DOWNLOAD_URL -O $IMAGE_PATH
fi

# Resize the image
echo "Resizing image to $IMAGE_SIZE"
e2fsck -y -f ${IMAGE_PATH}
resize2fs $IMAGE_PATH $IMAGE_SIZE
exit 0
