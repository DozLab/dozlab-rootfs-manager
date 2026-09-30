# Lab Timings

How long each lab takes to build and to start. Use this to set expectations per lab, to spot
regressions, and as the data source for a future timings dashboard.

- Measured: 2026-09-30, run `20260930T070232-labs`
- Code: `main` with #5 (init.sh errors), #6 (rootfs built in Docker) and #7 (k8s lab on the VM lab) merged in
- Host: single x86_64 Ubuntu machine with KVM
- Raw data: [`timings/20260930T070232-labs.jsonl`](timings/20260930T070232-labs.jsonl)

## Two clocks: build time vs session setup

Each lab goes through the same pipeline:

```
 BUILD (once per change to a lab)                         SESSION SETUP (every time a user starts a lab)
 ┌────────────┐   ┌─────────────┐   ┌──────────────────┐   ┌──────────────────┐   ┌─────────────────────┐
 │ base image │ → │ lab image   │ → │ init image       │ → │ init container   │ → │ Firecracker boot    │
 │ (Ubuntu)   │   │ (Dockerfile)│   │ (lab → ext4 disk)│   │ (copy disk, grow │   │ (ready = SSH        │
 └────────────┘   └─────────────┘   └──────────────────┘   │  to 4 GB)        │   │  answers in the VM) │
                                                           └──────────────────┘   └─────────────────────┘
```

- **Build time** is paid once, in CI or on a developer machine, when a lab changes. No user waits for it.
- **Session setup** is paid every time a user starts a lab. This is the number users feel, and
  the one to keep small.

## The labs and what they are for

| Lab | Purpose | Built on | Status |
|---|---|---|---|
| **base** (`base_image/`) | Not a lab. Shared Ubuntu 22.04 layer with systemd, sshd, haveged and basic tools | `ubuntu:22.04` | Keep |
| **vm** (`labs/vm_lab/`) | General Linux lab: shell, packages, scripting practice. eth0 networking, key-only root SSH, serial console | base | Keep. The baseline lab |
| **k8s** (`labs/k8_lab/`) | Kubernetes lab: practice `kubeadm`, containerd and `kubectl` (Kubernetes 1.30) | vm | Keep. Its disk image should be trimmed |
| **custom-initrd** (`labs/custom-initrd/`) | Demo of a minimal Alpine VM with its own Go init process | `alpine:3.18` | Not usable: Firecracker doesn't run its `/init` (no `init=/init` in the boot args), and it has no network or SSH, so neither users nor the terminal sidecar can reach it. Candidate for removal |

## Results (cold build, no Docker cache)

### Base image

| Stage | Time |
|---|---|
| Build base image (apt install from scratch) | **67.8 s** |

### vm lab: general-purpose Ubuntu VM

| Stage | Time | Notes |
|---|---|---|
| Build lab image | 3.7 s | Small layer on top of base |
| Build init image | 16.5 s | Disk image 311 MB |
| **Build total** (incl. base) | **88.0 s** | |
| Setup: init container | 3.1 s | Copy + grow to 4 GB |
| Setup: Firecracker start → SSH | 2.4 s | |
| **Session setup total** | **5.5 s** | |

### k8s lab: Kubernetes practice VM

| Stage | Time | Notes |
|---|---|---|
| Build lab image | 159.3 s | containerd download, Kubernetes packages |
| Build init image | 44.7 s | Disk image 1.4 GB |
| **Build total** (incl. base + vm) | **275.5 s (~4.6 min)** | |
| Setup: init container | 12.6 s | Copying 1.4 GB is the slow part |
| Setup: Firecracker start → SSH | 2.9 s | |
| **Session setup total** | **15.5 s** | |

### custom-initrd lab: minimal Alpine demo

| Stage | Time | Notes |
|---|---|---|
| Build lab image | 6.5 s | Go build + Alpine; doesn't use base |
| Build init image | 6.9 s | Disk image 41 MB |
| **Build total** | **13.4 s** | |
| Setup: init container | 1.0 s | |
| Setup: Firecracker start → SSH | never | No SSH server; the boot wait timed out |

### All labs at a glance

| Lab | Lab image | Init image (disk size) | Init container | Firecracker → SSH | Session setup |
|---|---|---|---|---|---|
| base | 67.8 s | – | – | – | – |
| vm | 3.7 s | 16.5 s (311 MB) | 3.1 s | 2.4 s | **5.5 s** |
| k8s | 159.3 s | 44.7 s (1.4 GB) | 12.6 s | 2.9 s | **15.5 s** |
| custom-initrd | 6.5 s | 6.9 s (41 MB) | 1.0 s | never | not usable |

A cached rebuild of an unchanged image takes about 1–1.5 s.

## Why the times differ

- **Boot is the same for every lab**: about 3 s from Firecracker start to SSH.
- **Session setup grows with disk image size**, because the init container copies the whole
  image into the session every time: 41 MB → 1 s, 311 MB → 3 s, 1.4 GB → 13 s. Roughly **1 s per
  100 MB**. What a lab installs decides how long its users wait.
- **k8s is slow to build** because of package downloads (containerd, Kubernetes). That's a
  one-time cost. It's slow to start because of its disk image size, which includes a 5.15 kernel
  (`linux-image-virtual`) that Firecracker never uses.

## Expectations per lab

| Lab | Session setup target | Current | What it takes |
|---|---|---|---|
| vm | under 6 s | 5.5 s ✅ | Nothing |
| k8s | under 10 s | 15.5 s ❌ | Shrink the disk image: remove `linux-image-virtual` (and `cloud-init` if unused). Fix the kubelet drop-in (`--container-runtime=remote` is rejected by kubelet 1.27+) so the lab works as a Kubernetes lab |
| New labs | about 3 s boot + about 1 s per 100 MB of disk image | – | Keep the disk image lean; build on the vm lab so networking and SSH work |

## Before and after the build changes

Measured with the same Docker boot setup, before and after #6 (rootfs built in Docker) and #7
(k8s lab on the VM lab):

| Step | Before | After |
|---|---|---|
| vm rootfs → init image | 16 s, 348 MB (sudo + loop mount) | 16.5–20 s cold / 4 s cached, 311 MB, no sudo |
| k8s rootfs → init image | ~67 s, 2.0 GB | 42–45 s, 1.4–1.5 GB |
| Init container, vm | ~5 s | ~3–4 s |
| Init container, k8s | ~21 s | ~13–16 s |
| vm: Firecracker start → SSH | ~4 s | ~2.4–3 s |
| k8s: Firecracker start → SSH | never (no network or sshd) | ~2.9 s |

For comparison, on the local k3s cluster (2026-09-29, before these changes) a vm lab pod went
from created to Ready in 8–10 s, with 3–4 s of that in the init container.

## How these were measured

Every lab is built and booted in Docker, without a cluster or sudo:

1. Build the lab image with its Makefile (`--no-cache` for cold numbers).
2. Build the init image with `make -C init-setup build LAB=<lab>`.
3. Run the init container against an empty volume with `IMAGE_SIZE=4G`, as the lab pod's
   init container does.
4. Start the `dozlab-firecracker` image with `/dev/kvm` and `/dev/net/tun` (2 vCPUs, 2 GiB), and
   time until `ssh root@<vm>` succeeds.

The measurements come from the local-cluster script's `labs` command
(`NO_CACHE=1 bash dozlab.sh labs`; `LABS="vm k8s"` picks labs). It appends one JSON line per
stage:

```json
{"run":"20260930T070232-labs","step":"setup: vm Firecracker start -> SSH","start":1790748246.492,"end":1790748248.874,"seconds":2.38,"status":"ok"}
```

To add a new measurement, add its JSON lines to `docs/timings/` as `<run>.jsonl` and update the
tables above. Keeping one file per run lets a dashboard compare runs over time.
