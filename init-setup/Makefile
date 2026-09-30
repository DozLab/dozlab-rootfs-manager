.PHONY: build build-no-image push

DOCKER := docker
BUILD_DATE:=$(shell date --rfc-3339=seconds)
GIT_SHA:=$(shell git rev-parse HEAD)

REGISTRY?=docker.io/dozman99
TAG?=$(shell git rev-parse --short HEAD)

# Which lab's image becomes the VM rootfs: vm, k8s or custom-initrd (build it first, e.g.
# make build-vm at the repo root)
LAB?=vm
LAB_IMAGE?=$(REGISTRY)/dozlab-$(LAB):$(TAG)
IMAGE_NAME?=$(REGISTRY)/dozlab-init-$(LAB)
# Optional public key file baked in for root; local clusters only, never for pushed images
AUTHORIZED_KEYS?=

build:
	$(DOCKER) build -t $(IMAGE_NAME):$(TAG) \
		--build-arg LAB_IMAGE=$(LAB_IMAGE) \
		$(if $(AUTHORIZED_KEYS),--build-arg AUTHORIZED_KEY="$$(cat $(AUTHORIZED_KEYS))") \
		--label "org.opencontainers.image.created"="$(BUILD_DATE)" \
		--label "org.opencontainers.image.source"="https://github.com/DozLab/dozlab-rootfs-manager" \
		--label "org.opencontainers.image.revision"="$(GIT_SHA)" \
		--label "org.opencontainers.image.description"="Init container with the $(LAB) lab rootfs baked in" \
		.

# Init container without a baked-in rootfs (sessions set IMAGE_DOWNLOAD_URL)
build-no-image:
	$(DOCKER) build -t $(REGISTRY)/dozlab-init:$(TAG) --target init .

push:
	$(DOCKER) push $(IMAGE_NAME):$(TAG)
