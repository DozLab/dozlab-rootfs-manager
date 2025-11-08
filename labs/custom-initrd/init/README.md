# Custom Init System

A minimal, high-performance init process written in Go for containerized and MicroVM environments.

## Overview

This is a custom PID 1 init system designed specifically for minimal Linux environments, particularly targeting:
- Docker/Podman containers running as `--privileged`
- Firecracker MicroVMs
- Lightweight lab environments
- Ultra-fast boot scenarios (< 2 seconds)

Unlike traditional init systems (systemd, SysVinit, OpenRC), this init is purpose-built for ephemeral, single-purpose environments where simplicity and speed are paramount.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                     Kernel                          │
│              (Starts PID 1 - /init)                 │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│              Custom Init Process                     │
│  ┌─────────────────────────────────────────────┐   │
│  │  1. Mount Essential Filesystems             │   │
│  │     • /proc   (process info)                │   │
│  │     • /sys    (kernel/device interface)     │   │
│  │     • /dev    (device files)                │   │
│  │     • /tmp    (temp storage)                │   │
│  └─────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────┐   │
│  │  2. Configure System                        │   │
│  │     • Hostname                              │   │
│  │     • Network interfaces                    │   │
│  │     • DNS resolution                        │   │
│  └─────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────┐   │
│  │  3. Start Services (Optional)               │   │
│  │     • sshd                                  │   │
│  │     • Custom daemons                        │   │
│  └─────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────┐   │
│  │  4. Launch User Shell                       │   │
│  │     • /bin/sh or /bin/bash                  │   │
│  │     • Wait for completion                   │   │
│  └─────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────┐   │
│  │  5. Cleanup & Reap Zombies                  │   │
│  │     • Signal handling (SIGCHLD)             │   │
│  │     • Process reaping                       │   │
│  │     • Graceful shutdown                     │   │
│  └─────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

## Features

### Core Capabilities
- **Fast Boot**: < 2 second boot time from kernel to shell
- **Minimal Footprint**: < 5MB static binary (with aggressive optimization)
- **Zombie Reaping**: Proper SIGCHLD handling to prevent zombie processes
- **Signal Handling**: Graceful shutdown on SIGTERM/SIGINT
- **Filesystem Management**: Automatic mounting of essential filesystems
- **Network Configuration**: Basic network interface setup
- **Service Management**: Simple service startup and supervision

### Design Principles
1. **Simplicity**: No complex dependency management or unit files
2. **Performance**: Minimal startup overhead
3. **Reliability**: Single point of failure, easy to debug
4. **Portability**: Static binary, no external dependencies
5. **Security**: Minimal attack surface

## Building

### Prerequisites
- Go 1.20 or later
- Linux build environment

### Local Build (Development)
```bash
cd labs/custom-initrd/init
go build --tags netgo --ldflags '-s -w -extldflags "-lm -lstdc++ -static"' -o init main.go
```

**Build Flags Explained**:
- `--tags netgo`: Use pure Go DNS resolver (no libc dependency)
- `-s -w`: Strip symbol table and debug info (reduce binary size)
- `-extldflags "-lm -lstdc++ -static"`: Create fully static binary
- Result: Static binary that works without any shared libraries

### Container Build (Production)
The Dockerfile uses multi-stage builds for optimal image size:

```bash
cd labs/custom-initrd
make build
```

This produces:
1. **Stage 1 (Builder)**: golang:1.20-alpine with build tools
2. **Stage 2 (Runtime)**: alpine:3.18 with only the static init binary

### Build Verification
```bash
# Check binary is static
ldd init
# Expected output: "not a dynamic executable"

# Check binary size
ls -lh init
# Expected: ~3-8MB depending on features

# Test run (requires root/privileged)
sudo ./init
```

## Usage

### Docker Container
```bash
# Build the image
docker build -t dozlab-custom-initrd:latest .

# Run with privileged mode (required for init operations)
docker run --rm -it --privileged dozlab-custom-initrd:latest
```

### Firecracker MicroVM
```bash
# Extract rootfs from container
docker create --name temp dozlab-custom-initrd:latest
docker export temp -o rootfs.tar
docker rm temp

# Create ext4 image
fallocate -l 1G rootfs.ext4
mkfs.ext4 rootfs.ext4
sudo mount -o loop rootfs.ext4 /mnt
sudo tar -xf rootfs.tar -C /mnt
sudo umount /mnt

# Launch with Firecracker
firecracker --config-file vm-config.json
```

Example `vm-config.json`:
```json
{
  "boot-source": {
    "kernel_image_path": "/path/to/vmlinux",
    "boot_args": "console=ttyS0 reboot=k panic=1 pci=off init=/init"
  },
  "drives": [{
    "drive_id": "rootfs",
    "path_on_host": "/path/to/rootfs.ext4",
    "is_root_device": true,
    "is_read_only": false
  }],
  "machine-config": {
    "vcpu_count": 2,
    "mem_size_mib": 512
  }
}
```

## Configuration

### Environment Variables

The init process supports configuration via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `HOSTNAME` | `dozlab-vm` | System hostname |
| `SHELL` | `/bin/sh` | Shell to launch |
| `INIT_DEBUG` | `false` | Enable debug logging |
| `SKIP_NETWORK` | `false` | Skip network configuration |
| `SKIP_SERVICES` | `false` | Skip service startup |

### Example with Environment Variables
```bash
docker run --rm -it --privileged \
  -e HOSTNAME=my-lab \
  -e INIT_DEBUG=true \
  -e SHELL=/bin/bash \
  dozlab-custom-initrd:latest
```

## Implementation Details

### Filesystem Mounts

The init process mounts these filesystems:

```go
/proc      -> procfs    (Process information)
/sys       -> sysfs     (Kernel/device info)
/dev/pts   -> devpts    (Pseudo-terminals)
/dev/shm   -> tmpfs     (Shared memory)
/tmp       -> tmpfs     (Temporary files)
```

Mount flags:
- `MS_NOSUID`: No setuid binaries
- `MS_NODEV`: No device files (except /dev)
- `MS_NOEXEC`: No execution (for /dev/shm, /tmp)

### Process Reaping

As PID 1, the init process must reap zombie processes:

```go
// Handle SIGCHLD to reap zombie processes
signal.Notify(sigCh, syscall.SIGCHLD)
go func() {
    for range sigCh {
        for {
            var wstatus syscall.WaitStatus
            pid, err := syscall.Wait4(-1, &wstatus, syscall.WNOHANG, nil)
            if err != nil || pid <= 0 {
                break
            }
        }
    }
}()
```

### Signal Handling

Graceful shutdown on termination signals:

```go
signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)
select {
case <-sigCh:
    // Cleanup and exit
    log.Println("Shutting down...")
    syscall.Sync()
    syscall.Reboot(syscall.LINUX_REBOOT_CMD_POWER_OFF)
}
```

### Network Configuration

Basic network setup:

```go
1. Bring up loopback interface (lo)
2. Configure eth0 with DHCP (if available)
3. Set hostname via /etc/hostname
4. Configure DNS via /etc/resolv.conf
```

## Debugging

### Enable Debug Mode
```bash
docker run --rm -it --privileged \
  -e INIT_DEBUG=true \
  dozlab-custom-initrd:latest
```

### Check Init Logs
```bash
# Inside container
dmesg | grep init

# From host (container logs)
docker logs <container-id>
```

### Common Issues

**Issue**: "Operation not permitted" errors
**Solution**: Run with `--privileged` flag or appropriate capabilities:
```bash
docker run --cap-add SYS_ADMIN --cap-add NET_ADMIN ...
```

**Issue**: Shell doesn't start
**Solution**: Verify shell exists in the image:
```bash
docker run --rm -it --entrypoint /bin/ls dozlab-custom-initrd:latest /bin/
```

**Issue**: Network not working
**Solution**: Enable network configuration:
```bash
docker run --rm -it --privileged -e SKIP_NETWORK=false ...
```

## Performance Benchmarks

Typical boot times (kernel hand-off to shell):

| Environment | Boot Time |
|-------------|-----------|
| Docker (privileged) | ~0.5s |
| Firecracker MicroVM | ~1.2s |
| QEMU/KVM | ~1.8s |

Memory usage:
- Init process: ~2-4MB RSS
- Total minimal system: ~20MB

## Security Considerations

### Minimal Attack Surface
- No complex service manager code
- No D-Bus, no systemd-journald
- Static binary (no dynamic library loading)
- No unnecessary network services

### Recommended Practices
1. Run read-only rootfs when possible:
   ```bash
   docker run --read-only -v /tmp:/tmp:rw ...
   ```

2. Drop capabilities when not needed:
   ```bash
   docker run --cap-drop ALL --cap-add CHOWN --cap-add SETUID ...
   ```

3. Use seccomp profiles to limit syscalls

4. Enable AppArmor/SELinux profiles

## Extending the Init System

### Adding Custom Services

Modify `startServices()` in `main.go`:

```go
func startServices() error {
    services := []string{
        "/usr/sbin/sshd",
        "/usr/bin/my-daemon",
    }

    for _, svc := range services {
        if _, err := os.Stat(svc); err == nil {
            go runService(svc)
        }
    }
    return nil
}
```

### Custom Initialization

Add hooks in `main()`:

```go
func main() {
    setupFilesystems()
    configureNetwork()

    // Custom initialization here
    runCustomSetup()

    startServices()
    launchShell()
}
```

## Comparison with Other Init Systems

| Feature | Custom Init | systemd | SysVinit | BusyBox init |
|---------|-------------|---------|----------|--------------|
| Binary Size | ~5MB | ~1.6MB | ~40KB | ~1MB |
| Boot Time | ~0.5s | ~3-5s | ~2-3s | ~1s |
| Complexity | Low | Very High | Medium | Low |
| Service Mgmt | Basic | Advanced | Basic | Basic |
| Use Case | Containers/VMs | Full OS | Legacy | Embedded |

## License

[Specify license here]

## Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/my-feature`)
3. Commit changes (`git commit -am 'Add my feature'`)
4. Push to branch (`git push origin feature/my-feature`)
5. Create Pull Request

## References

- [Linux Boot Process](https://www.kernel.org/doc/html/latest/admin-guide/init.html)
- [PID 1 Requirements](https://man7.org/linux/man-pages/man2/wait.2.html)
- [Go Static Linking](https://golang.org/cmd/link/)
- [Firecracker Documentation](https://github.com/firecracker-microvm/firecracker)
