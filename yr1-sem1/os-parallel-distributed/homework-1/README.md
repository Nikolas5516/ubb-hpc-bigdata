# Homework 1 — Virtualized ROCKS 6.2 Cluster

A virtualized High-Performance Computing cluster built in Oracle VirtualBox for the
course **OS for Parallel and Distributed Systems**.
The cluster runs **ROCKS 6.2 "Sidewinder" (CentOS 6.6)** and consists of one head
node (frontend) and three compute nodes.

**Assignment:** install a virtualized cluster with a head node and at least two
compute nodes in a virtual environment. 

## Topology

```
                 ┌───────────────────────────────┐
   Internet ─────┤ eth1 (Bridged, public)        │
                 │          HeadNode             │
                 │        "cluster.local"        │
                 │ eth0 (Internal Network intnet)│
                 └───────────────┬───────────────┘
                                 │  private cluster network (10.0.0.0/8)
          ┌──────────────────────┼──────────────────────┐
     ┌────┴──────┐          ┌────┴──────┐          ┌────┴──────┐
     │compute-0-0│          │compute-0-1│          │compute-0-2│
     │  (eth0)   │          │  (eth0)   │          │  (eth0)   │
     └───────────┘          └───────────┘          └───────────┘
```

- The **frontend** has two NICs: `eth0` on a private Internal Network to the compute
  nodes, `eth1` bridged to the host's Wi-Fi for internet. It acts as router / DHCP /
  DNS for the private side.
- The **compute nodes** have a single NIC on the same Internal Network. They have no
  OS media of their own — they are imaged over the private network (PXE) from the
  frontend.
- **VM name → Rocks host name:** the VirtualBox VMs `ComputeNode1/2/3` register with
  the frontend as `compute-0-0`, `compute-0-1`, `compute-0-2` (Rocks assigns those
  names during `insert-ethers`). The HeadNode VM is the Rocks host `cluster`.

## Host environment

| Item | Value |
|------|-------|
| OS | Windows 11 |
| RAM | 32 GB |
| CPU | 12 cores |
| Internet | Mobile phone hotspot (carrier-assigned IP range) |
| Hypervisor | **Oracle VirtualBox 7.2.22** |
| Install media | ROCKS 6.2 Sidewinder Jumbo DVD ISO (`area51+base+...+zfs-linux-6.2.x86_64.disk1.iso`, ~3.25 GB) |

## Prerequisites

1. **Oracle VirtualBox 7.x** installed.
2. The **ROCKS 6.2 Jumbo DVD ISO**.
3. **No host virtualization changes needed.** VirtualBox 7.2.22 coexists with
   Windows 11's virtualization-based security, so the 64-bit CentOS 6.6 guest boots
   with Memory Integrity **on**, Virtual Machine Platform **enabled**, and the
   hypervisor launch type at its default (`auto`). 

## Virtual machine specifications

| VM | RAM | CPUs | Disk | Notes |
|----|-----|------|------|-------|
| HeadNode (frontend) | 4096 MB | 2 | 30 GB | Type Linux / Red Hat (64-bit) |
| ComputeNode1 | 2048 MB | 1 | 30 GB | " |
| ComputeNode2 | 2048 MB | 1 | 30 GB | " |
| ComputeNode3 | 2048 MB | 1 | 30 GB | " |

All disks are **dynamically allocated** (they do not consume the full 30 GB up front).

Common VirtualBox settings for every VM:
- **System → Motherboard:** EFI **disabled** (ROCKS 6.2 expects classic BIOS boot).
- **Display:** Graphics Controller **VMSVGA**.
- **Storage:** disk and optical drive on the **IDE** controller.

## Build — Part 1: the frontend

1. **New VM** `HeadNode`, Type Linux, Version **Red Hat (64-bit)**. Leave the ISO field
   in the wizard **blank**.
2. **Settings → Storage:** attach the Jumbo DVD ISO to the IDE optical drive.
3. **Settings → System → Boot Order:** Optical **above** Hard Disk.
4. **Settings → Network:**
   - Adapter 1 → **Internal Network**, name `intnet` (becomes `eth0`, private).
   - Adapter 2 → **Bridged Adapter**, host Wi-Fi card (becomes `eth1`, public).
5. **Start**, and at the boot prompt type **`build`**.
6. On **Select Your Rolls**, click **CD/DVD-based Roll** and select **all** rolls on
   the disc (base, kernel, os, area51, ganglia, hpc, sge, web-server, python, perl,
   java, …), then Submit.
7. **Cluster configuration** — replace the San Diego defaults:

   | Field | Value used |
   |-------|-----------|
   | Fully-Qualified Host Name | `cluster.local` |
   | Cluster Name | *(own name)* |
   | Certificate Organization | UBB Cluj |
   | Certificate Locality | Cluj-Napoca |
   | Certificate State | Cluj |
   | Certificate Country | RO |
   | Contact / URL / Lat-Long | left at defaults |
   | WebUI | installed |

8. **Public network (eth1):** IP `10.216.167.200`, netmask `255.255.255.0`, MTU `1500`.
   Gateway `10.216.167.204`, DNS `8.8.8.8`.
   *(These match the host's hotspot subnet at build time; hotspot addresses can change
   on reconnect. The private side is independent of the hotspot.)*
9. **Private network (eth0):** accept the ROCKS defaults (`10.1.1.1`).
10. Set the **root password** (kept private, not committed), time zone
    **Europe/Bucharest**, NTP `pool.ntp.org`, partitioning **auto**.
11. The frontend copies packages, installs, and reboots on its own to a CentOS 6.6
    login. Log in as **root**.

## Build — Part 2: the compute nodes

On the frontend, in a terminal:

```bash
insert-ethers          # choose the "Compute" appliance; leave it listening
```

For each of ComputeNode1–3 in VirtualBox:

1. **New VM** (2048 MB, 1 CPU, 30 GB, dynamically allocated), Type Linux / Red Hat (64-bit).
2. **Settings → Network:** Adapter 1 → **Internal Network `intnet`**; Adapter 2 **disabled**.
3. **Settings → System → Boot Order:** **Network first** (so it PXE-boots to install).
4. **Start.** The node appears in `insert-ethers` as `compute-0-0` / `-0-1` / `-0-2`
   (a `*` marks it registered) and auto-installs from the frontend over `eth0`.

When all three are registered, quit `insert-ethers` (**F8**).

After a node finishes imaging it reboots and will loop on PXE ("no more network
devices"). Fix once per node: power it off and set **Hard Disk first** in the boot
order. The node then boots its installed OS to a `compute-0-x login:` prompt. (Compute
nodes are headless; they are managed from the frontend, not logged into directly.)

## Verification

From the frontend terminal:

```bash
rocks list host
```

Four machines registered (frontend + three compute nodes):

```
HOST         MEMBERSHIP  CPUS  RACK  RANK
cluster      Frontend    2     0     0
compute-0-0  Compute     1     0     0
compute-0-1  Compute     1     0     1
compute-0-2  Compute     1     0     2
```

```bash
rocks run host "hostname"
```

Every compute node answers over the private network:

```
compute-0-0.local
compute-0-1.local
compute-0-2.local
```

These two outputs are the proof the cluster is built and operational. The actual
captures from this build are in `screenshots/`.

## Part 3: regular user, shared storage & MPI

Adds a non-root user, confirms the NFS-shared home works across the nodes, and runs an
MPI job that spans the compute nodes.

### 1. Create the user and propagate it

On the frontend, as **root**:

```bash
useradd student
passwd student
rocks sync users      # pushes the user + SSH keys to every compute node
```

`rocks sync users` is the critical step: a plain `useradd` only creates the account on
the frontend; this distributes it (and the passwordless-SSH keys) to all compute nodes.

### 2. Fix — NFS home automount must use the private IP

**Symptom:** logging in as `student` on a compute node failed with `Could not chdir to
home directory /home/student` / NFS `No route to host`.

**Cause:** `/home` is NFS-exported from the frontend and automounted on the nodes. The
map `/etc/auto.home` referenced the frontend by name `cluster.local`, which on the nodes
resolves to the frontend's **public** (hotspot) IP — unreachable from the private
network (and it changes on hotspot reconnect).

**Fix:** point the automount at the fixed **private** IP `10.1.1.1`. On the frontend:

```bash
sed -i 's/cluster\.local/10.1.1.1/g' /etc/auto.home   # repoint the map
411put /etc/auto.home                                  # publish to the nodes
rocks run host compute "411get --all"                  # nodes pull the new map
rocks run host compute "service autofs restart"        # reload automount
```

### 3. Verify as the user

```bash
su - student
ssh compute-0-0          # passwordless (shared SSH keys via the NFS home)
hostname                 # -> compute-0-0.local
df -h                    # -> /home mounted from 10.1.1.1:/export/home/student
```

### 4. Run the MPI job

```bash
module load rocks-openmpi
mpirun -np 3 --host compute-0-0,compute-0-1,compute-0-2 hostname
```

Output — one line per node, proving the job was distributed across the private network:

```
compute-0-0.local
compute-0-1.local
compute-0-2.local
```

The `--host` list must have **no spaces** between the node names.

## Starting and stopping the cluster

**Shut down** — compute nodes first, frontend last:

```bash
rocks run host compute "shutdown -h now"   # from the frontend
shutdown -h now                            # then the frontend itself
```

**Start up** — frontend first, then the nodes:

1. VirtualBox → start **HeadNode**, log in as root, let its services come up.
2. Start **ComputeNode1/2/3** (they boot from disk straight to their login prompts).
3. Confirm with `rocks run host "hostname"`.

Only the frontend is needed for write-up work; start the nodes only to demonstrate the
full cluster.

## Troubleshooting (issues encountered during this build)

- **ISO keeps detaching from the optical drive mid-install** — re-insert it live via
  the running VM's **Devices → Optical Drives** menu, without powering off.
- **"Rocks disc was not found"** — the optical drive showed **Empty** in Storage;
  re-attach the ISO.
- **Compute node: "no more network devices" after install** — it is PXE-looping; set
  **Hard Disk first** in that node's boot order.
- **"REMOTE HOST IDENTIFICATION HAS CHANGED"** when running a command on a node — a
  stale SSH host key after reinstalling the node. Not an attack; it clears once the
  node settles (or remove the old key from `/root/.ssh/known_hosts`).
- **Harmless warnings:** the desktop "running as root super user" notice is expected on
  a ROCKS frontend; `maddash-server` (perfSONAR) and `ibaddr` (InfiniBand) failing at
  boot/shutdown are expected in a VM with no such hardware; the graphics-controller
  warning is cleared by selecting **VMSVGA**.

## Repository layout

```
yr1-sem1/os-parallel-distributed/homework-1/
├── README.md        this file
├── .gitignore       ignores *.iso, *.vdi, VM logs/snapshots
└── screenshots/
    ├── 01-rocks-list-run.png      rocks list host + rocks run host "hostname"
    └── 02-user-ssh-df-mpi.png     su - student / ssh / df -h / mpirun
```

VM disk images and ISOs are **not** committed (they are gigabytes); they are documented
here and reproduced from the steps above.