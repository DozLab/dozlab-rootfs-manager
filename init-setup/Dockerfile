# syntax=docker/dockerfile:1
# Init container that puts a lab's VM rootfs into the pod's volume (see init.sh).
#
#   docker build --build-arg LAB_IMAGE=dozman99/dozlab-vm:<tag> -t dozman99/dozlab-init-vm:<tag> .
#
# The lab image (any labs/* image) is turned into an ext4 filesystem inside the build with
# `mkfs.ext4 -d`: no loop mount, no sudo, no `docker export`. `--target init` builds the
# container without a baked-in image, for use with IMAGE_DOWNLOAD_URL.
ARG LAB_IMAGE=dozman99/dozlab-vm:latest

FROM ${LAB_IMAGE} AS lab

FROM alpine:3.20 AS rootfs
RUN apk add --no-cache coreutils e2fsprogs e2fsprogs-extra
ARG VM_HOSTNAME=dozlab-vm
# Public key for root's authorized_keys. Local clusters only: don't bake a key into an image
# you push.
ARG AUTHORIZED_KEY=
# Copy the lab's filesystem out (GNU cp -a keeps owners, modes, links and xattrs), then write
# the files a container runtime normally provides and a VM has to have itself.
RUN --mount=type=bind,from=lab,target=/lab \
    cp -a /lab /rootfs \
 && echo "$VM_HOSTNAME" > /rootfs/etc/hostname \
 && printf '127.0.0.1 localhost\n127.0.1.1 %s\n::1 localhost ip6-localhost ip6-loopback\n' \
      "$VM_HOSTNAME" > /rootfs/etc/hosts \
 && ln -sfn ../run/systemd/resolve/stub-resolv.conf /rootfs/etc/resolv.conf \
 # cloud-init must see every VM as a first boot: drop any state a build step left behind
 && rm -rf /rootfs/var/lib/cloud/instance /rootfs/var/lib/cloud/instances \
      /rootfs/var/lib/cloud/data /rootfs/var/lib/cloud/sem \
 && if [ -n "$AUTHORIZED_KEY" ]; then \
      install -d -m 0700 /rootfs/root/.ssh \
      && echo "$AUTHORIZED_KEY" > /rootfs/root/.ssh/authorized_keys \
      && chmod 0600 /rootfs/root/.ssh/authorized_keys; \
    fi \
 # Build with headroom, then shrink to the contents: init.sh copies the image on every
 # session start and grows it to IMAGE_SIZE there. (One RUN, so /rootfs is never a layer.)
 && size_mb=$(( $(du -sm /rootfs | cut -f1) * 13 / 10 + 64 )) \
 && truncate -s "${size_mb}M" /image.ext4 \
 && mkfs.ext4 -q -d /rootfs /image.ext4 \
 && rm -rf /rootfs \
 && { e2fsck -fy /image.ext4 >/dev/null || [ $? -le 1 ]; } \
 && resize2fs -M /image.ext4 \
 && ls -lh /image.ext4

FROM alpine:3.20 AS init
RUN apk add --no-cache e2fsprogs e2fsprogs-extra
WORKDIR /app
COPY init.sh init.sh
CMD ["/app/init.sh"]

FROM init
COPY --from=rootfs /image.ext4 /app/image.ext4
