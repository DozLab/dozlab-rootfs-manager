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
docker build -t dozlab-base:latest .
```

3. Build specific lab environments:
```bash
# Kubernetes lab
cd labs/k8_lab
docker build -t dozlab-k8s-lab:latest .

# VM lab
cd labs/vm_lab
docker build -t dozlab-vm-lab:latest .

# Custom initrd lab
cd labs/custom-initrd
docker build -t dozlab-custom-initrd:latest .
```

### Quick Start with Make

```bash
# Build all lab images
make build-all

# Build specific lab
make build-k8s
make build-vm
make build-custom

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
- Kubernetes 1.28+
- kubectl, helm, k9s
- Docker-in-Docker support
- Sample deployments and services

**Configuration**:
```dockerfile
FROM dozlab-base:latest

RUN apt-get update && apt-get install -y \
    kubectl \
    helm \
    k9s \
    docker.io

COPY manifests/ /etc/kubernetes/manifests/
COPY exercises/ /home/dozlab/exercises/

EXPOSE 6443 8080
```

### VM Lab

**Features**:
- Multi-language development environment
- Git, vim, curl, and common tools
- SSH server for remote access
- Customizable via environment variables

**Configuration**:
```dockerfile
FROM dozlab-base:latest

RUN apt-get update && apt-get install -y \
    build-essential \
    python3 \
    nodejs \
    git \
    vim \
    openssh-server

USER dozlab
WORKDIR /home/dozlab

EXPOSE 22 3000 8000
```

### Custom Initrd Lab

**Features**:
- Minimal Linux environment
- Custom Go-based init system
- Ultra-lightweight (< 50MB)
- Firecracker MicroVM ready

**Init Process** (`labs/custom-initrd/init/main.go`):
```go
func main() {
    // Mount filesystems
    mountFilesystems()
    
    // Start essential services
    startServices()
    
    // Setup networking
    configureNetwork()
    
    // Start user shell
    startShell()
}
```

## Custom Init System

The custom initrd lab includes a Go-based init system:

### Features
- Fast boot time (< 2 seconds)
- Minimal resource usage
- Custom service management
- Network configuration
- User environment setup

### Building
```bash
cd labs/custom-initrd/init
go build -o init main.go
```

### Integration
The init binary is embedded in the container and serves as PID 1:
```dockerfile
COPY init/init /sbin/init
ENTRYPOINT ["/sbin/init"]
```

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
# Version tags
dozlab-k8s-lab:v1.0.0
dozlab-vm-lab:v1.0.0
dozlab-custom-initrd:v1.0.0

# Latest tags
dozlab-k8s-lab:latest
dozlab-vm-lab:latest
dozlab-custom-initrd:latest

# Feature tags
dozlab-k8s-lab:k8s-1.28
dozlab-vm-lab:ubuntu-22.04
dozlab-custom-initrd:go-1.21
```

## Testing

### Image Testing
```bash
# Test image functionality
docker run --rm -it dozlab-k8s-lab:latest kubectl version
docker run --rm -it dozlab-vm-lab:latest python3 --version

# Test custom init
docker run --rm --privileged dozlab-custom-initrd:latest
```

### Integration Testing
```bash
# Test with Firecracker
./test-firecracker.sh dozlab-custom-initrd:latest

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
docker run --read-only -v /tmp:/tmp:rw dozlab-lab:latest
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
# Tag for registry
docker tag dozlab-k8s-lab:latest your-registry.com/dozlab-k8s-lab:v1.0.0

# Push to registry
docker push your-registry.com/dozlab-k8s-lab:v1.0.0
```

### Kubernetes Deployment
```yaml
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: lab-environment
    image: your-registry.com/dozlab-k8s-lab:v1.0.0
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