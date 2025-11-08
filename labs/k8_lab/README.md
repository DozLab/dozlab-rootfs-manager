# Kubernetes Lab Image

Complete Kubernetes lab environment built on the dozlab base image, featuring a full K8s toolchain with kubeadm, kubelet, kubectl, and containerd runtime.

## Overview

This lab image provides a production-ready Kubernetes environment suitable for:
- Kubernetes cluster setup and testing
- Container runtime experimentation
- K8s learning and training environments
- CI/CD Kubernetes testing
- Running in Firecracker MicroVMs

## Installed Components

### Kubernetes Stack (v1.30)
- `kubeadm` - Kubernetes cluster bootstrapping tool
- `kubelet` - Node agent that runs on each node
- `kubectl` - Kubernetes command-line tool
- **Version**: Kubernetes 1.30 (configurable via build arg)

### Container Runtime
- `containerd` v1.7.19 - Industry-standard container runtime
- CNI plugins included for networking
- CRI (Container Runtime Interface) configured

### Linux Kernel & System
- `linux-image-virtual` - Optimized kernel for virtualized environments
- `cloud-init` - Cloud instance initialization
- Kernel modules: `overlay`, `br_netfilter`

### Additional Tools
- `dnsutils` - DNS troubleshooting (dig, nslookup)
- `jq` - JSON processor for K8s API interactions
- `less` - Pager for viewing logs
- `apt-transport-https` - Secure package downloads
- `ca-certificates` - SSL certificate management
- `gnupg2` - GPG for package verification
- `software-properties-common` - PPA management
- `libseccomp2` - Seccomp support for containers

## Build Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `TAG` | `test` | Base image tag to use |
| `ARCH` | `amd64` | Target architecture (amd64, arm64) |
| `CONTAINERD_VERSION` | `1.7.19` | Containerd version to install |
| `KUBERNETES_VERSION` | `1.30` | Kubernetes major.minor version |

## Building

### Default Build

```bash
cd labs/k8_lab
docker build -t dozlab-k8s:latest .
```

### Custom Kubernetes Version

```bash
docker build \
  --build-arg KUBERNETES_VERSION=1.29 \
  -t dozlab-k8s:1.29 .
```

### Custom Base Image

```bash
docker build \
  --build-arg TAG=latest \
  -t dozlab-k8s:latest .
```

### Using Makefile

```bash
make build    # Build the image
make push     # Push to registry
```

## Configuration

### Network Configuration

The image includes pre-configured sysctl parameters for Kubernetes networking:

```
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.ipv6.conf.all.forwarding        = 1
net.ipv6.conf.all.disable_ipv6      = 0
net.ipv4.tcp_congestion_control     = bbr
vm.overcommit_memory                = 1
kernel.panic                        = 10
net.ipv4.conf.all.rp_filter         = 1
kernel.panic_on_oops                = 1
```

### Kernel Modules

Auto-loaded modules for container networking:
- `overlay` - OverlayFS for container layers
- `br_netfilter` - Bridge netfilter for iptables

### Containerd Configuration

- Config location: `/etc/containerd/config.toml`
- Socket: `unix:///run/containerd/containerd.sock`
- Enabled as systemd service
- CNI network configuration removed (managed by Kubernetes)

### Kubelet Configuration

- Runtime: containerd (via CRI)
- Extra args: `--container-runtime=remote --runtime-request-timeout=15m`
- Config: `/etc/systemd/system/kubelet.service.d/0-containerd.conf`
- Enabled as systemd service
- Packages held to prevent accidental upgrades

## Usage

### Verify Installation

```bash
# Check Kubernetes version
docker run --rm dozlab-k8s:latest kubeadm version

# Check kubectl
docker run --rm dozlab-k8s:latest kubectl version --client

# Check containerd
docker run --rm dozlab-k8s:latest containerd --version
```

### Initialize Kubernetes Cluster

```bash
# In a Firecracker VM or privileged container
kubeadm init --pod-network-cidr=10.244.0.0/16

# Configure kubectl
mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# Install CNI (e.g., Flannel)
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
```

### Join Worker Node

```bash
# Use the join command from kubeadm init output
kubeadm join <control-plane-host>:<port> --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

## Firecracker Integration

### Creating Rootfs for Firecracker

```bash
# Build the image
docker build -t dozlab-k8s:latest .

# Export to rootfs
docker create --name k8s-export dozlab-k8s:latest
docker export k8s-export -o k8s-rootfs.tar

# Create ext4 image (4GB for K8s)
dd if=/dev/zero of=k8s.ext4 bs=1M count=4096
mkfs.ext4 k8s.ext4

# Extract to image
mkdir -p /tmp/k8s-rootfs
sudo mount k8s.ext4 /tmp/k8s-rootfs
sudo tar -xf k8s-rootfs.tar -C /tmp/k8s-rootfs
sudo umount /tmp/k8s-rootfs

# Cleanup
docker rm k8s-export
```

### Firecracker Configuration

```json
{
  "boot-source": {
    "kernel_image_path": "/var/lib/firecracker/vmlinux",
    "boot_args": "console=ttyS0 reboot=k panic=1 pci=off init=/lib/systemd/systemd"
  },
  "drives": [{
    "drive_id": "rootfs",
    "path_on_host": "/path/to/k8s.ext4",
    "is_root_device": true,
    "is_read_only": false
  }],
  "machine-config": {
    "vcpu_count": 4,
    "mem_size_mib": 4096
  },
  "network-interfaces": [{
    "iface_id": "eth0",
    "guest_mac": "AA:FC:00:00:00:01",
    "host_dev_name": "tap0"
  }]
}
```

### Recommended Resources

For a single-node Kubernetes cluster:
- **CPU**: 4+ vCPUs
- **Memory**: 4GB+ RAM
- **Disk**: 4GB+ storage

For multi-node clusters, adjust accordingly per node.

## Testing

### Test Kubernetes Components

```bash
# Verify kubeadm
docker run --rm dozlab-k8s:latest kubeadm version -o short

# Test containerd
docker run --rm --privileged dozlab-k8s:latest \
  containerd --version

# Check kernel modules
docker run --rm --privileged dozlab-k8s:latest \
  lsmod | grep -E "overlay|br_netfilter"
```

### Test in Firecracker VM

1. Boot VM with k8s.ext4 rootfs
2. Login (root/root)
3. Initialize cluster:
   ```bash
   kubeadm init --pod-network-cidr=10.244.0.0/16
   ```
4. Verify cluster:
   ```bash
   export KUBECONFIG=/etc/kubernetes/admin.conf
   kubectl get nodes
   ```

## Common Workflows

### Single-Node Development Cluster

```bash
# Initialize with taint removal for single-node
kubeadm init --pod-network-cidr=10.244.0.0/16

# Allow workloads on control plane
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
kubectl taint nodes --all node-role.kubernetes.io/master-

# Install CNI
kubectl apply -f <cni-manifest>
```

### Multi-Node Cluster

```bash
# On control plane node
kubeadm init --pod-network-cidr=10.244.0.0/16 \
  --control-plane-endpoint=<control-plane-ip>

# On worker nodes (use join command from init output)
kubeadm join <control-plane-endpoint>:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

## Troubleshooting

### Issue: kubeadm init fails with "connection refused"

**Solution**: Ensure containerd is running:
```bash
systemctl status containerd
systemctl start containerd
```

### Issue: Pods stuck in "ContainerCreating"

**Solution**: Check CNI plugin installation:
```bash
ls /opt/cni/bin/
kubectl get pods -n kube-system
```

### Issue: Node shows "NotReady"

**Solution**: Install a CNI plugin (e.g., Flannel, Calico, Weave):
```bash
kubectl apply -f <cni-manifest-url>
```

### Issue: Container runtime not responding

**Solution**: Verify containerd socket:
```bash
ls -la /run/containerd/containerd.sock
systemctl restart containerd
```

## Upgrading Kubernetes

To upgrade to a newer Kubernetes version:

```bash
# Update build args
docker build \
  --build-arg KUBERNETES_VERSION=1.31 \
  -t dozlab-k8s:1.31 .

# Or modify Dockerfile and rebuild
```

Note: Packages are held with `apt-mark hold` to prevent accidental upgrades within running systems.

## Security Considerations

### Default Configuration
- Root password: `root` (change in production!)
- Machine ID: Cleared for unique VM instances
- SSH: Configured but verify security settings

### Hardening Recommendations
1. Change root password
2. Configure SSH key-based authentication
3. Enable firewall rules
4. Use RBAC policies in Kubernetes
5. Enable audit logging
6. Configure Pod Security Standards

## Related Components

- **Base Image** (`base_image/`) - Foundation for this image
- **Init Setup** (`init-setup/`) - Prepares rootfs for Firecracker
- **VM Lab** (`labs/vm_lab/`) - Simpler alternative for non-K8s workloads

## References

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [kubeadm Documentation](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [containerd Documentation](https://containerd.io/docs/)
- [Firecracker Documentation](https://github.com/firecracker-microvm/firecracker)

## Contributing

When modifying this lab:
1. Test K8s cluster initialization
2. Verify containerd integration
3. Check compatibility with common CNI plugins
4. Update version numbers in this README

## License

See LICENSE file in repository root.
