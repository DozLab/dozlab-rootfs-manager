# Dozlab Rootfs Manager

Container and root filesystem management for lab environments, providing custom VM images for Firecracker-based virtual machines. This repository manages the complete lifecycle from base images to specialized lab environments.

## Features

- **Base Image**: Ubuntu 22.04-based foundational image with systemd, networking, and SSH support
- **Init Container**: Automated rootfs image download, preparation, and resizing for Firecracker VMs
- **Kubernetes Lab**: Complete K8s environment with kubeadm, kubelet, kubectl, and containerd runtime
- **VM Lab**: Minimal general-purpose VM environment with basic utilities
- **Firecracker Integration**: Purpose-built for running labs in Firecracker MicroVMs
- **Build Automation**: Makefile-based build system for each component

## Architecture

```
┌──────────────────┐    ┌─────────────────┐    ┌──────────────────┐
│   Base Image     │───▶│  Lab Images     │───▶│ Firecracker VMs  │
│                  │    │                 │    │                  │
│ • Ubuntu 22.04   │    │ • K8s Lab       │    │ • Running Labs   │
│ • systemd        │    │ • VM Lab        │    │ • ext4 Rootfs    │
│ • SSH Server     │    │ • Custom Labs   │    │ • Network Ready  │
│ • Network Tools  │    │                 │    │                  │
└──────────────────┘    └─────────────────┘    └──────────────────┘
         ▲
         │
         │              ┌─────────────────┐
         └──────────────│  Init Setup     │
                        │                 │
                        │ • Download      │
                        │ • Resize        │
                        │ • Prepare       │
                        └─────────────────┘
```

## Components

### 1. Base Image (`base_image/`)

Ubuntu 22.04-based foundational image that serves as the base for all lab environments.

**Installed Packages**:
- `systemd` - System and service manager (runs as PID 1)
- `openssh-server` - SSH server for remote access
- `udev` and `kmod` - Device management and kernel module loading
- `iproute2`, `iputils-ping`, `net-tools` - Network configuration utilities
- `curl`, `wget` - HTTP clients
- `vim-tiny` - Text editor
- `dbus` - Inter-process communication
- `haveged`, `rng-tools` - Random number generation
- `sudo` - Privilege escalation

**Build Arguments**:
- `OS_VERSION` - Ubuntu version (default: 22.04)

**Usage**:
```bash
cd base_image
docker build -t dozlab-base:latest .
# Or with custom OS version
docker build --build-arg OS_VERSION=20.04 -t dozlab-base:20.04 .
```

### 2. Init Setup (`init-setup/`)

Alpine-based init container that downloads, prepares, and resizes rootfs images for Firecracker VMs. This container runs as an init container in Kubernetes before the Firecracker VM starts.

**Purpose**:
- Download pre-built rootfs images from remote URLs
- Copy local development images to the correct location
- Resize ext4 filesystem images to desired disk size
- Prepare images for Firecracker VM consumption

**Environment Variables**:
- `IMAGE_PATH` - Destination path for the rootfs image (default: `/srv/vm/kernels/image.ext4`)
- `LOCAL_DEV_IMAGE_PATH` - Local development image path (default: `/app/image.ext4`)
- `IMAGE_DOWNLOAD_URL` - URL to fetch the rootfs image from (optional)
- `IMAGE_SIZE` - Target disk size for the VM (default: `1G`)

**Workflow**:
1. Creates the image directory if it doesn't exist
2. Attempts to move local image to destination (for development)
3. If no local image and download URL provided, downloads from URL
4. Runs `e2fsck` to check filesystem integrity
5. Resizes the ext4 filesystem to specified size

**Usage**:
```bash
cd init-setup
docker build -t dozlab-init:latest .

# Run with environment variables
docker run --rm \
  -v /path/to/disk:/srv/vm/kernels \
  -e IMAGE_DOWNLOAD_URL="https://example.com/rootfs.ext4" \
  -e IMAGE_SIZE="2G" \
  dozlab-init:latest
```

### 3. Kubernetes Lab (`labs/k8_lab/`)

Complete Kubernetes lab environment built on the base image with full K8s tooling and container runtime.

**Installed Components**:
- **Containerd** v1.7.19 - Container runtime with CNI plugins
- **Kubernetes** v1.30 - kubeadm, kubelet, kubectl
- **Linux Kernel** - `linux-image-virtual` for VM support
- **Additional Tools**: cloud-init, dnsutils, jq, less

**Configuration**:
- Kernel modules for networking: `overlay`, `br_netfilter`
- Sysctl parameters for Kubernetes networking
- Containerd configured as container runtime
- Kubelet configured to use containerd via CRI
- systemd units enabled for containerd and kubelet
- Root password: `root` (for console access)

**Build Arguments**:
- `TAG` - Base image tag (default: `test`)
- `ARCH` - Architecture (default: `amd64`)
- `CONTAINERD_VERSION` - Containerd version (default: `1.7.19`)
- `KUBERNETES_VERSION` - K8s version (default: `1.30`)

**Usage**:
```bash
cd labs/k8_lab
docker build -t dozlab-k8s:latest .

# With custom versions
docker build \
  --build-arg TAG=latest \
  --build-arg KUBERNETES_VERSION=1.29 \
  -t dozlab-k8s:1.29 .
```

### 4. VM Lab (`labs/vm_lab/`)

Minimal general-purpose VM environment for basic use cases.

**Configuration**:
- Machine ID cleared (for unique VM instances)
- SSH server configured (locale warnings disabled)
- Root password: `root` (for console access)
- Root SSH directory prepared

**Build Arguments**:
- `TAG` - Base image tag (default: `test`)

**Usage**:
```bash
cd labs/vm_lab
docker build -t dozlab-vm:latest .
```

### 5. Custom Initrd Lab (`labs/custom-initrd/`)

Ultra-lightweight Alpine-based image with a custom Go init system for specialized use cases.

**Purpose**:
- Provide a minimal container runtime environment
- Custom init process written in Go
- Static binary compilation for portability
- Suitable for MicroVM environments requiring minimal overhead

**Build Process**:
The lab uses a multi-stage Docker build:
1. **Build Stage**: Uses `golang:1.20-alpine` to compile the Go init binary
2. **Runtime Stage**: Uses `alpine:3.18` with minimal utilities

**Installed Components**:
- `curl` - HTTP client
- `ca-certificates` - SSL certificate management
- `htop` - Process monitoring

**Build Configuration**:
- Go build flags: `--tags netgo --ldflags '-s -w -extldflags "-lm -lstdc++ -static"'`
- Static linking for standalone binary
- Strips debug symbols for minimal size

**Directory Structure**:
```
labs/custom-initrd/
├── Dockerfile          # Multi-stage build definition
├── Makefile           # Build automation with local and container builds
├── init/              # Go source code for init process (not tracked in git)
│   └── main.go        # Custom init implementation
└── .gitignore         # Excludes built binaries
```

**Usage**:
```bash
cd labs/custom-initrd

# Build the image (requires init/main.go to exist)
make build

# Or build locally for testing
make init-local

# Push to registry
make push
```

**Note**: The `init/` directory containing the Go source code (`main.go`) must be created separately and is not tracked in git per the `.gitignore` configuration. The init binary serves as PID 1 in the container.

## Getting Started

### Prerequisites

- Docker or compatible container runtime
- Make (each component has its own Makefile)
- For init-setup: Volume mount point for disk images

### Building Images

Each component can be built independently using Docker or Make:

#### 1. Build Base Image First

The base image is required for all lab environments:

```bash
cd base_image
docker build -t dozlab-base:latest .
```

#### 2. Build Init Setup Container

```bash
cd init-setup
docker build -t dozlab-init:latest .
```

#### 3. Build Lab Images

Lab images depend on the base image. Make sure to push the base image to a registry or use local tags:

```bash
# Kubernetes Lab
cd labs/k8_lab
docker build --build-arg TAG=latest -t dozlab-k8s:latest .

# VM Lab
cd labs/vm_lab
docker build --build-arg TAG=latest -t dozlab-vm:latest .

# Custom Initrd Lab (requires init/main.go to be present)
cd labs/custom-initrd
make build
```

### Using Make

Each component includes a Makefile for build automation:

```bash
# In each directory (base_image, labs/k8_lab, labs/vm_lab, etc.)
make          # Shows available targets
make build    # Builds the image
make push     # Pushes to registry (configure registry in Makefile)
```

## Directory Structure

```
dozlab-rootfs-manager/
├── base_image/              # Ubuntu 22.04 base image
│   └── Dockerfile          # Base image definition
├── init-setup/             # Init container for rootfs preparation
│   ├── Dockerfile          # Alpine-based init container
│   ├── init.sh             # Rootfs download and resize script
│   ├── local_create_image.sh  # Local image creation helper
│   ├── README.md           # Init setup documentation
│   └── disk/               # Directory for local disk images
└── labs/                   # Lab environment images
    ├── k8_lab/             # Kubernetes lab
    │   ├── Dockerfile      # K8s lab image with kubeadm, containerd
    │   └── Makefile        # Build automation
    ├── vm_lab/             # General VM lab
    │   ├── Dockerfile      # Minimal VM lab image
    │   └── Makefile        # Build automation
    └── custom-initrd/      # Custom Go-based init system
        ├── Dockerfile      # Multi-stage build for Go init
        ├── Makefile        # Build automation
        ├── .gitignore      # Excludes init binaries
        └── init/           # Go source code (not tracked in git)
            └── main.go     # Custom init implementation
```

## Converting Container Images to Rootfs

To use these images with Firecracker, you need to convert them to ext4 filesystem images:

### Method 1: Using docker export

```bash
# Build your lab image
docker build -t dozlab-k8s:latest labs/k8_lab/

# Create a container (don't start it)
docker create --name temp-container dozlab-k8s:latest

# Export the container filesystem
docker export temp-container | sudo tar -C /mnt/rootfs -xf -

# Create ext4 image (adjust size as needed)
dd if=/dev/zero of=rootfs.ext4 bs=1M count=4096
mkfs.ext4 rootfs.ext4
sudo mount rootfs.ext4 /mnt/rootfs
# Copy files, then umount

# Cleanup
docker rm temp-container
```

### Method 2: Using init-setup Container

The init-setup container can download and prepare pre-built rootfs images:

```bash
docker run --rm \
  -v $(pwd)/disk:/srv/vm/kernels \
  -e IMAGE_DOWNLOAD_URL="https://storage.googleapis.com/your-bucket/rootfs.ext4" \
  -e IMAGE_SIZE="4G" \
  dozlab-init:latest
```

## Firecracker Integration

These images are designed to run as rootfs in Firecracker MicroVMs:

### Example Firecracker Configuration

```json
{
  "boot-source": {
    "kernel_image_path": "/var/lib/firecracker/vmlinux",
    "boot_args": "console=ttyS0 reboot=k panic=1 pci=off init=/lib/systemd/systemd"
  },
  "drives": [
    {
      "drive_id": "rootfs",
      "path_on_host": "/srv/vm/kernels/image.ext4",
      "is_root_device": true,
      "is_read_only": false
    }
  ],
  "machine-config": {
    "vcpu_count": 2,
    "mem_size_mib": 2048
  },
  "network-interfaces": [
    {
      "iface_id": "eth0",
      "guest_mac": "AA:FC:00:00:00:01",
      "host_dev_name": "tap0"
    }
  ]
}
```

### Kubernetes Integration

In a Kubernetes environment, use the init-setup container as an init container:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: firecracker-lab
spec:
  initContainers:
  - name: init-rootfs
    image: dozlab-init:latest
    env:
    - name: IMAGE_DOWNLOAD_URL
      value: "https://storage.googleapis.com/your-bucket/dozlab-k8s.ext4"
    - name: IMAGE_SIZE
      value: "4G"
    - name: IMAGE_PATH
      value: "/srv/vm/kernels/image.ext4"
    volumeMounts:
    - name: vm-disk
      mountPath: /srv/vm/kernels
  containers:
  - name: firecracker
    image: your-firecracker-image:latest
    securityContext:
      privileged: true
    volumeMounts:
    - name: vm-disk
      mountPath: /srv/vm/kernels
  volumes:
  - name: vm-disk
    emptyDir: {}
```

## Configuration Reference

### Base Image Build Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `OS_VERSION` | `22.04` | Ubuntu version |

### K8s Lab Build Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `TAG` | `test` | Base image tag |
| `ARCH` | `amd64` | Architecture |
| `CONTAINERD_VERSION` | `1.7.19` | Containerd version |
| `KUBERNETES_VERSION` | `1.30` | Kubernetes version |

### VM Lab Build Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `TAG` | `test` | Base image tag |

### Custom Initrd Lab Build Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `REGISTRY` | `docker.io/dozman99` | Container registry |
| `IMAGE_NAME` | `$(REGISTRY)/lab-custom-initrd-os` | Full image name |
| `TAG` | `$(git rev-parse --short HEAD)` | Image tag (git commit hash) |

**Makefile Targets**:
- `make build` - Build the Docker image with multi-stage build
- `make push` - Push image to registry
- `make init-local` - Build init binary locally for testing

### Init-Setup Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `IMAGE_PATH` | `/srv/vm/kernels/image.ext4` | Destination path for rootfs |
| `LOCAL_DEV_IMAGE_PATH` | `/app/image.ext4` | Local development image path |
| `IMAGE_DOWNLOAD_URL` | (empty) | URL to download rootfs from |
| `IMAGE_SIZE` | `1G` | Target disk size |

## Testing and Validation

### Testing Base Image

```bash
# Build and test base image
cd base_image
docker build -t dozlab-base:test .

# Verify systemd and services
docker run --rm -it --privileged dozlab-base:test /lib/systemd/systemd

# Test SSH (in separate terminal)
docker run -d -p 2222:22 --name test-base dozlab-base:test
ssh root@localhost -p 2222  # password: root
docker stop test-base && docker rm test-base
```

### Testing K8s Lab Image

```bash
cd labs/k8_lab
docker build --build-arg TAG=test -t dozlab-k8s:test .

# Verify Kubernetes tools
docker run --rm dozlab-k8s:test kubeadm version
docker run --rm dozlab-k8s:test kubectl version --client
docker run --rm dozlab-k8s:test containerd --version
```

### Testing Init-Setup Container

```bash
cd init-setup
docker build -t dozlab-init:test .

# Test with local image
mkdir -p test-disk
docker run --rm \
  -v $(pwd)/test-disk:/srv/vm/kernels \
  -e IMAGE_SIZE="2G" \
  dozlab-init:test

# Verify the resized image exists
ls -lh test-disk/image.ext4
```

### Testing Custom Initrd Lab

```bash
cd labs/custom-initrd

# Build init binary locally
make init-local

# Build container image (requires init/main.go)
make build

# Test the container
docker run --rm -it dozman99/lab-custom-initrd-os:$(git rev-parse --short HEAD)
```

### Testing with Firecracker

```bash
# 1. Convert your lab image to ext4 (see "Converting Container Images to Rootfs")
# 2. Create Firecracker config (see "Firecracker Integration")
# 3. Start Firecracker VM
firecracker --api-sock /tmp/firecracker.sock --config-file config.json

# 4. Access via console
# Press Enter in the Firecracker console
# Login: root / root
```

## Image Registry

### Tagging Convention

```bash
# Base images
dozlab-base:latest
dozlab-base:22.04
dozlab-base:20.04

# Lab images
dozlab-k8s:latest
dozlab-k8s:k8s-1.30
dozlab-k8s:k8s-1.29
dozlab-vm:latest

# Custom initrd
dozman99/lab-custom-initrd-os:latest
dozman99/lab-custom-initrd-os:<git-sha>

# Init container
dozlab-init:latest
```

### Publishing to Registry

```bash
# Tag for your registry
docker tag dozlab-base:latest your-registry.com/dozlab-base:latest
docker tag dozlab-k8s:latest your-registry.com/dozlab-k8s:k8s-1.30
docker tag dozlab-vm:latest your-registry.com/dozlab-vm:latest
docker tag dozlab-init:latest your-registry.com/dozlab-init:latest

# Push to registry
docker push your-registry.com/dozlab-base:latest
docker push your-registry.com/dozlab-k8s:k8s-1.30
docker push your-registry.com/dozlab-vm:latest
docker push your-registry.com/dozlab-init:latest

# Custom initrd uses Makefile for registry management
cd labs/custom-initrd
make push  # Pushes to registry configured in Makefile
```

## Troubleshooting

### Common Issues

#### Issue: Lab image fails to build - can't find base image

**Solution**: Build and tag the base image first, or update the `TAG` build argument to match your base image tag:

```bash
cd base_image
docker build -t dozman99/lab-base_image:test .
```

#### Issue: Init container fails to resize image

**Solution**: Check that the image path is writable and the filesystem is ext4. The container needs `e2fsprogs-extra` which is included in the Alpine image.

#### Issue: Firecracker VM won't boot

**Solution**:
- Verify the kernel image path is correct
- Check boot args include `init=/lib/systemd/systemd`
- Ensure rootfs ext4 image is not corrupted
- Verify machine-id files are cleared (done automatically in lab images)

#### Issue: SSH connection refused in VM

**Solution**:
- Verify SSH service is enabled: `systemctl status sshd`
- Check network configuration in Firecracker
- Verify firewall rules allow SSH traffic

#### Issue: Custom initrd build fails - cannot find init/main.go

**Solution**: The custom-initrd lab requires you to provide the Go source code for your custom init system:

```bash
cd labs/custom-initrd
mkdir -p init
# Create your init/main.go with your custom init implementation
# Example structure:
cat > init/main.go <<'EOF'
package main

import (
    "fmt"
    "os"
)

func main() {
    fmt.Println("Custom init starting...")
    // Your init logic here
}
EOF

# Then build
make build
```

## Development Workflow

### Creating a New Lab Type

1. Create new directory under `labs/`:
```bash
mkdir labs/my_new_lab
cd labs/my_new_lab
```

2. Create Dockerfile based on base image:
```dockerfile
ARG TAG=latest
FROM dozman99/lab-base_image:${TAG}

# Install your tools
RUN apt-get update && apt-get install -y \
    your-tools \
    your-packages

# Configure environment
RUN echo "" > /etc/machine-id && echo "" > /var/lib/dbus/machine-id
RUN mkdir -m 0700 -p /root/.ssh
RUN echo "root:root" | chpasswd
```

3. Create Makefile for build automation
4. Test the image
5. Convert to ext4 rootfs for Firecracker

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes (new lab types, improvements, bug fixes)
4. Test your changes thoroughly
5. Submit a pull request with a clear description

## License

See LICENSE file for details.