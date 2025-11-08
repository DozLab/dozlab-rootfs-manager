.PHONY: help build-all build-base build-k8s build-vm build-custom-initrd clean push-all

# Default target
help:
	@echo "Dozlab Rootfs Manager - Build System"
	@echo ""
	@echo "Available targets:"
	@echo "  make build-all           - Build all lab images (base + all labs)"
	@echo "  make build-base          - Build base image only"
	@echo "  make build-k8s           - Build Kubernetes lab image"
	@echo "  make build-vm            - Build VM lab image"
	@echo "  make build-custom-initrd - Build custom initrd lab image"
	@echo "  make push-all            - Push all images to registry"
	@echo "  make clean               - Remove all built images"
	@echo ""
	@echo "Configuration:"
	@echo "  REGISTRY         - Docker registry (default: docker.io/dozman99)"
	@echo "  TAG              - Image tag (default: git SHA)"
	@echo "  OS_VERSION       - Ubuntu version (default: 22.04)"
	@echo "  KUBERNETES_VERSION - K8s version (default: 1.30)"

# Build all images
build-all: build-base build-k8s build-vm build-custom-initrd
	@echo "All images built successfully!"

# Build base image
build-base:
	@echo "Building base image..."
	$(MAKE) -C base_image build

# Build Kubernetes lab
build-k8s: build-base
	@echo "Building Kubernetes lab image..."
	$(MAKE) -C labs/k8_lab build

# Build VM lab
build-vm: build-base
	@echo "Building VM lab image..."
	$(MAKE) -C labs/vm_lab build

# Build custom initrd lab
build-custom-initrd:
	@echo "Building custom initrd lab image..."
	$(MAKE) -C labs/custom-initrd build

# Push all images to registry
push-all:
	@echo "Pushing all images to registry..."
	$(MAKE) -C base_image push
	$(MAKE) -C labs/k8_lab push
	$(MAKE) -C labs/vm_lab push
	$(MAKE) -C labs/custom-initrd push
	@echo "All images pushed successfully!"

# Clean up all images
clean:
	@echo "Cleaning up Docker images..."
	docker images | grep dozlab- | awk '{print $$3}' | xargs -r docker rmi -f || true
	@echo "Cleanup complete!"
