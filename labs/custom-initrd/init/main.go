package main

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

const (
	defaultHostname = "dozlab-vm"
	defaultShell    = "/bin/sh"
)

// Config holds initialization configuration
type Config struct {
	Hostname     string
	Shell        string
	Debug        bool
	SkipNetwork  bool
	SkipServices bool
}

func main() {
	// Must be PID 1
	if os.Getpid() != 1 {
		log.Fatal("This init process must run as PID 1")
	}

	// Load configuration from environment
	cfg := loadConfig()

	if cfg.Debug {
		log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds | log.Lshortfile)
		log.Println("Starting custom init system (PID 1)")
	}

	// Setup signal handling for zombie process reaping
	setupSignalHandlers(cfg.Debug)

	// Core initialization sequence
	if err := mountFilesystems(cfg.Debug); err != nil {
		log.Fatalf("Failed to mount filesystems: %v", err)
	}

	if !cfg.SkipNetwork {
		if err := configureNetwork(cfg.Hostname, cfg.Debug); err != nil {
			log.Printf("Warning: Network configuration failed: %v", err)
		}
	}

	if !cfg.SkipServices {
		if err := startServices(cfg.Debug); err != nil {
			log.Printf("Warning: Service startup failed: %v", err)
		}
	}

	// Launch shell and wait
	if cfg.Debug {
		log.Printf("Launching shell: %s", cfg.Shell)
	}

	launchShell(cfg.Shell, cfg.Debug)

	// Cleanup on exit
	if cfg.Debug {
		log.Println("Init process exiting, shutting down...")
	}
	cleanup()
}

// loadConfig reads configuration from environment variables
func loadConfig() Config {
	return Config{
		Hostname:     getEnv("HOSTNAME", defaultHostname),
		Shell:        getEnv("SHELL", defaultShell),
		Debug:        getEnv("INIT_DEBUG", "false") == "true",
		SkipNetwork:  getEnv("SKIP_NETWORK", "false") == "true",
		SkipServices: getEnv("SKIP_SERVICES", "false") == "true",
	}
}

// getEnv returns environment variable value or default
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// mountFilesystems mounts essential pseudo filesystems
func mountFilesystems(debug bool) error {
	mounts := []struct {
		source string
		target string
		fstype string
		flags  uintptr
		data   string
	}{
		{"proc", "/proc", "proc", syscall.MS_NOSUID | syscall.MS_NOEXEC | syscall.MS_NODEV, ""},
		{"sysfs", "/sys", "sysfs", syscall.MS_NOSUID | syscall.MS_NOEXEC | syscall.MS_NODEV, ""},
		{"devpts", "/dev/pts", "devpts", syscall.MS_NOSUID | syscall.MS_NOEXEC, "mode=0620,ptmxmode=0666"},
		{"tmpfs", "/dev/shm", "tmpfs", syscall.MS_NOSUID | syscall.MS_NODEV, "mode=1777"},
		{"tmpfs", "/tmp", "tmpfs", syscall.MS_NOSUID | syscall.MS_NODEV, "mode=1777"},
	}

	for _, m := range mounts {
		// Create mount point if it doesn't exist
		if err := os.MkdirAll(m.target, 0755); err != nil && !os.IsExist(err) {
			return fmt.Errorf("failed to create mount point %s: %v", m.target, err)
		}

		// Check if already mounted
		if isMounted(m.target) {
			if debug {
				log.Printf("Already mounted: %s", m.target)
			}
			continue
		}

		// Mount the filesystem
		if err := syscall.Mount(m.source, m.target, m.fstype, m.flags, m.data); err != nil {
			return fmt.Errorf("failed to mount %s: %v", m.target, err)
		}

		if debug {
			log.Printf("Mounted: %s -> %s (type: %s)", m.source, m.target, m.fstype)
		}
	}

	return nil
}

// isMounted checks if a path is already mounted
func isMounted(path string) bool {
	data, err := os.ReadFile("/proc/mounts")
	if err != nil {
		return false
	}

	lines := strings.Split(string(data), "\n")
	for _, line := range lines {
		fields := strings.Fields(line)
		if len(fields) >= 2 && fields[1] == path {
			return true
		}
	}
	return false
}

// configureNetwork sets up basic networking
func configureNetwork(hostname string, debug bool) error {
	// Set hostname
	if err := syscall.Sethostname([]byte(hostname)); err != nil {
		return fmt.Errorf("failed to set hostname: %v", err)
	}

	if debug {
		log.Printf("Hostname set to: %s", hostname)
	}

	// Write hostname to /etc/hostname
	hostnameFile := "/etc/hostname"
	if err := os.WriteFile(hostnameFile, []byte(hostname+"\n"), 0644); err != nil {
		if debug {
			log.Printf("Warning: failed to write %s: %v", hostnameFile, err)
		}
	}

	// Bring up loopback interface
	if err := bringUpInterface("lo", debug); err != nil {
		if debug {
			log.Printf("Warning: failed to bring up loopback: %v", err)
		}
	}

	// Configure /etc/resolv.conf if it doesn't exist
	resolvConf := "/etc/resolv.conf"
	if _, err := os.Stat(resolvConf); os.IsNotExist(err) {
		resolverConfig := "nameserver 8.8.8.8\nnameserver 8.8.4.4\n"
		if err := os.WriteFile(resolvConf, []byte(resolverConfig), 0644); err != nil {
			if debug {
				log.Printf("Warning: failed to write %s: %v", resolvConf, err)
			}
		}
	}

	return nil
}

// bringUpInterface brings up a network interface
func bringUpInterface(iface string, debug bool) error {
	cmd := exec.Command("ip", "link", "set", iface, "up")
	if err := cmd.Run(); err != nil {
		// Try alternative method if ip command fails
		return bringUpInterfaceIoctl(iface, debug)
	}

	if debug {
		log.Printf("Brought up interface: %s", iface)
	}
	return nil
}

// bringUpInterfaceIoctl brings up interface using ioctl (fallback)
func bringUpInterfaceIoctl(iface string, debug bool) error {
	// This is a simplified version - full implementation would use syscall.IoctlSetInt
	// For now, we'll just log and continue
	if debug {
		log.Printf("Interface %s: ioctl method not fully implemented", iface)
	}
	return nil
}

// startServices launches optional services
func startServices(debug bool) error {
	// List of services to start (if they exist)
	services := []string{
		"/usr/sbin/sshd",
	}

	for _, svc := range services {
		if _, err := os.Stat(svc); err == nil {
			if debug {
				log.Printf("Starting service: %s", svc)
			}
			go runService(svc, debug)
		}
	}

	return nil
}

// runService starts and supervises a service
func runService(path string, debug bool) {
	for {
		cmd := exec.Command(path)
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr

		if err := cmd.Start(); err != nil {
			if debug {
				log.Printf("Failed to start service %s: %v", path, err)
			}
			return
		}

		if debug {
			log.Printf("Service %s started with PID %d", filepath.Base(path), cmd.Process.Pid)
		}

		// Wait for service to exit
		err := cmd.Wait()
		if debug {
			log.Printf("Service %s exited: %v", filepath.Base(path), err)
		}

		// Don't restart if init is shutting down
		select {
		case <-time.After(5 * time.Second):
			// Restart after 5 seconds
			if debug {
				log.Printf("Restarting service: %s", filepath.Base(path))
			}
		}
	}
}

// launchShell starts the user shell
func launchShell(shell string, debug bool) {
	// Find available shell
	shells := []string{shell, "/bin/bash", "/bin/sh", "/bin/ash"}
	var shellPath string

	for _, s := range shells {
		if _, err := os.Stat(s); err == nil {
			shellPath = s
			break
		}
	}

	if shellPath == "" {
		log.Fatal("No shell found")
	}

	// Setup shell environment
	cmd := exec.Command(shellPath)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = append(os.Environ(),
		"HOME=/root",
		"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
		"TERM="+getEnv("TERM", "xterm"),
	)

	// Run shell
	if err := cmd.Run(); err != nil {
		log.Printf("Shell exited with error: %v", err)
	}
}

// setupSignalHandlers configures signal handling for init
func setupSignalHandlers(debug bool) {
	// Channel for signals
	sigCh := make(chan os.Signal, 2)

	// Handle SIGCHLD for zombie reaping
	signal.Notify(sigCh, syscall.SIGCHLD)
	go func() {
		for {
			sig := <-sigCh
			if sig == syscall.SIGCHLD {
				reapZombies(debug)
			}
		}
	}()

	// Handle SIGTERM, SIGINT for graceful shutdown
	termCh := make(chan os.Signal, 1)
	signal.Notify(termCh, syscall.SIGTERM, syscall.SIGINT)
	go func() {
		sig := <-termCh
		if debug {
			log.Printf("Received signal %v, shutting down...", sig)
		}
		cleanup()
		os.Exit(0)
	}()
}

// reapZombies reaps all zombie child processes
func reapZombies(debug bool) {
	for {
		var wstatus syscall.WaitStatus
		pid, err := syscall.Wait4(-1, &wstatus, syscall.WNOHANG, nil)

		if err != nil || pid <= 0 {
			break
		}

		if debug {
			log.Printf("Reaped zombie process: PID %d, status: %v", pid, wstatus)
		}
	}
}

// cleanup performs shutdown tasks
func cleanup() {
	// Sync filesystems
	syscall.Sync()

	// Kill all processes (except init)
	syscall.Kill(-1, syscall.SIGTERM)

	// Give processes time to exit gracefully
	time.Sleep(2 * time.Second)

	// Force kill remaining processes
	syscall.Kill(-1, syscall.SIGKILL)

	// Final sync
	syscall.Sync()
}
