# Kubecracker Init Container

This repository builds the container image to prepare the rootfs image for a Firecracker VM in Kubecracker. This container will run as a init container followed by Firecracker in Docker container.

## Environment Varibales

- `IMAGE_PATH` : Where the VM rootfs goes. Defaults to /srv/vm/kernels/image.ext4
- `IMAGE_DOWNLOAD_URL` : URL to fetch the image from. Optional: without it, the image baked into the container (`make build-init`) is used
- `IMAGE_SIZE` : Size to resize the image. This will be the disk size of the VM. Defaults to 1G

An image already at `IMAGE_PATH` is kept and only resized, so re-running the init container on the same volume doesn't replace the VM's disk. The container exits non-zero if there's no image to use, or if the download, filesystem check or resize fails.
