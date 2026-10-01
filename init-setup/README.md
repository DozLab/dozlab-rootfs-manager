# Kubecracker Init Container

This repository builds the container image to prepare the rootfs image for a Firecracker VM in Kubecracker. This container will run as a init container followed by Firecracker in Docker container.

## Environment Varibales

- `IMAGE_PATH` : Where the VM rootfs goes. Defaults to /srv/vm/kernels/image.ext4
- `IMAGE_DOWNLOAD_URL` : URL to fetch the image from. Optional: without it, the image baked into the container (`make build-init`) is used
- `IMAGE_SIZE` : Size to resize the image. This will be the disk size of the VM. Defaults to 1G. Not used when `WRITABLE_DISK_PATH` is set
- `WRITABLE_DISK_PATH` : Where the session's writable disk goes. Optional: when set, the image at `IMAGE_PATH` is a read-only base that is never changed (see below)
- `WRITABLE_DISK_SIZE` : Size of the writable disk. This is the disk space the VM sees. Defaults to 1G

Per-session setup (read by cloud-init in the VM on first boot; see `labs/vm_lab`):

- `SSH_AUTHORIZED_KEY` : Public key(s) for root, one per line
- `SESSION_ID` : Makes the cloud-init instance id `dozlab-<SESSION_ID>`
- `VM_HOSTNAME` : The VM's hostname. Defaults to dozlab-vm
- `USER_DATA` : A complete `#cloud-config`; replaces the one generated from `SSH_AUTHORIZED_KEY`

When `SSH_AUTHORIZED_KEY` or `USER_DATA` is set, the container writes `meta-data` and `user-data` to `/var/lib/cloud/seed/nocloud/`: on the writable disk when there is one, otherwise inside the image (with `debugfs`, no mount needed). Without them, no seed is written and cloud-init stays off. The init container owns disk sizing; cloud-init's resize is turned off.

## Read-only base and writable disk

With `WRITABLE_DISK_PATH` set, the container leaves the image at `IMAGE_PATH` exactly as it was built (no filesystem check, no resize, no seed) and creates a second disk for the session:

- a sparse ext4 file of `WRITABLE_DISK_SIZE`, so it only takes the space the VM has written
- `upper/` holds everything the VM changes, and `work/` is scratch space the overlay needs
- the cloud-init seed is at `upper/var/lib/cloud/seed/nocloud/`, which the VM sees as `/var/lib/cloud/seed/nocloud/`

The disk is made and filled in one step with `mkfs.ext4 -d`, so there's no mount and no privileges are needed. The VM has to boot with the base read-only, this disk as its second drive and `init=/sbin/overlay-init` (`start-firecracker.sh` in dozlab-infra does all three when it gets the same `WRITABLE_DISK_PATH`); see `labs/vm_lab/README.md`.

A disk already at `WRITABLE_DISK_PATH` is kept as it is, seed included. On a volume that outlives the pod, the session comes back with its files, and cloud-init treats the start as a reboot (same instance id), so the SSH host keys stay the same.

Without `WRITABLE_DISK_PATH`, the image is the VM's one read-write disk, as before: it is checked, grown to `IMAGE_SIZE`, and the seed is written into it.

An image already at `IMAGE_PATH` is kept (and, without a writable disk, only resized), so re-running the init container on the same volume doesn't replace the VM's disk. The container exits non-zero if there's no image to use, or if the download, filesystem check, resize or writable-disk creation fails.
