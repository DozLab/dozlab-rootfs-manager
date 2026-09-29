.PHONY: build image push

DOCKER := docker
BUILD_DATE:=$(shell date --rfc-3339=seconds)
GIT_SHA:=$(shell git rev-parse HEAD)

REGISTRY?=docker.io/dozman99
IMAGE_NAME?=$(REGISTRY)/init-setup
TAG?=$(shell git rev-parse --short HEAD)

# Lab image baked in as the VM rootfs (build it first: make build-vm at the repo root)
ROOTFS_IMAGE?=$(REGISTRY)/dozlab-vm:$(TAG)
# Optional public key file baked in for root; local clusters only, never for pushed images
AUTHORIZED_KEYS?=
# local_create_image.sh loop-mounts the image, which needs root
SUDO?=sudo

build: image
	$(DOCKER) build -t $(IMAGE_NAME):$(TAG) \
	    --build-arg OS_VERSION=$(OS_VERSION) \
		--label "org.opencontainers.image.created"="$(BUILD_DATE)" \
		--label "org.opencontainers.image.authors"="Liquid Metal Authors" \
		--label "org.opencontainers.image.url"="https://github.com/weaveworks-liquidmetal/image-builder" \
		--label "org.opencontainers.image.source"="https://github.com/weaveworks-liquidmetal/image-builder/tree/main/capmvm/kubernetes" \
		--label "org.opencontainers.image.revision"="$(GIT_SHA)" \
		--label "org.opencontainers.image.vendor"="Weaveworks" \
		--label "org.opencontainers.image.licenses"="MPL-2.0" \
		--label "org.opencontainers.image.description"="A image to use for a microvm volume when creating a cluster using Cluster API Provider Microvm" \
		--label "works.weave.liquidmetal.image_version"="$(OS_VERSION)" \
		.

# Build ./disk/image.ext4 from ROOTFS_IMAGE (shrunk to its contents)
image:
	$(SUDO) env IMAGE_PATH=./disk/image.ext4 CONTAINER_IMAGE_NAME=$(ROOTFS_IMAGE) \
		AUTHORIZED_KEYS=$(AUTHORIZED_KEYS) ./local_create_image.sh
	$(SUDO) chown -R $(shell id -u):$(shell id -g) ./disk

push:
	$(DOCKER) push $(IMAGE_NAME):$(TAG)
