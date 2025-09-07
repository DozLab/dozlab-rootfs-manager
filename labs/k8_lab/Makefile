.PHONY: build  push


DOCKER := docker
BUILD_DATE:=$(shell date --rfc-3339=seconds)
GIT_SHA:=$(shell git rev-parse HEAD)

CONTAINERD_VERSION?=1.5.9
OS_VERSION?=22.04# RELEASE follows the UBUNTU release
REGISTRY?=docker.io/dozman99
IMAGE_NAME?=$(REGISTRY)/lab-k8-os
TAG?=$(shell git rev-parse --short HEAD)

RELEASE_VERSIONS?=1.21.8 # 1.22.3 1.22.8 1.23.5 # RELEASE follows the kubernetes release


build:
	$(DOCKER) build -t $(IMAGE_NAME):$(TAG)\
		--build-arg KUBERNETES_VERSION=$(RELEASE_VERSIONS) \
		--build-arg TAG=$(TAG) --build-arg OS_VERSION=$(OS_VERSION) \
		--build-arg CONTAINERD_VERSION=$(CONTAINERD_VERSION) \
		--label "org.opencontainers.image.created"="$(BUILD_DATE)" \
		--label "org.opencontainers.image.authors"="Liquid Metal Authors" \
		--label "org.opencontainers.image.url"="https://github.com/weaveworks-liquidmetal/image-builder" \
		--label "org.opencontainers.image.source"="https://github.com/weaveworks-liquidmetal/image-builder/tree/main/capmvm/kubernetes" \
		--label "org.opencontainers.image.revision"="$(GIT_SHA)" \
		--label "org.opencontainers.image.vendor"="Weaveworks" \
		--label "org.opencontainers.image.licenses"="MPL-2.0" \
		--label "org.opencontainers.image.description"="A image to use for a microvm volume when creating a cluster" \
		--label "works.weave.liquidmetal.image_version"="$(OS_VERSION)" \
		.
push:
	$(DOCKER) push $(IMAGE_NAME):$(TAG)
