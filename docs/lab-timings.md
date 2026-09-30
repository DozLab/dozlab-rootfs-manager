# Lab Timings

How long each lab takes to build and to start. Use this to set expectations per lab, to spot
regressions, and as the data source for a future timings dashboard.

- Measured: 2026-09-30, run `20260930T070232-labs`
- Code: `main` with #5 (init.sh errors), #6 (rootfs built in Docker) and #7 (k8s lab on the VM lab) merged in
- Host: single x86_64 Ubuntu machine with KVM
- Raw data: [`timings/20260930T070232-labs.jsonl`](timings/20260930T070232-labs.jsonl)

## Iterations

Each iteration is one round of changes, with the times it produced. Add a new iteration (and
its raw run under `timings/`) every time a change is meant to make things faster, so progress
stays visible.

### Summary: session setup per iteration (lab start → VM answers SSH)

| Iteration | Date | Fixes applied (see [Fixes](#fixes-what-was-done-to-cut-the-time)) | vm session setup | k8s session setup |
|---|---|---|---|---|
| 0 | before 2026-09-29 | None: starting point | **30 s** (cluster) | never (no network/SSH) |
| 1 | 2026-09-29 | F1 shrink the rootfs | **8–10 s** (cluster) · 9 s (Docker) | never (no network/SSH) |
| 2 | 2026-09-30 | F3 build the rootfs inside Docker | **5.5 s** (Docker) | **15.5 s** (Docker) |
| 3 | next | F6, F7 (planned): slim the k8s rootfs, apt cache mounts | target < 6 s | target < 10 s |

"Cluster" means a lab pod on the local k3s node, from pod created to Ready. "Docker" means the
same init container and Firecracker image run directly in Docker (see
[How these were measured](#how-these-were-measured)); it leaves out pod scheduling (~1–2 s).

### Fixes: what was done to cut the time

Every fix, the problem it solved, and what it did to the times. "Before → after" uses the same
measurement method on both sides.

| Fix | Iteration | Problem (what made it slow or broken) | Fix (what was done) | Where | Before → after |
|---|---|---|---|---|---|
| **F1** | 1 | The init image baked in a **2 GiB ext4 that held only ~340 MiB of data**. `init-rootfs` copies the whole file into the pod on every session start (image layer → volume is a full copy), so users waited for 2 GiB of mostly empty blocks. | After building the ext4, run `e2fsck -f` and **`resize2fs -M`** to shrink the filesystem and the file to its contents (~350 MB). `init.sh` then **grows it to the session's disk size inside the pod** (`resize2fs <image> $IMAGE_SIZE`), which takes about a second. | First in `dozlab.sh` (local); now `init-setup/Dockerfile` (#6) | `init-rootfs` **16 s → 3–4 s** (cluster) |
| **F3** | 2 | Making the rootfs used `docker export` + **loop mount + sudo**: it needed root, ran one lab at a time (all labs wrote `init-setup/disk/image.ext4`), was never cached, left mounts behind on failure, and had to undo Docker leftovers (`/.dockerenv`, empty `/etc/hostname`). | The init-setup **Dockerfile builds the ext4 itself**: a build stage bind-mounts the lab image, copies it with `cp -a`, writes hostname/hosts/resolv.conf, then **`mkfs.ext4 -d`** creates the filesystem straight from the directory (30% headroom), and `resize2fs -M` shrinks it. No mount, no sudo; Docker caches the result and labs build in parallel. | `init-setup/Dockerfile`, `make build-init LAB=<lab>` (#6) | vm: 16 s → **16.5 s cold / ~1.5 s cached**, 348 → **311 MB**, no sudo. k8s: ~67 s → **44.7 s**, 2.0 → **1.4 GB**. Smaller images also cut the init container: vm ~5 → **3.1 s**, k8s ~21 → **12.6 s** |
| **F6** | 3 (planned) | The k8s rootfs is 1.4 GB, and the init container spends 12.6 s copying it. It includes **`linux-image-virtual` (a 5.15 kernel and modules) that Firecracker never uses**, since Firecracker boots its own kernel, and probably `cloud-init`. | Remove those packages and clean the apt caches in the k8s Dockerfile. | `labs/k8_lab/Dockerfile` | **Estimated, not measured:** ~200 MB removed, so rootfs 1.4 → ~1.2 GB, k8s init container **12.6 → ~10.6 s**, k8s session setup **15.5 → ~13.5 s** (about **2 s saved** per session start) |
| **F7** | 3 (planned) | Changing any early Dockerfile line re-downloads every apt package in later steps. That is most of the k8s lab's 159 s cold build. | `RUN --mount=type=cache,target=/var/cache/apt` (and `/var/lib/apt`) on the apt steps. | Lab Dockerfiles | Expected: faster rebuilds after a change; cold build unchanged. To be measured |

**Changes without a fix behind them:** the vm Firecracker → SSH time went from ~4 s (iteration 1)
to 2.4 s (iteration 2), but no change targeted boot. Treat it as run-to-run variation until
repeated runs confirm it.

### Iteration 0: starting point

- **Setup:** the init image baked in a 2 GiB ext4 that was mostly empty (~340 MiB of data).
  `init-rootfs` copied all 2 GiB into the pod on every session start. The rootfs was made with
  `docker export` + loop mount + sudo, one lab at a time. The k8s lab was built on the base image
  and had no network or SSH under Firecracker.
- **Times (cluster):** `init-rootfs` 16 s; pod created → Ready 30 s.
- **Source:** measured on the local k3s node and reported in #4. No raw run was kept.

### Iteration 1: shrink the rootfs, faster readiness

- **Fixes:** F1. Shrink the ext4 to its contents after building it (`resize2fs -M`; ~350 MB instead
  of 2 GiB), then grow it to the disk size in the pod. Readiness probe every second during
  startup (controller).
- **Times (cluster, vm lab):**

  | Stage | Run 1 | Run 2 |
  |---|---|---|
  | Schedule + sandbox | 1.0 s | 1.0 s |
  | `init-rootfs` (copy, fsck, grow) | 3.0 s | 4.0 s |
  | network-setup init container | 0.0 s | 1.0 s |
  | Start Firecracker + sidecar containers | 1.8 s | 1.2 s |
  | Tap + iptables + Firecracker API | 0.0 s | 0.1 s |
  | Load kernel/rootfs, start instance | 0.1 s | 0.1 s |
  | Guest kernel boot | 1.0 s | 1.0 s |
  | systemd → sshd listening | 1.1 s | 1.1 s |
  | Readiness probe notices sshd | 0.0 s | 0.4 s |
  | **Pod created → Ready** | **8.0 s** | **10.0 s** |

- **Times (Docker, same method as iteration 2):**

  | Lab | Rootfs → init image | Rootfs size | Init container | Firecracker → SSH |
  |---|---|---|---|---|
  | vm | 16 s (sudo + loop mount) | 348 MB | ~5 s | ~4 s |
  | k8s | ~67 s | 2.0 GB | ~21 s | never |

- **Source:** cluster runs [`timings/20260929T122254-test.jsonl`](timings/20260929T122254-test.jsonl)
  and [`timings/20260929T124538-test.jsonl`](timings/20260929T124538-test.jsonl). The Docker numbers
  were measured on 2026-09-30 before switching to iteration 2; no raw run was kept.

### Iteration 2: rootfs built in Docker, k8s lab on the vm lab

- **Fixes:** F3. The init-setup Docker build makes the ext4 itself with `mkfs.ext4 -d` (no sudo,
  no loop mount, cached by Docker, labs build in parallel; #6). The k8s lab is built on the vm lab,
  so it gets networking and SSH (#7). `init.sh` fails on errors and uses `IMAGE_DOWNLOAD_URL` (#5).
- **Times:** the [Results](#results-cold-build-no-docker-cache) tables below.
- **Change from iteration 1 (Docker method):**

  | Step | Iteration 1 | Iteration 2 | Change |
  |---|---|---|---|
  | vm rootfs → init image | 16 s, 348 MB, sudo | 16.5 s cold / ~1.5 s cached, 311 MB, no sudo | Same cold time, no sudo, cached rebuilds |
  | vm init container | ~5 s | 3.1 s | −2 s |
  | vm Firecracker → SSH | ~4 s | 2.4 s | −1.6 s (no fix targeted this; likely variation) |
  | **vm session setup** | **~9 s** | **5.5 s** | **−40%** |
  | k8s rootfs → init image | ~67 s, 2.0 GB | 44.7 s, 1.4 GB | −22 s, −30% size |
  | k8s init container | ~21 s | 12.6 s | −8 s |
  | k8s Firecracker → SSH | never | 2.9 s | Now usable |
  | **k8s session setup** | **never** | **15.5 s** | **Now usable** |

- **Source:** [`timings/20260930T070232-labs.jsonl`](timings/20260930T070232-labs.jsonl).
- **Not yet measured:** the cluster (pod created → Ready) with iteration 2's images.

### Iteration 3 (next): slim the k8s lab, faster rebuilds

- **Planned fixes:** F6, F7.
  - Remove `linux-image-virtual` (a 5.15 kernel Firecracker never uses) and `cloud-init` if unused
    from the k8s lab; clean apt caches. Setup time follows rootfs size (~1 s per 100 MB).
  - `RUN --mount=type=cache,target=/var/cache/apt` in the lab Dockerfiles, so package steps
    don't re-download after an earlier layer changes.
  - Fix the kubelet drop-in (`--container-runtime=remote` is rejected by kubelet 1.27+).
- **Targets:** k8s session setup under 10 s; k8s rootfs well under 1.4 GB; vm unchanged.
- **Times:** fill in after the run.

  | Step | Iteration 2 | Iteration 3 | Change |
  |---|---|---|---|
  | k8s lab image build (cold) | 159.3 s | | |
  | k8s rootfs size | 1.4 GB | | |
  | k8s init container | 12.6 s | | |
  | **k8s session setup** | **15.5 s** | | |
  | vm session setup | 5.5 s | | |

### Later ideas (not scheduled)

| Idea | Expected effect |
|---|---|
| Cache each lab's rootfs on the node and copy-on-write it per session | Init container close to 0 s for every lab |
| Warm pool: keep booted sessions ready per lab | Users wait ~0 s; costs idle CPU/RAM |
| Firecracker snapshots (resume instead of boot; `start-firecracker.sh` has the API calls) | Boot ~3 s → under 1 s |
| Registry build cache in CI (`--cache-from/--cache-to`) | CI stops rebuilding the base from scratch |

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

Iteration 2, run `20260930T070232-labs`.

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

To record a new iteration:

1. Make the change, then run `NO_CACHE=1 bash dozlab.sh labs` (cold) and, if possible, the
   cluster test session (`bash dozlab.sh test`), which records a per-phase pod breakdown.
2. Copy the run's lines from `~/.dozlab-local/timings.jsonl` to `docs/timings/<run>.jsonl`.
3. Add an iteration section above, with what changed, the new times, the change from the
   previous iteration, and the run file, and add a row to the summary table.

One file per run lets a dashboard chart every iteration.
