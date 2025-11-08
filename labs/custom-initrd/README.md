# Custom Initrd Lab

Ultra-lightweight Alpine-based image with a custom Go init system for specialized use cases requiring minimal overhead.

## Overview

This lab provides a minimal runtime environment with a custom init process written in Go. It's designed for scenarios where you need:
- Complete control over the init process
- Minimal resource footprint
- Fast boot times
- Custom initialization logic
- MicroVM optimization

Unlike traditional init systems (systemd, OpenRC), this allows you to implement exactly the initialization logic your application needs.

## Features

- **Custom Go Init**: Write your own PID 1 process in Go
- **Static Binary**: Fully static compilation for portability
- **Multi-stage Build**: Optimized Docker build process
- **Minimal Base**: Alpine 3.18 with only essential utilities
- **Fast Boot**: Minimal overhead for rapid startup
- **Flexible**: Adapt init logic to your specific needs

## Architecture

```
┌─────────────────────────────────────────────────────┐
│ Build Stage (golang:1.20-alpine)                    │
│                                                      │
│  init/main.go  ──[static build]──> /go/src/init    │
│                                                      │
│  Build flags:                                       │
│  - netgo tag (static networking)                   │
│  - Static linking (-extldflags "-static")          │
│  - Strip symbols (-s -w)                           │
└─────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│ Runtime Stage (alpine:3.18)                         │
│                                                      │
│  /init           ── Custom Go init binary (PID 1)   │
│  /usr/bin/curl   ── HTTP client                     │
│  /usr/bin/htop   ── Process monitor                 │
│  + ca-certificates                                  │
└─────────────────────────────────────────────────────┘
```

## Directory Structure

```
labs/custom-initrd/
├── Dockerfile          # Multi-stage build definition
├── Makefile           # Build automation
├── .dockerignore      # Files to exclude from build context
├── .gitignore         # Git ignore rules (includes init/)
├── README.md          # This file
└── init/              # Your Go init source (not tracked in git)
    ├── main.go        # Main init implementation
    ├── go.mod         # Go module definition (optional)
    └── go.sum         # Go dependencies (optional)
```

## Build Arguments

None required - the build is self-contained.

## Build Configuration

### Go Build Flags

```bash
go build \
  --tags netgo \
  --ldflags '-s -w -extldflags "-lm -lstdc++ -static"' \
  -o init main.go
```

| Flag | Purpose |
|------|---------|
| `--tags netgo` | Use pure Go networking (no cgo) |
| `-s` | Strip symbol table |
| `-w` | Strip DWARF debugging info |
| `-extldflags "-static"` | Force static linking |
| `-extldflags "-lm -lstdc++"` | Link math and C++ libs statically |

### Installed Packages (Runtime)

- `curl` - HTTP client for health checks or downloads
- `ca-certificates` - SSL certificate validation
- `htop` - Interactive process viewer

## Getting Started

### 1. Create Your Init Implementation

First, create the `init/` directory and your Go init program:

```bash
cd labs/custom-initrd
mkdir -p init
cd init
```

Create `main.go` with your custom init logic:

```go
package main

import (
    "fmt"
    "log"
    "os"
    "os/exec"
    "os/signal"
    "syscall"
)

func main() {
    // PID 1 responsibilities
    log.Println("Custom init starting (PID 1)")

    // 1. Mount essential filesystems
    mountFilesystems()

    // 2. Setup networking
    setupNetwork()

    // 3. Start your application
    startApplication()

    // 4. Reap zombie processes
    reapZombies()
}

func mountFilesystems() {
    mounts := []struct {
        source, target, fstype string
        flags                  uintptr
    }{
        {"proc", "/proc", "proc", 0},
        {"sysfs", "/sys", "sysfs", 0},
        {"tmpfs", "/tmp", "tmpfs", 0},
        {"devtmpfs", "/dev", "devtmpfs", 0},
    }

    for _, m := range mounts {
        if err := syscall.Mount(m.source, m.target, m.fstype, m.flags, ""); err != nil {
            log.Printf("Failed to mount %s: %v", m.target, err)
        }
    }
}

func setupNetwork() {
    // Configure network interfaces
    // Example: ip link set lo up
    cmd := exec.Command("ip", "link", "set", "lo", "up")
    if err := cmd.Run(); err != nil {
        log.Printf("Failed to setup network: %v", err)
    }
}

func startApplication() {
    // Start your main application
    log.Println("Starting application...")

    // Example: start a shell
    cmd := exec.Command("/bin/sh")
    cmd.Stdin = os.Stdin
    cmd.Stdout = os.Stdout
    cmd.Stderr = os.Stderr

    if err := cmd.Start(); err != nil {
        log.Fatalf("Failed to start shell: %v", err)
    }
}

func reapZombies() {
    // Handle SIGCHLD to reap zombie processes
    sigChan := make(chan os.Signal, 1)
    signal.Notify(sigChan, syscall.SIGCHLD)

    for {
        <-sigChan
        // Reap all available children
        for {
            var status syscall.WaitStatus
            pid, err := syscall.Wait4(-1, &status, syscall.WNOHANG, nil)
            if err != nil || pid <= 0 {
                break
            }
            log.Printf("Reaped child process: PID %d", pid)
        }
    }
}
```

### 2. Build the Image

Using Make (recommended):

```bash
cd labs/custom-initrd
make build
```

Or using Docker directly:

```bash
docker build -t dozman99/lab-custom-initrd-os:latest .
```

### 3. Test Locally

```bash
# Run the container
docker run --rm -it --privileged \
  dozman99/lab-custom-initrd-os:$(git rev-parse --short HEAD)
```

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make build` | Build Docker image with multi-stage build |
| `make push` | Push image to registry |
| `make init-local` | Build init binary locally (for testing) |

## Build Variables

Configure in Makefile or override on command line:

| Variable | Default | Description |
|----------|---------|-------------|
| `REGISTRY` | `docker.io/dozman99` | Container registry |
| `IMAGE_NAME` | `$(REGISTRY)/lab-custom-initrd-os` | Full image name |
| `TAG` | `$(git rev-parse --short HEAD)` | Image tag |

Example:

```bash
make build REGISTRY=myregistry.com TAG=v1.0.0
```

## Init Implementation Examples

### Example 1: Minimal Init

```go
package main

import (
    "log"
    "os"
    "os/signal"
    "syscall"
)

func main() {
    log.Println("Minimal init starting")

    // Wait for signals
    sig := make(chan os.Signal, 1)
    signal.Notify(sig, syscall.SIGTERM, syscall.SIGINT)

    <-sig
    log.Println("Shutting down")
}
```

### Example 2: Service Manager

```go
package main

import (
    "log"
    "os/exec"
    "sync"
)

type Service struct {
    Name    string
    Command string
    Args    []string
}

func main() {
    services := []Service{
        {"app", "/usr/bin/myapp", []string{}},
        {"logger", "/usr/bin/logger", []string{"-f"}},
    }

    var wg sync.WaitGroup
    for _, svc := range services {
        wg.Add(1)
        go func(s Service) {
            defer wg.Done()
            runService(s)
        }(svc)
    }

    wg.Wait()
}

func runService(svc Service) {
    log.Printf("Starting service: %s", svc.Name)
    cmd := exec.Command(svc.Command, svc.Args...)
    if err := cmd.Run(); err != nil {
        log.Printf("Service %s failed: %v", svc.Name, err)
    }
}
```

### Example 3: Container Runtime

```go
package main

import (
    "fmt"
    "log"
    "os"
    "os/exec"
    "syscall"
)

func main() {
    // Mount container filesystems
    mountAll()

    // Setup networking
    setupContainerNetwork()

    // Execute the container entrypoint
    if len(os.Args) > 1 {
        runContainerCommand(os.Args[1:])
    } else {
        runShell()
    }
}

func mountAll() {
    // Implement mount logic
}

func setupContainerNetwork() {
    // Implement network setup
}

func runContainerCommand(args []string) {
    cmd := exec.Command(args[0], args[1:]...)
    cmd.Stdin = os.Stdin
    cmd.Stdout = os.Stdout
    cmd.Stderr = os.Stderr
    cmd.SysProcAttr = &syscall.SysProcAttr{
        Setpgid: true,
    }

    if err := cmd.Run(); err != nil {
        log.Fatalf("Command failed: %v", err)
    }
}

func runShell() {
    runContainerCommand([]string{"/bin/sh"})
}
```

## Firecracker Integration

### Creating Rootfs

```bash
# Build the image
make build

# Export to rootfs
docker create --name initrd-export dozman99/lab-custom-initrd-os:latest
docker export initrd-export -o initrd-rootfs.tar

# Create ext4 image (1GB is sufficient for minimal init)
dd if=/dev/zero of=custom-init.ext4 bs=1M count=1024
mkfs.ext4 custom-init.ext4

# Extract
mkdir -p /tmp/initrd-rootfs
sudo mount custom-init.ext4 /tmp/initrd-rootfs
sudo tar -xf initrd-rootfs.tar -C /tmp/initrd-rootfs
sudo umount /tmp/initrd-rootfs

# Cleanup
docker rm initrd-export
rm initrd-rootfs.tar
```

### Firecracker Configuration

```json
{
  "boot-source": {
    "kernel_image_path": "/var/lib/firecracker/vmlinux",
    "boot_args": "console=ttyS0 reboot=k panic=1 pci=off init=/init"
  },
  "drives": [{
    "drive_id": "rootfs",
    "path_on_host": "/path/to/custom-init.ext4",
    "is_root_device": true,
    "is_read_only": false
  }],
  "machine-config": {
    "vcpu_count": 1,
    "mem_size_mib": 256
  }
}
```

Note the `init=/init` boot argument pointing to your custom init binary.

### Recommended Resources

Minimal configuration:
- **CPU**: 1 vCPU
- **Memory**: 128-256MB RAM
- **Disk**: 512MB-1GB storage

## Testing

### Build and Test Init Locally

```bash
# Build init binary locally
cd init
go build -o init main.go

# Test it (requires root)
sudo ./init
```

### Test Container

```bash
# Build image
make build

# Run with your init as PID 1
docker run --rm -it --privileged \
  dozman99/lab-custom-initrd-os:$(git rev-parse --short HEAD)

# Inside container, verify PID 1
ps aux
```

### Debugging

```bash
# Build with debug symbols (modify Dockerfile temporarily)
go build -o init main.go  # Without -s -w flags

# Run with strace
docker run --rm -it --privileged \
  --entrypoint /usr/bin/strace \
  dozman99/lab-custom-initrd-os:latest \
  /init
```

## Use Cases

### 1. Minimal Container Runtime

Implement your own container runtime with just the features you need:
- Process isolation
- Resource limits
- Custom networking

### 2. Specialized Application Init

Bootstrap specific applications with custom requirements:
- Database initialization
- Configuration management
- Service orchestration

### 3. Educational/Research

Learn about:
- Linux boot process
- Init systems
- Process management
- System calls

### 4. Embedded Systems

Ultra-lightweight init for constrained environments:
- IoT devices
- Edge computing
- Embedded Linux

## Performance

### Boot Time
- **Container startup**: <100ms
- **Firecracker boot**: <500ms
- **Init execution**: Depends on your implementation

### Resource Usage
- **Memory**: ~10-50MB (base + your init logic)
- **Disk**: ~50-100MB
- **CPU**: Minimal (unless your init is CPU-intensive)

## Troubleshooting

### Issue: Build fails - cannot find init/main.go

**Solution**: Create your init implementation first:
```bash
mkdir -p init
cat > init/main.go <<'EOF'
package main
import "log"
func main() {
    log.Println("Hello from custom init!")
    select {}
}
EOF
```

### Issue: Container exits immediately

**Solution**: Your init must not exit. Add an infinite loop or wait for signals:
```go
select {}  // Block forever
// or
sig := make(chan os.Signal, 1)
signal.Notify(sig, syscall.SIGTERM)
<-sig
```

### Issue: Zombie processes accumulating

**Solution**: Implement proper SIGCHLD handling to reap zombies (see examples above).

### Issue: Static build fails with cgo errors

**Solution**: Use `--tags netgo` and ensure no cgo dependencies:
```bash
CGO_ENABLED=0 go build -o init main.go
```

## Best Practices

1. **Always reap zombies**: PID 1 must reap orphaned child processes
2. **Handle signals**: Respond to SIGTERM, SIGINT for graceful shutdown
3. **Mount filesystems early**: Especially /proc, /sys, /dev
4. **Log appropriately**: Use structured logging for debugging
5. **Keep it simple**: Complex init logic belongs in services, not init
6. **Test thoroughly**: Init bugs can break the entire system

## Comparison with Other Init Systems

| Feature | Custom Go Init | systemd | runit | busybox init |
|---------|----------------|---------|-------|--------------|
| **Size** | ~2-10MB | ~200MB+ | ~1MB | <1MB |
| **Complexity** | Your choice | High | Low | Very Low |
| **Features** | Custom | Many | Few | Minimal |
| **Boot Speed** | Very Fast | Moderate | Fast | Very Fast |
| **Flexibility** | Total | Limited | Moderate | Limited |

## Security Considerations

1. **Run as PID 1**: Your init has full system access
2. **Input validation**: Sanitize any configuration or input
3. **Privilege dropping**: Drop privileges when spawning child processes
4. **Resource limits**: Set ulimits for child processes
5. **Secure defaults**: Use secure configurations by default

## Related Components

- **Base Image** (`base_image/`) - Full systemd-based environment
- **K8s Lab** (`labs/k8_lab/`) - Kubernetes environment
- **VM Lab** (`labs/vm_lab/`) - General-purpose VM
- **Init Setup** (`init-setup/`) - Prepares rootfs for Firecracker

## References

- [Writing an Init System](https://felipec.wordpress.com/2013/11/04/init/)
- [Go syscall package](https://pkg.go.dev/syscall)
- [Linux Boot Process](https://en.wikipedia.org/wiki/Linux_startup_process)
- [Process Management in Go](https://pkg.go.dev/os/exec)

## Contributing

When contributing to this lab:
1. Keep the runtime image minimal
2. Document init implementation patterns
3. Provide example init implementations
4. Test with Firecracker
5. Measure boot times and resource usage

## License

See LICENSE file in repository root.
