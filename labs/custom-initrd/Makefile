.PHONY: init-local build  push


DOCKER := docker
BUILD_DATE:=$(shell date --rfc-3339=seconds)
GIT_SHA:=$(shell git rev-parse HEAD)

REGISTRY?=docker.io/dozman99
IMAGE_NAME?=$(REGISTRY)/lab-custom-initrd-os
TAG?=$(shell git rev-parse --short HEAD)


build:
	$(DOCKER) build -t $(IMAGE_NAME):$(TAG)  \
		--build-arg TAG=$(TAG) \
		--label "org.opencontainers.image.created"="$(BUILD_DATE)" \
		--label "org.opencontainers.image.authors"="Liquid Metal Authors" \
		--label "org.opencontainers.image.url"="https://github.com/weaveworks-liquidmetal/image-builder" \
		--label "org.opencontainers.image.source"="https://github.com/weaveworks-liquidmetal/image-builder/tree/main/capmvm/kubernetes" \
		--label "org.opencontainers.image.revision"="$(GIT_SHA)" \
		--label "org.opencontainers.image.vendor"="Weaveworks" \
		--label "org.opencontainers.image.description"="A image to use for a microvm volume to test" \
		.
push:
	$(DOCKER) push $(IMAGE_NAME):$(TAG)

# init-local builds a static binary for local testing, but the lab uses a multi-stage
# Dockerfile for this instead - https://docs.docker.com/develop/develop-images/multistage-build/
init-local:
	cd init && \
	go build --tags netgo --ldflags '-s -w -extldflags "-lm -lstdc++ -static"' -o init main.go

# Extract a root filesystem into a tar
# extract:
# 	docker rm -f extract || :
# 	rm -rf rootfs.tar || :
# 	docker create --name extract dozman99/custom-initrd
# 	docker export extract -o rootfs.tar
# 	docker rm -f extract

# # Allocate a 5GB disk image, then extract the rootfs.tar from the 
# # container into it
# image:
# 	set -e 
# 	rm -rf rootfs.img || : ;\
# 	sudo fallocate -l 5G ./rootfs.img  ;\
# 	sudo mkfs.ext4 ./rootfs.img  ;\
# 	TMP=$$(mktemp -d)  ;\
# 	echo $$TMP  ;\
# 	sudo mount -o loop ./rootfs.img $$TMP  ;\
# 	sudo tar -xvf rootfs.tar -C $$TMP  ;\
# 	sudo umount $$TMP

