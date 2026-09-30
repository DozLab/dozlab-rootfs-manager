# Lab Timings

A timeline of every change that moved lab times: what changed, how much time it saved or
added for each VM, and what it cost. Only final, measured times are recorded. A change enters
the timeline when it reaches a working result, not while it's being debugged.

Raw measurements: [`timings/`](timings/), one file per run.

## What is being timed

```
 BUILD (once per change to a lab)                         SESSION SETUP (every time a user starts a lab)
 ┌────────────┐   ┌─────────────┐   ┌──────────────────┐   ┌──────────────────┐   ┌─────────────────────┐
 │ base image │ → │ lab image   │ → │ init image       │ → │ init container   │ → │ Firecracker boot    │
 │ (Ubuntu)   │   │ (Dockerfile)│   │ (lab → ext4 disk)│   │ (copy disk, grow │   │ (ready = SSH        │
 └────────────┘   └─────────────┘   └──────────────────┘   │  to 4 GB)        │   │  answers in the VM) │
                                                           └──────────────────┘   └─────────────────────┘
```

- **Session setup** is what users wait for, every time they start a lab. It's the main number.
- **Build time** is paid once per change, in CI or on a developer machine.

Each time is marked with where it was measured:
- **cluster**: a lab pod on the local k3s node, from pod created to Ready.
- **Docker**: the same init container and Firecracker image run in Docker. This leaves out pod
  scheduling (~1–2 s).

## Timeline

| Iteration | Date | What changed | vm session setup | k8s session setup | Time saved (−) or added (+) | Trade-off |
|---|---|---|---|---|---|---|
| 0 | before 2026-09-29 | Starting point | 30 s (cluster) | – | – | – |
| 1 | 2026-09-29 | Shrink the rootfs to its contents (F1); readiness probe every second | 8–10 s (cluster), ~9 s (Docker) | – | vm **−20 to −22 s** | One more build step (fsck + shrink); every session grows the disk at start (~1 s). The probe runs every second during startup |
| 2 | 2026-09-30 | Build the rootfs inside Docker (F3); build the k8s lab on the vm lab | 5.5 s (Docker) | 15.5 s (Docker) | vm **−3.5 s**; k8s first measured | Cold build of the vm init image is no faster (16.5 s vs 16 s); the build needs twice the rootfs size in temp space. The k8s build now waits for the vm build |
| 3 | 2026-09-30 | Per-session setup: cloud-init applies each session's SSH key and hostname and makes new host keys; init.sh writes the seed and still owns disk resizing; no IPv6 router discovery on eth0; no RSA host keys | 9.1–10.3 s (Docker) | not measured | vm **+3.6 to +4.8 s** | This is the cost of per-session setup: +51 MB rootfs (init container +0.4–1.6 s) and cloud-init runs before sshd (boot +3.2 s). The VM gets no IPv6 autoconfiguration (the lab network has none) and no RSA host key |
| 4 | planned | Remove the unused `linux-image-virtual` from the k8s lab (F6); apt cache mounts (F7) | unchanged | ~13.5 s (estimate) | k8s **~−2 s** (estimate) | None expected: Firecracker never uses that kernel. F7 keeps an apt cache on the build machine |

**Net for the vm lab:** 30 s → 5.5 s (−24.5 s) by iteration 2, then +3.6 to +4.8 s in iteration
3 to give every session its own key, hostname and host keys.

## Stage by stage

How each stage moved from one iteration to the next. **Bold** is the change: − is time saved, + is
time added. "First measured" means the stage has no earlier number to compare with.

### Build stages (paid once per change)

| Stage | 0 → 1 | 1 → 2 | 2 → 3 | 3 → 4 (planned) |
|---|---|---|---|---|
| base image | not measured | 67.8 s (first measured) | unchanged | unchanged |
| vm lab image | not measured | 3.7 s (first measured) | 3.7 → ~44 s (**+40 s**): installs cloud-init | unchanged |
| vm init image (lab → ext4) | 16 s (first measured) | 16 → 16.5 s cold (**+0.5 s**); cached rebuild ~1.5 s (**−14.5 s**) | 16.5 → ~17 s (**+0.5 s**): bigger rootfs | unchanged |
| k8s lab image | – | 159.3 s (first measured) | not measured | faster rebuilds after a change (F7, to be measured) |
| k8s init image | – | 44.7 s (first measured) | not measured | smaller rootfs (F6, to be measured) |

### Setup stages (paid every time a user starts a lab)

| Stage | 0 → 1 | 1 → 2 | 2 → 3 | 3 → 4 (planned) |
|---|---|---|---|---|
| vm init container | 16 → 3–4 s, cluster (**−12 to −13 s**): 2 GiB → 348 MB to copy | ~5 → 3.1 s (**−1.9 s**): 348 → 311 MB | 3.1 → 3.5–4.7 s (**+0.4 to +1.6 s**): 311 → 362 MB | unchanged |
| vm boot → SSH | not measured | ~4 → 2.4 s (**−1.6 s**): no change aimed at boot, likely run-to-run variation | 2.4 → 5.6 s (**+3.2 s**): cloud-init runs before sshd | unchanged |
| vm pod created → Ready (cluster) | 30 → 8–10 s (**−20 to −22 s**) | not measured on the cluster | not measured on the cluster | – |
| k8s init container | – | 12.6 s (first measured) | not measured | 12.6 → ~10.6 s (**~−2 s**, estimate) |
| k8s boot → SSH | – | 2.9 s (first measured) | not measured | unchanged |

### What went up and what went down

| | Went down | Went up |
|---|---|---|
| **Build** | vm init image rebuild −14.5 s once Docker caches it (iteration 2) | vm lab image +40 s and vm init image +0.5 s for cloud-init (iteration 3); vm init image cold +0.5 s (iteration 2) |
| **Setup** | vm init container −12 to −13 s (iteration 1) and −1.9 s (iteration 2); vm boot −1.6 s (iteration 2, likely variation) | vm init container +0.4 to +1.6 s and vm boot +3.2 s for per-session setup (iteration 3) |

The iteration 3 build numbers come from one build of the per-session test branch (not a
`NO_CACHE=1` run), so treat them as approximate.

## Per VM

### vm lab: general-purpose Ubuntu VM

| Iteration | Rootfs size | Init container | Boot → SSH | Session setup | Change from previous |
|---|---|---|---|---|---|
| 0 | 2 GiB | 16 s (cluster) | – | 30 s (cluster) | – |
| 1 | 348 MB | 3–4 s (cluster), ~5 s (Docker) | ~4 s (Docker) | 8–10 s (cluster), ~9 s (Docker) | −20 to −22 s: ~1.7 GB less to copy |
| 2 | 311 MB | 3.1 s | 2.4 s | 5.5 s | −3.5 s: smaller rootfs (init −1.9 s); boot −1.6 s with no change aimed at boot (likely run-to-run variation) |
| 3 | 362 MB | 3.5–4.7 s | 5.6 s | 9.1–10.3 s | +3.6 to +4.8 s: cloud-init (+51 MB, runs before sshd) |

Build (iteration 2, cold): base 67.8 s + lab 3.7 s + init image 16.5 s = **88.0 s**. A cached
rebuild of an unchanged image takes about 1–1.5 s.

### k8s lab: Kubernetes practice VM

| Iteration | Rootfs size | Init container | Boot → SSH | Session setup | Change from previous |
|---|---|---|---|---|---|
| 2 | 1.4 GB | 12.6 s | 2.9 s | 15.5 s | First measured: built on the vm lab |
| 4 (planned) | ~1.2 GB (estimate) | ~10.6 s (estimate) | ~2.9 s | ~13.5 s (estimate) | ~−2 s: no unused kernel to copy |

Build (iteration 2, cold): base 67.8 s + vm lab 3.7 s + k8s lab 159.3 s + init image 44.7 s =
**275.5 s (~4.6 min)**.

### custom-initrd lab

Not in the timeline: it never reaches a usable state under Firecracker (its `/init` isn't run and
it has no SSH). Its build is 13.4 s (lab 6.5 s + init image 6.9 s, 41 MB rootfs).

## Fixes: what was done to cut the time

Every fix, the problem it solved, and what it did to the times. "Before → after" uses the same
measurement method on both sides.

| Fix | Iteration | Problem (what made it slow or broken) | Fix (what was done) | Where | Before → after |
|---|---|---|---|---|---|
| **F1** | 1 | The init image baked in a **2 GiB ext4 that held only ~340 MiB of data**. `init-rootfs` copies the whole file into the pod on every session start (image layer → volume is a full copy), so users waited for 2 GiB of mostly empty blocks. | After building the ext4, run `e2fsck -f` and **`resize2fs -M`** to shrink the filesystem and the file to its contents (~350 MB). `init.sh` then **grows it to the session's disk size inside the pod** (`resize2fs <image> $IMAGE_SIZE`), which takes about a second. | First in `dozlab.sh` (local); now `init-setup/Dockerfile` (#6) | `init-rootfs` **16 s → 3–4 s** (cluster) |
| **F3** | 2 | Making the rootfs used `docker export` + **loop mount + sudo**: it needed root, ran one lab at a time (all labs wrote `init-setup/disk/image.ext4`), was never cached, left mounts behind on failure, and had to undo Docker leftovers (`/.dockerenv`, empty `/etc/hostname`). | The init-setup **Dockerfile builds the ext4 itself**: a build stage bind-mounts the lab image, copies it with `cp -a`, writes hostname/hosts/resolv.conf, then **`mkfs.ext4 -d`** creates the filesystem straight from the directory (30% headroom), and `resize2fs -M` shrinks it. No mount, no sudo; Docker caches the result and labs build in parallel. | `init-setup/Dockerfile`, `make build-init LAB=<lab>` (#6) | vm: 16 s → **16.5 s cold / ~1.5 s cached**, 348 → **311 MB**, no sudo. k8s: ~67 s → **44.7 s**, 2.0 → **1.4 GB**. Smaller images also cut the init container: vm ~5 → **3.1 s**, k8s ~21 → **12.6 s** |
| **F6** | 4 (planned) | The k8s rootfs is 1.4 GB, and the init container spends 12.6 s copying it. It includes **`linux-image-virtual` (a 5.15 kernel and modules) that Firecracker never uses**, since Firecracker boots its own kernel. | Remove `linux-image-virtual` and clean the apt caches in the k8s Dockerfile. **Keep `cloud-init`**: it delivers per-session setup (SSH key, hostname) from the seed that init.sh writes into the rootfs. | `labs/k8_lab/Dockerfile` | **Estimated, not measured:** ~200 MB removed, so rootfs 1.4 → ~1.2 GB, k8s init container **12.6 → ~10.6 s**, k8s session setup **15.5 → ~13.5 s** (about **2 s saved** per session start) |
| **F7** | 4 (planned) | Changing any early Dockerfile line re-downloads every apt package in later steps. That is most of the k8s lab's 159 s cold build. | `RUN --mount=type=cache,target=/var/cache/apt` (and `/var/lib/apt`) on the apt steps. | Lab Dockerfiles | Expected: faster rebuilds after a change; cold build unchanged. To be measured |

## The labs

| Lab | Purpose |
|---|---|
| **base** (`base_image/`) | Not a lab: the shared Ubuntu 22.04 layer (systemd, sshd, haveged, basic tools) |
| **vm** (`labs/vm_lab/`) | General Linux lab: shell, packages, scripting practice |
| **k8s** (`labs/k8_lab/`) | Kubernetes lab: practice `kubeadm`, containerd and `kubectl` (Kubernetes 1.30). Built on the vm lab |
| **custom-initrd** (`labs/custom-initrd/`) | Demo of a minimal Alpine VM with its own Go init. Not a usable lab yet |

## Rules of thumb

- **Boot is about the same for every lab** (~2.5–3 s to SSH without cloud-init, ~5.6 s with it).
- **Session setup grows with rootfs size**: the init container copies the whole image every time,
  roughly **1 s per 100 MB**. What a lab installs decides how long its users wait.
- **Targets:** vm session setup under 6 s, k8s under 10 s. Iteration 3 put the vm lab above its
  target in exchange for per-session setup.

## Open decisions (iteration 3)

- Hostname per session: `lab-<sessionId>`, or `dozlab-vm` for everyone.
- Remove the shared `lab-ssh-key` setting, or keep it as a fallback.
- Accept ~3 s more boot for per-session setup, or look into cloud-init's startup first.

## How times are measured and recorded

Measured by the local-cluster script's `labs` command (`NO_CACHE=1 bash dozlab.sh labs` for
cold builds; `LABS="vm k8s"` picks labs). It builds each lab, runs the init container against an
empty volume with `IMAGE_SIZE=4G`, starts the `dozlab-firecracker` image with `/dev/kvm` and
`/dev/net/tun` (2 vCPUs, 2 GiB), and times until `ssh root@<vm>` succeeds. Each stage becomes
one JSON line:

```json
{"run":"20260930T070232-labs","step":"setup: vm Firecracker start -> SSH","start":1790748246.492,"end":1790748248.874,"seconds":2.38,"status":"ok"}
```

| Iteration | Raw data |
|---|---|
| 0 | None kept (reported in #4) |
| 1 | [`20260929T122254-test`](timings/20260929T122254-test.jsonl), [`20260929T124538-test`](timings/20260929T124538-test.jsonl) (cluster) |
| 2 | [`20260930T070232-labs`](timings/20260930T070232-labs.jsonl) (Docker, cold) |
| 3 | None kept (one-off test script) |

**To add an iteration:**

1. Make the change and measure it until it works. Attempts that failed along the way aren't
   recorded.
2. Run the measurement and copy the run's lines to `timings/<run>.jsonl`.
3. Add one row to the Timeline (what changed, time saved or added, trade-off) and one row per
   affected VM under Per VM.
4. Prune: replace estimates with the measured numbers, remove planned rows that were dropped,
   and keep past iterations to their single rows.
