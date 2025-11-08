# Dozlab Rootfs Manager

Container and root filesystem management for lab environments, providing custom VM images and container runtime configurations.

## Features

- **Custom Lab Images**: Build specialized container images for different lab types
- **Root Filesystem Management**: Custom initrd and rootfs creation
- **Multi-Lab Support**: Different lab environments (K8s, VM, custom)
- **Firecracker Integration**: MicroVM support with custom kernels
- **Build Automation**: Automated image building and deployment

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Base Images   │────│  Lab Builders   │────│ Runtime Images  │
│                 │    │                 │    │                 │
│ • Ubuntu/Alpine │    │ • K8s Lab       │    │ • lab-k8s:latest│
│ • Custom Kernel │    │ • VM Lab        │    │ • lab-vm:latest │
│ • Init System   │    │ • Custom Labs   │    │ • lab-custom    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Lab Types

### Kubernetes Lab (`labs/k8_lab/`)
- Pre-configured Kubernetes environment
- kubectl, helm, and common tools
- Sample manifests and exercises

### VM Lab (`labs/vm_lab/`)
- General-purpose virtual machine environment
- Development tools and utilities
- Customizable for various programming languages

### Custom Initrd Lab (`labs/custom-initrd/`)
- Minimal custom Linux environment
- Custom init process written in Go
- Ultra-lightweight for specific use cases

## Getting Started

### Prerequisites

- Docker
- Make (optional, for build automation)
- Root access (for some operations)

### Building Lab Images

1. Clone the repository:
```bash
git clone <repository-url>
cd dozlab-rootfs-manager
```

2. Build base image:
```bash
cd base_image
make build
```

3. Build specific lab environments:
```bash
# Kubernetes lab
cd labs/k8_lab
make build

# VM lab
cd labs/vm_lab
make build

# Custom initrd lab
cd labs/custom-initrd
make build
```

### Quick Start with Make

```bash
# Build all lab images (from repository root)
make build-all

# Build specific lab
make build-k8s
make build-vm
make build-custom-initrd

# Push all images to registry
make push-all

# Clean up images
make clean
```

## Directory Structure

```
├── base_image/          # Base container image
│   ├── Dockerfile
│   └── setup-scripts/
├── init-setup/          # Initialization scripts
│   ├── Dockerfile
│   └── init-scripts/
├── labs/               # Lab-specific configurations
│   ├── k8_lab/         # Kubernetes lab environment
│   │   ├── Dockerfile
│   │   ├── manifests/
│   │   └── exercises/
│   ├── vm_lab/         # General VM lab
│   │   ├── Dockerfile
│   │   ├── tools/
│   │   └── configs/
│   └── custom-initrd/  # Custom init system
│       ├── Dockerfile
│       ├── init/       # Go init process
│       └── rootfs/
└── Makefile           # Build automation
```

## Lab Configurations

### Kubernetes Lab

**Features**:
- Kubernetes 1.30
- kubeadm, kubelet, kubectl
- Containerd 1.7.19 runtime
- Pre-configured for cluster deployment
- Cloud-init support

**Configuration**:
```dockerfile
ARG TAG=test
FROM dozman99/dozlab-base:${TAG}

ARG KUBERNETES_VERSION=1.30
ARG CONTAINERD_VERSION=1.7.19

RUN apt-get update && apt-get install -y \
    dnsutils \
    cloud-init \
    linux-image-virtual \
    kubeadm \
    kubelet \
    kubectl

# Containerd is installed and configured
# Kubelet is configured for containerd runtime
# System is ready for kubeadm init/join
```

### VM Lab

**Features**:
- Minimal VM environment
- Base Ubuntu system with systemd
- SSH server pre-installed
- Passwordless root access for labs
- Locale-aware SSH configuration

**Configuration**:
```dockerfile
ARG TAG=test
FROM dozman99/dozlab-base:${TAG}

# Machine ID cleared for VM cloning
# SSH configured to disable locale forwarding
# Passwordless root login enabled for lab access
```

### Custom Initrd Lab

**Features**:
- Minimal Alpine-based environment
- Ultra-lightweight container
- Can be exported as rootfs for VMs
- Multi-stage build for Go applications

**Configuration**:
```dockerfile
FROM golang:1.20-alpine AS build
WORKDIR /go/src/
COPY init .
RUN go build --tags netgo --ldflags '-s -w -extldflags "-lm -lstdc++ -static"' -o init main.go

FROM alpine:3.18
RUN apk add --no-cache curl ca-certificates htop
COPY --from=build /go/src/init /init
```

**Note**: The `init` directory and Go-based init system are placeholders for custom initialization logic. You can implement custom init processes by creating the `init/main.go` file.

## Firecracker Integration

Support for running labs in Firecracker MicroVMs:

### VM Configuration
```json
{
    "boot-source": {
        "kernel_image_path": "/var/lib/firecracker/kernel",
        "boot_args": "console=ttyS0 reboot=k panic=1 pci=off"
    },
    "drives": [{
        "drive_id": "rootfs",
        "path_on_host": "/var/lib/firecracker/rootfs.ext4",
        "is_root_device": true,
        "is_read_only": false
    }],
    "machine-config": {
        "vcpu_count": 2,
        "mem_size_mib": 1024
    }
}
```

### Usage
```bash
# Start Firecracker VM with custom rootfs
firecracker --api-sock /tmp/firecracker.socket --config-file vm-config.json
```

## Environment Variables

### Build-time Variables
```bash
# Base image configuration
BASE_IMAGE=ubuntu:22.04
DOZLAB_USER=dozlab
DOZLAB_UID=1000

# Lab-specific settings
LAB_TYPE=k8s
KUBERNETES_VERSION=1.28.0
DOCKER_VERSION=24.0.0

# Custom initrd settings
INIT_BINARY_PATH=/sbin/init
KERNEL_VERSION=6.1.0
```

### Runtime Variables
```bash
# Networking
VM_IP=192.168.1.100
GATEWAY=192.168.1.1
DNS_SERVER=8.8.8.8

# Services
SSH_ENABLED=true
DOCKER_ENABLED=true
K8S_ENABLED=false

# User settings
USER_HOME=/home/dozlab
SHELL=/bin/bash
```

## Image Tagging Strategy

```bash
# Git SHA tags (default)
dozman99/dozlab-base:<git-sha>
dozman99/dozlab-k8s:<git-sha>
dozman99/dozlab-vm:<git-sha>
dozman99/dozlab-custom-initrd:<git-sha>

# Version tags (manual)
dozman99/dozlab-k8s:v1.0.0
dozman99/dozlab-vm:v1.0.0

# Feature tags (examples)
dozman99/dozlab-k8s:k8s-1.30
dozman99/dozlab-vm:ubuntu-22.04
```

## Testing

### Image Testing
```bash
# Test Kubernetes lab
docker run --rm -it dozman99/dozlab-k8s:<tag> kubeadm version
docker run --rm -it dozman99/dozlab-k8s:<tag> kubectl version --client

# Test VM lab
docker run --rm -it dozman99/dozlab-vm:<tag> /bin/bash --version

# Test custom initrd
docker run --rm -it dozman99/dozlab-custom-initrd:<tag> /init
```

### Integration Testing
```bash
# Export rootfs for Firecracker
docker export $(docker create dozman99/dozlab-custom-initrd:<tag>) | tar -C /tmp/rootfs -xf -

# Test in Kubernetes
kubectl apply -f test-manifests/
```

## Security

### Base Image Security
- Regular security updates
- Non-root user by default
- Minimal package installation
- Security scanning integration

### Lab Environment Access
**⚠️ Important: Lab Security Configuration**

This is a lab/educational environment optimized for ease of use:
- **Passwordless root access** is enabled for console/VM access
- Root account has no password requirement (uses `passwd -d root`)
- PAM is configured to allow null passwords for convenience

**Security Recommendations:**
- These images are intended for isolated lab environments only
- Do NOT use in production or exposed environments
- For production use, implement proper authentication:
  - SSH key-based authentication
  - Strong password policies
  - Disable root login
  - Use non-privileged users

### Runtime Security
```bash
# Run as non-privileged user
USER dozlab

# Limit capabilities
RUN setcap cap_net_bind_service=+ep /usr/bin/program

# Read-only root filesystem
docker run --read-only -v /tmp:/tmp:rw dozman99/dozlab-vm:latest
```

## Monitoring

### Image Metrics
- Build time and size
- Vulnerability scan results
- Usage statistics
- Performance benchmarks

### Runtime Metrics
- Boot time
- Memory usage
- CPU utilization
- Network performance

## Contributing

1. Fork the repository
2. Create a new lab type in `labs/your-lab/`
3. Add Dockerfile and configuration
4. Update Makefile with build targets
5. Add documentation and tests
6. Submit a pull request

## Deployment

### Registry Push
```bash
# Push all images (uses make)
make push-all

# Or push individually
cd labs/k8_lab && make push
cd labs/vm_lab && make push
```

### Kubernetes Deployment
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: lab-environment
spec:
  containers:
  - name: lab-k8s
    image: dozman99/dozlab-k8s:latest
    resources:
      requests:
        memory: "512Mi"
        cpu: "500m"
      limits:
        memory: "2Gi"
        cpu: "2"
```

## License

[Add your license here]