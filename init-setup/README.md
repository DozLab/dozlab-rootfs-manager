# Kubecracker Init Container

This repository builds the container image to prepare the rootfs image for a Firecracker VM in Kubecracker. This container will run as a init container followed by Firecracker in Docker container.

## Environment Varibales

- `IMAGE_PATH` : Where the VM rootfs goes. Defaults to /srv/vm/kernels/image.ext4
- `IMAGE_DOWNLOAD_URL` : URL to fetch the image from. Optional: without it, the image baked into the container (`make build-init`) is used
- `IMAGE_SIZE` : Size to resize the image. This will be the disk size of the VM. Defaults to 1G

Per-session setup (read by cloud-init in the VM on first boot; see `labs/vm_lab`):

- `SSH_AUTHORIZED_KEY` : Public key(s) for root, one per line
- `SESSION_ID` : Makes the cloud-init instance id `dozlab-<SESSION_ID>`
- `VM_HOSTNAME` : The VM's hostname. Defaults to dozlab-vm
- `USER_DATA` : A complete `#cloud-config`; replaces the one generated from `SSH_AUTHORIZED_KEY`

When `SSH_AUTHORIZED_KEY` or `USER_DATA` is set, the container writes `meta-data` and `user-data` into `/var/lib/cloud/seed/nocloud/` inside the image (with `debugfs`, no mount needed). Without them, no seed is written and cloud-init stays off. The init container owns resizing; cloud-init's resize is turned off.

An image already at `IMAGE_PATH` is kept and only resized, so re-running the init container on the same volume doesn't replace the VM's disk. The container exits non-zero if there's no image to use, or if the download, filesystem check or resize fails.
