# VM Lab Image

Minimal general-purpose VM environment built on the dozlab base image, designed for lightweight workloads and basic virtual machine use cases.

## Overview

This lab image provides a clean, minimal Ubuntu environment suitable for:
- General-purpose virtual machine instances
- Development and testing environments
- Lightweight application hosting
- Learning and experimentation
- Base for custom application VMs
- Running in Firecracker MicroVMs

Unlike the K8s lab, this image keeps the base system minimal without heavy components like container runtimes or orchestration tools.

## Features

- **Minimal footprint**: Only essential packages from base image
- **Clean state**: Machine IDs cleared for unique VM instances
- **SSH ready**: Configured for remote access
- **Locale optimized**: Warnings suppressed for cleaner experience
- **Firecracker ready**: Optimized for MicroVM deployment

## What's Included

This image inherits all packages from the base image:
- systemd (init system)
- openssh-server (SSH access)
- Network utilities (curl, wget, iproute2, iputils-ping, net-tools)
- Text editor (vim-tiny)
- Basic system tools (sudo, procps)

## Build Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `TAG` | `test` | Base image tag to use |

## Building

### Default Build

```bash
cd labs/vm_lab
docker build -t dozlab-vm:latest .
```

### Custom Base Image Tag

```bash
docker build --build-arg TAG=latest -t dozlab-vm:latest .
```

### Using Makefile

```bash
make build    # Build the image
make push     # Push to registry
```

## Configuration

### Machine ID Management

The image clears machine IDs to ensure each VM instance gets unique identifiers:

```dockerfile
RUN echo "" > /etc/machine-id && echo "" > /var/lib/dbus/machine-id
```

This is crucial for:
- DHCP client identification
- systemd journal uniqueness
- System logging
- Network configuration

### SSH Configuration

SSH is pre-configured with locale forwarding disabled to avoid warnings:

```
# Disabled: AcceptEnv LANG LC_*
```

This prevents locale-related warnings when the container doesn't have locale packages installed.

### Root Access

- **Console access**: root password set to `root`
- **SSH directory**: `/root/.ssh` created with proper permissions (0700)

**Security Note**: Change the root password in production environments!

## Usage

### Running Locally (Docker)

```bash
# Interactive shell
docker run --rm -it dozlab-vm:latest /bin/bash

# Background service
docker run -d --name my-vm dozlab-vm:latest

# With SSH access
docker run -d -p 2222:22 --name my-vm dozlab-vm:latest
ssh root@localhost -p 2222  # password: root
```

### Firecracker Integration

#### Creating Rootfs for Firecracker

```bash
# Build the image
docker build -t dozlab-vm:latest .

# Export to rootfs
docker create --name vm-export dozlab-vm:latest
docker export vm-export -o vm-rootfs.tar

# Create ext4 image (2GB for minimal VM)
dd if=/dev/zero of=vm.ext4 bs=1M count=2048
mkfs.ext4 vm.ext4

# Extract to image
mkdir -p /tmp/vm-rootfs
sudo mount vm.ext4 /tmp/vm-rootfs
sudo tar -xf vm-rootfs.tar -C /tmp/vm-rootfs
sudo umount /tmp/vm-rootfs

# Cleanup
docker rm vm-export
rm vm-rootfs.tar
```

#### Firecracker Configuration

```json
{
  "boot-source": {
    "kernel_image_path": "/var/lib/firecracker/vmlinux",
    "boot_args": "console=ttyS0 reboot=k panic=1 pci=off init=/lib/systemd/systemd"
  },
  "drives": [{
    "drive_id": "rootfs",
    "path_on_host": "/path/to/vm.ext4",
    "is_root_device": true,
    "is_read_only": false
  }],
  "machine-config": {
    "vcpu_count": 2,
    "mem_size_mib": 1024
  },
  "network-interfaces": [{
    "iface_id": "eth0",
    "guest_mac": "AA:FC:00:00:00:01",
    "host_dev_name": "tap0"
  }]
}
```

#### Recommended Resources

For general-purpose workloads:
- **CPU**: 1-2 vCPUs
- **Memory**: 512MB-1GB RAM
- **Disk**: 1-2GB storage

Adjust based on your application requirements.

## Customization

### Adding Application Dependencies

Create a derived image:

```dockerfile
FROM dozlab-vm:latest

# Install your application dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    nodejs \
    npm \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy your application
COPY app/ /opt/app/

# Configure startup
RUN systemctl enable your-service
```

### Adding Development Tools

```dockerfile
FROM dozlab-vm:latest

# Install development tools
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    vim \
    htop \
    strace \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
```

### Configuring Services

```dockerfile
FROM dozlab-vm:latest

# Enable SSH on boot
RUN systemctl enable ssh

# Add custom systemd service
COPY my-service.service /etc/systemd/system/
RUN systemctl enable my-service
```

## Testing

### Basic Functionality Tests

```bash
# Test the image
docker run --rm dozlab-vm:latest cat /etc/os-release

# Verify machine ID is cleared
docker run --rm dozlab-vm:latest cat /etc/machine-id

# Check SSH configuration
docker run --rm dozlab-vm:latest grep AcceptEnv /etc/ssh/sshd_config
```

### SSH Access Test

```bash
# Start VM with SSH
docker run -d -p 2222:22 --name test-vm \
  --privileged dozlab-vm:latest /lib/systemd/systemd

# Wait for boot
sleep 5

# Test SSH connection
ssh -o StrictHostKeyChecking=no root@localhost -p 2222

# Cleanup
docker stop test-vm && docker rm test-vm
```

### Firecracker VM Test

```bash
# After creating vm.ext4 rootfs
firecracker --api-sock /tmp/firecracker.sock --config-file vm-config.json

# In Firecracker console, press Enter
# Login: root / root

# Verify system
uname -a
ip addr show
systemctl status
```

## Use Cases

### 1. Application Host

Deploy your application in a lightweight VM:
- Web servers (nginx, Apache)
- API services
- Background workers
- Microservices

### 2. Development Environment

Use as a development sandbox:
- Safe testing environment
- Isolated from host system
- Easy to rebuild and reset

### 3. CI/CD Test Environment

Run tests in clean VMs:
- Consistent test environment
- Fast boot times with Firecracker
- Easy parallelization

### 4. Learning Platform

Educational use:
- Linux system administration
- Networking experiments
- Security testing (in isolated environments)

## Common Workflows

### Deploy a Web Application

```dockerfile
FROM dozlab-vm:latest

# Install web server
RUN apt-get update && apt-get install -y nginx \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy website files
COPY website/ /var/www/html/

# Enable nginx
RUN systemctl enable nginx

# Expose port
EXPOSE 80
```

### Create Development Environment

```bash
# Build custom dev image
cat > Dockerfile.dev <<'EOF'
FROM dozlab-vm:latest

RUN apt-get update && apt-get install -y \
    build-essential \
    python3-dev \
    python3-pip \
    git \
    vim \
    && apt-get clean

RUN pip3 install --no-cache-dir \
    flask \
    requests \
    pytest

WORKDIR /workspace
EOF

docker build -f Dockerfile.dev -t my-dev-env .
```

## Troubleshooting

### Issue: Machine ID not unique across VMs

**Solution**: The image clears machine IDs by default. If you see duplicate IDs, verify:
```bash
cat /etc/machine-id  # Should be empty or regenerated on boot
```

### Issue: Locale warnings in SSH sessions

**Solution**: Already configured! The image disables locale forwarding. If you need locales:
```dockerfile
FROM dozlab-vm:latest
RUN apt-get update && apt-get install -y locales
RUN locale-gen en_US.UTF-8
```

### Issue: systemd services not starting

**Solution**: Ensure you run with proper privileges:
```bash
docker run --privileged dozlab-vm:latest /lib/systemd/systemd
```

### Issue: Network not configured in Firecracker

**Solution**: Configure networking in Firecracker config and set up interfaces in the VM:
```bash
ip addr add 172.16.0.2/24 dev eth0
ip link set eth0 up
ip route add default via 172.16.0.1
```

## Comparison with Other Labs

| Feature | VM Lab | K8s Lab | Custom Initrd |
|---------|--------|---------|---------------|
| **Size** | Small | Large | Minimal |
| **Purpose** | General use | Kubernetes | Specialized |
| **Boot Time** | Fast | Moderate | Very Fast |
| **Memory** | 512MB+ | 4GB+ | 256MB+ |
| **Complexity** | Simple | Complex | Simple |

## Performance Considerations

### Memory Usage

Minimal configuration can run on:
- **Idle**: ~100-150MB RAM
- **With services**: 200-500MB RAM
- **Under load**: Varies by application

### Boot Time

- **In Docker**: ~2-3 seconds
- **In Firecracker**: ~1-2 seconds
- **systemd init**: ~500ms-1s

### Disk Usage

- **Container size**: ~150-200MB
- **Rootfs ext4**: 1-2GB (allocated)
- **Actual usage**: ~500MB-1GB

## Security Best Practices

1. **Change default password**:
   ```bash
   passwd root
   ```

2. **Configure SSH keys**:
   ```bash
   mkdir -p /root/.ssh
   echo "your-public-key" > /root/.ssh/authorized_keys
   chmod 600 /root/.ssh/authorized_keys
   ```

3. **Disable password authentication**:
   ```bash
   sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
   ```

4. **Enable firewall**:
   ```bash
   apt-get install -y ufw
   ufw allow ssh
   ufw enable
   ```

## Related Components

- **Base Image** (`base_image/`) - Foundation for this image
- **K8s Lab** (`labs/k8_lab/`) - Full Kubernetes environment
- **Init Setup** (`init-setup/`) - Prepares rootfs for Firecracker
- **Custom Initrd** (`labs/custom-initrd/`) - Minimal Go-based init

## Contributing

When modifying this lab:
1. Keep it minimal - add components to derived images instead
2. Test both Docker and Firecracker deployments
3. Verify machine ID clearing functionality
4. Document any new default configurations

## License

See LICENSE file in repository root.
