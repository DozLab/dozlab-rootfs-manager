# Base Image

Ubuntu 22.04-based foundational image that serves as the base for all lab environments in the Dozlab rootfs manager.

## Overview

This base image provides a complete Linux environment with systemd init system, networking utilities, and SSH access. It's designed to run in Firecracker MicroVMs and serves as the foundation for specialized lab images (K8s, VM, etc.).

## Installed Packages

### System & Init
- `systemd` - System and service manager (runs as PID 1)
- `udev` - Device management
- `kmod` - Kernel module loading
- `dbus` - Inter-process communication

### Networking
- `iproute2` - Advanced network configuration
- `iputils-ping` - Network diagnostic tool
- `net-tools` - Legacy networking tools
- `openssh-server` - SSH server for remote access

### Utilities
- `curl` - HTTP client
- `wget` - File downloader
- `vim-tiny` - Lightweight text editor
- `procps` - Process monitoring utilities
- `sudo` - Privilege escalation

### Security & Random Number Generation
- `haveged` - Entropy daemon
- `rng-tools` - Random number generator tools

## Build Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `OS_VERSION` | `22.04` | Ubuntu base version |

## Building

### Basic Build

```bash
cd base_image
docker build -t dozlab-base:latest .
```

### Custom Ubuntu Version

```bash
docker build --build-arg OS_VERSION=20.04 -t dozlab-base:20.04 .
```

### Build with Registry Push

```bash
REGISTRY=your-registry.com
docker build -t ${REGISTRY}/dozlab-base:latest .
docker push ${REGISTRY}/dozlab-base:latest
```

## Testing

### Test Basic Functionality

```bash
# Run with systemd
docker run --rm -it --privileged dozlab-base:latest /lib/systemd/systemd
```

### Test SSH Access

```bash
# Start container with SSH
docker run -d -p 2222:22 --name test-base dozlab-base:latest

# Connect (password: root)
ssh root@localhost -p 2222

# Cleanup
docker stop test-base && docker rm test-base
```

### Verify Installed Packages

```bash
docker run --rm dozlab-base:latest dpkg -l | grep systemd
docker run --rm dozlab-base:latest which curl
docker run --rm dozlab-base:latest ip addr
```

## Usage in Lab Images

Lab images use this base image as their foundation:

```dockerfile
ARG TAG=latest
FROM dozman99/lab-base_image:${TAG}

# Add your lab-specific packages and configuration
RUN apt-get update && apt-get install -y \
    your-packages

# Lab-specific setup
RUN your-setup-commands
```

## Firecracker Integration

This base image is designed for Firecracker MicroVMs:

### Key Features for Firecracker
- **systemd init**: Proper init system for managing services
- **Networking**: Complete network stack for VM connectivity
- **SSH**: Remote access to VM instances
- **Device management**: udev for proper device handling

### Converting to Rootfs

```bash
# Create container
docker create --name base-export dozlab-base:latest

# Export to tar
docker export base-export > base-rootfs.tar

# Create ext4 image
dd if=/dev/zero of=base.ext4 bs=1M count=2048
mkfs.ext4 base.ext4

# Mount and extract
mkdir -p /tmp/rootfs
sudo mount base.ext4 /tmp/rootfs
sudo tar -xf base-rootfs.tar -C /tmp/rootfs
sudo umount /tmp/rootfs

# Cleanup
docker rm base-export
rm base-rootfs.tar
```

## Configuration

### Default Settings
- Root password: Not set by default (configure in derived images)
- SSH: openssh-server installed but must be enabled
- systemd: Configured as default init system

### Customization

Create a derived image:

```dockerfile
FROM dozlab-base:latest

# Set root password
RUN echo "root:yourpassword" | chpasswd

# Enable SSH
RUN systemctl enable ssh

# Add custom configuration
COPY your-config /etc/your-config
```

## Size Optimization

The base image prioritizes functionality over size, but you can optimize:

```dockerfile
FROM dozlab-base:latest

# Remove unnecessary packages after installation
RUN apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
```

## Troubleshooting

### Issue: systemd fails to start

**Solution**: Ensure you run with `--privileged` flag or proper capabilities:
```bash
docker run --privileged dozlab-base:latest /lib/systemd/systemd
```

### Issue: SSH connection refused

**Solution**: SSH service must be enabled in derived images:
```dockerfile
RUN systemctl enable ssh
RUN echo "root:root" | chpasswd
```

### Issue: Network not working

**Solution**: Verify network tools are available:
```bash
docker run --rm dozlab-base:latest ip link show
```

## Related Components

- **K8s Lab** (`labs/k8_lab/`) - Kubernetes environment built on this base
- **VM Lab** (`labs/vm_lab/`) - General-purpose VM built on this base
- **Init Setup** (`init-setup/`) - Prepares rootfs images for Firecracker

## Contributing

When modifying the base image:
1. Keep changes minimal and broadly applicable
2. Test with all dependent lab images
3. Document new packages in this README
4. Update version tags appropriately

## License

See LICENSE file in repository root.
