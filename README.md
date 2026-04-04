# tuned-tumbleweed-config

![Platform](https://img.shields.io/badge/platform-openSUSE%20Tumbleweed-73BA25)
![CPU](https://img.shields.io/badge/CPU-AMD%20A8--6410%20APU-ED1C24)
![Governor](https://img.shields.io/badge/governor-schedutil-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Profile](https://img.shields.io/badge/tuned-crisis--desktop-orange)
![Usage](https://img.shields.io/badge/usage-streaming%20%7C%20KVM%20%7C%20desktop-purple)

Custom **tuned** profile for openSUSE Tumbleweed on an AMD A8-6410 APU — built for a desktop running 24/7 on AC power, streaming media (Kodi, QMPlay2), KVM virtualization, and a full local network stack (Squid + Unbound + Caddy + Prometheus).

Deployed and validated in production. Every setting is justified.

---

## Table of contents

1. [How CPU frequency scaling works](#1-how-cpu-frequency-scaling-works)
2. [CPU governors — the decision makers](#2-cpu-governors--the-decision-makers)
3. [Memory management and tuned](#3-memory-management-and-tuned)
4. [Energy saving — what the kernel controls](#4-energy-saving--what-the-kernel-controls)
5. [Problems encountered with standard profiles](#5-problems-encountered-with-standard-profiles)
6. [Why create a custom profile](#6-why-create-a-custom-profile)
7. [Profile explained](#7-profile-explained)
8. [Repository structure](#8-repository-structure)
9. [Installation](#9-installation)
10. [Useful commands](#10-useful-commands)

---

## 1. How CPU frequency scaling works

Modern CPUs do not run at a fixed clock speed. The kernel adjusts frequency dynamically based on workload — this mechanism is called **CPUFreq**.

```
Hardware limits (BIOS / CPU spec)
      │
      ▼
┌─────────────────────────────────────────┐
│          CPUFreq subsystem              │
│                                         │
│  cpuinfo_min_freq = 1000 MHz  (floor)  │
│  cpuinfo_max_freq = 2000 MHz  (ceiling) │
│                                         │
│  scaling_min_freq ◄── tuned / user      │
│  scaling_max_freq ◄── tuned / user      │
└──────────────┬──────────────────────────┘
               │
               ▼
       [ Governor ]  ◄── decides the actual frequency
               │
               ▼
     CPU cores run at chosen freq
```

The **governor** is the algorithm that picks the frequency between min and max, based on its own logic (load, latency targets, power budget). tuned selects and configures the governor — it does not bypass it.

### Frequency range on this system

| Parameter | Value |
|-----------|-------|
| CPU | AMD A8-6410 APU (Beema, 28nm) |
| Cores | 4 (no hyperthreading) |
| Minimum frequency | 1000 MHz |
| Maximum frequency | 2000 MHz |
| Available governors | conservative, ondemand, performance, schedutil |

---

## 2. CPU governors — the decision makers

### Visual comparison

```
FREQUENCY
2000 MHz ─────────────────────────────────────────────────────── performance
          ████████████████████████████████████████████████████
          
1750 MHz                                                         ← AMD boost
          
1500 MHz ░░░░░░░░░░░░░░▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓  schedutil
          ^idle         ^load spike  ^idle      ^sustained load
          
1400 MHz  ░░░░░▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒  conservative
          (gradual ramp up / gradual ramp down)
          
1400 MHz  ░░░░░████████████████████░░░░░░░░░░████████████████  ondemand (legacy)
          ^idle ^jumps to max       ^idle     ^jumps to max
          
1000 MHz ─────────────────────────────────────────────────────── powersave
          ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░

          TIME ──────────────────────────────────────────────►

Legend:  ░ idle / very low freq   ▒ mid freq   ▓ high freq   █ max freq
```

### Governor profiles

#### `performance` — always maximum

```
Behavior : freq = max at all times
           ┌────────────────────────────────────┐
Freq       │████████████████████████████████████│  2000 MHz constant
           └────────────────────────────────────┘

✔ Best raw throughput
✔ Zero latency on load spikes
✗ Maximum power draw at all times
✗ Higher thermals — fan never rests
→ Use case: compilation servers, HPC, benchmarks
```

#### `powersave` — always minimum

```
Behavior : freq = min at all times
           ┌────────────────────────────────────┐
Freq       │░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░│  1000 MHz constant
           └────────────────────────────────────┘

✔ Minimum power consumption
✔ Minimum thermals
✗ System feels sluggish under any load
✗ Media playback stutters, KVM VMs throttled
→ Use case: idle servers, battery-critical laptops
```

#### `ondemand` — legacy reactive (deprecated)

```
Behavior : jumps to max on any load, drops slowly
           
           Load:  ░░░▓░░░░░▓▓▓░░░░░░░▓░░░░░░░░░░

           Freq:  ░░░█░░░░░███░░░░░░░█░░░░░░░░░░  (immediately max on spike)
                     ↑               ↑
                  jumps instantly  jumps instantly

✔ Responsive
✗ Overshoots — max freq even for a 1ms spike
✗ High context switching cost (sampling timer)
✗ Replaced by schedutil in kernel 4.7+
→ Use case: legacy systems — avoid on modern kernels
```

#### `conservative` — gradual ramp

```
Behavior : steps up/down slowly regardless of load urgency

           Load:  ░░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░

           Freq:  ░░░▒▒▒▒▒▓▓▓▓▓▓▓▓▒▒▒▒░░░░░░░░░░  (gradual)
                     ←ramp up→←ramp down→

✔ Smooth transitions — no overshoot
✗ Slow to respond — sustained load required before reaching max
✗ Streaming / VMs suffer during the ramp-up lag
→ Use case: thermally constrained embedded systems
```

#### `schedutil` — kernel scheduler integrated (modern, recommended)

```
Behavior : frequency mirrors CPU utilization reported by the scheduler
           No sampling timer — reacts on every scheduler event

           Utilization signal from kernel scheduler:
           ░░░░▒▒▒▒▒▒▒▒▓▓▓▓▓▓▓▓▓▓▓░░░░░░▒▒▒▒▒▒▒▒▓▓▓▓▓▓░░░

           CPU frequency response:
           ░░░░▒▒▒▒▒▒▒▒▓▓▓▓▓▓▓▓▓▓▓░░░░░░▒▒▒▒▒▒▒▒▓▓▓▓▓▓░░░
                ↑ near-instant response, proportional to actual load

✔ Frequency is proportional — no overshoot, no undershoot
✔ Reacts in microseconds (scheduler tick, not sampling poll)
✔ Aware of CPU idle states — better integration with cpuidle
✔ Native support for AMD boost
✗ Requires kernel 4.7+ (standard on all modern distributions)
→ Use case: everything — the correct default on modern Linux
```

### Side-by-side comparison

| Governor | Reaction time | Freq accuracy | Power efficiency | Latency | Status |
|----------|--------------|---------------|-----------------|---------|--------|
| performance | instant | fixed max | lowest | zero | production |
| powersave | instant | fixed min | highest | highest | production |
| ondemand | ~10ms (poll) | overshoots | moderate | low | **deprecated** |
| conservative | slow (stepped) | undershoots | good | high | legacy |
| **schedutil** | **<1ms (event)** | **proportional** | **best balance** | **low** | **recommended** |

---

## 3. Memory management and tuned

tuned can reinforce sysctl memory parameters to ensure the profile is coherent end-to-end. On this system, `/etc/sysctl.d/99-custom.conf` and the tuned profile both set `vm.swappiness = 30` — intentionally.

### Why both?

```
Boot sequence:
                                      
  kernel defaults                     vm.swappiness = 60 (kernel default)
       │
       ▼
  sysctl.d/ (99-custom.conf)    →     vm.swappiness = 30
       │
       ▼
  tuned profile loads           →     vm.swappiness = 30  (confirms, no conflict)
       │
       ▼
  Running system                →     vm.swappiness = 30  ✔
```

If tuned is restarted or the profile is reloaded, it re-applies its own sysctl values — ensuring nothing drifts back to kernel defaults. This is deliberate redundancy, not an error.

### Swap strategy on this system

```
RAM: 12 GB
Swap: zram (compressed swap in RAM, zstd algorithm)

                ┌──────────────────────────────────┐
                │           12 GB RAM               │
                │                                   │
                │  Active data        zram region   │
                │  (vm.swappiness=30  (compressed,  │
                │   keeps data in     in RAM)       │
                │   RAM longer)       ↕             │
                │                   fast swap       │
                └──────────────────────────────────┘

swappiness = 30 :  the kernel prefers to keep data in RAM
                   but is allowed to use zram under pressure
swappiness = 5  :  too aggressive → zram barely used → RAM wastes
swappiness = 60 :  kernel default → evicts too eagerly → latency spikes
```

---

## 4. Energy saving — what the kernel controls

Energy saving on Linux is a layered system. tuned sits in the middle and coordinates multiple subsystems:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Energy saving layers                         │
│                                                                 │
│  Layer 1 — CPU frequency (CPUFreq)                              │
│  ┌──────────────────────────────────┐                           │
│  │ Governor: schedutil              │ ← tuned sets this         │
│  │ Boost: enabled (AMD SenseMI)     │ ← tuned enables this      │
│  │ EPP: balance_performance         │ ← tuned sets this         │
│  └──────────────────────────────────┘                           │
│                                                                 │
│  Layer 2 — CPU idle states (cpuidle)                            │
│  ┌──────────────────────────────────┐                           │
│  │ C0  : active (running)           │                           │
│  │ C1  : halt (few μs to wake)      │ ← all enabled by default  │
│  │ C2+ : deeper sleep (ms to wake)  │                           │
│  └──────────────────────────────────┘                           │
│                                                                 │
│  Layer 3 — Storage power management                             │
│  ┌──────────────────────────────────┐                           │
│  │ Readahead: 4096 sectors          │ ← tuned sets this         │
│  │ (reduces random I/O on USB SSD)  │                           │
│  └──────────────────────────────────┘                           │
│                                                                 │
│  Layer 4 — GPU power management (Radeon R5)                     │
│  ┌──────────────────────────────────┐                           │
│  │ dpm-performance: GPU at full     │ ← tuned sets this         │
│  │ panel_power_savings: 0           │ ← no screen dimming       │
│  └──────────────────────────────────┘                           │
│                                                                 │
│  Layer 5 — Audio power management                               │
│  ┌──────────────────────────────────┐                           │
│  │ timeout: 0 (no auto-suspend)     │ ← tuned sets this         │
│  └──────────────────────────────────┘                           │
└─────────────────────────────────────────────────────────────────┘
```

### Energy Performance Preference (EPP)

EPP is a hint to the CPU hardware about the balance between performance and energy saving. It works *below* the governor — the governor sets frequency, EPP influences how aggressively the hardware power gates individual components.

```
EPP values (from most aggressive saving to most aggressive performance):

power            ←─────────────────────────────────────────► performance
  │         balance_power    balance_performance                   │
  ▼               ▼                  ▼                             ▼
 min                                                              max
 freq                                                             freq


This system: balance_performance
             ↑
     Prioritizes responsiveness for streaming and KVM
     without pinning to max power draw at all times
```

---

## 5. Problems encountered with standard profiles

### `balanced` — the starting point

openSUSE's default `balanced` profile uses `schedutil` which is correct, but its GPU settings default to `dpm-balanced` (power-saving mode for the Radeon R5 integrated GPU). This caused two issues:

```
Problem 1 — Video decoding stutters
─────────────────────────────────────
  Symptom : occasional dropped frames in Kodi and QMPlay2 during
            scene changes or high-bitrate streams (H.265 4K, AV1)
  
  Cause   : dpm-balanced throttles the Radeon R5 GPU below the
             clock needed for hardware-assisted decoding
  
  Effect  : ┌────────────────────────────────────────────────┐
            │  GPU clock (dpm-balanced)                      │
            │  ░░░░░░░▒▒▒▒▒▒▒▒░░░░░░░▒▒▒░░░░░░░░░░░░░░░░░  │
            │              ↑ decode demand spike             │
            │              GPU not fast enough → stutter     │
            └────────────────────────────────────────────────┘
  
  Fix     : radeon_powersave=dpm-performance in [video]
```

```
Problem 2 — Audio crackles at stream start
───────────────────────────────────────────
  Symptom : 0.5–1 second audio crackle / dropout when starting
            playback in Kodi, QMPlay2, or Spotify

  Cause   : The audio subsystem (HDA Intel) enters power-saving
            mode after inactivity. Waking it adds latency exactly
            at the moment playback starts.

  Fix     : [audio] timeout=-1 + modprobe.d power_save=0 + script.sh reinforcement
```

### `desktop` profile — why not just use it?

The `desktop` profile is tuned for interactive use but does not expose GPU power management controls for AMD/Radeon integrated graphics, and does not set EPP explicitly. It also does not set readahead, which matters for the USB SSD.

### `latency-performance` — too aggressive

Disables all CPU idle states (forces C0 at all times) — this keeps the AMD A8-6410 at full power even when idle, causing unnecessary heat without benefit on a 4-core desktop APU.

---

## 6. Why create a custom profile

Standard profiles are designed for broad compatibility — they cannot know that this machine is:

- Always on AC power (no battery saving needed)
- Running an integrated AMD Radeon R5 that needs GPU performance mode for smooth video
- Using a USB SSD where sequential readahead matters more than random I/O minimization
- Running KVM virtual machines that need consistent CPU availability
- Connected to a local privacy stack (Squid + Unbound) where network latency must be low
- Using zram as swap (not spinning disk — different swappiness optimum)

```
Profile inheritance chain:

  [ balanced ]  ← openSUSE base profile
       │
       │  inherits all settings, then overrides:
       ▼
  [ crisis-desktop ]
       │
       ├── [cpu]   governor=schedutil (confirmed, not changed)
       │           energy_performance_preference=balance_performance
       │           boost=1  (AMD boost explicitly enabled)
       │
       ├── [sysctl] vm.swappiness=30 (reinforces 99-custom.conf)
       │
       ├── [disk]       readahead=>4096 (all devices)
       │
       ├── [scsi_host]  devices=host0,host1 — ALPM for SATA only
       │                host2=USB (Samsung T7) excluded — no sysfs file
       │
       ├── [audio]      timeout=-1 / reset_controller=false
       │                workaround for tuned _norm_value() bug with timeout=0
       │                actual setting handled by modprobe.d + script.sh
       │
       ├── [script]     script.sh — reinforces power_save=0 after plugins run
       │
       └── [video]      panel_power_savings=0 (no screen dimming on AC)
                        radeon_powersave=dpm-performance (smooth decode)
```

The custom profile solves all the above problems while keeping the correct base (`balanced` with `schedutil`) — no need to rewrite from scratch.

---

## 7. Profile explained

```ini
[main]
summary=Optimized desktop profile for streaming, KVM and network stack — AC only
include=balanced        # inherit all balanced defaults
```

### `[cpu]` — frequency and boost

```ini
governor=schedutil
energy_performance_preference=balance_performance
boost=1
```

| Setting | Value | Effect |
|---------|-------|--------|
| `governor` | schedutil | Frequency tracks real load via scheduler events — best balance of responsiveness and efficiency |
| `energy_performance_preference` | balance_performance | Hardware EPP hint: lean toward performance without pinning to max |
| `boost` | 1 | Enables AMD Precision Boost — the CPU can briefly exceed its rated 2.0 GHz when thermal headroom allows |

### `[sysctl]` — memory

```ini
vm.swappiness=30
```

Ensures the tuned profile confirms the value set in `99-custom.conf`. If the profile is reloaded, swappiness never drifts back to the kernel default of 60.

### `[disk]` — storage

```ini
readahead=>4096
```

Sets readahead to 4096 sectors (2 MB) on all block devices. On a USB SSD used for sequential reads (package downloads, ISO files, video files, VM disk images), large readahead reduces I/O wait by pre-fetching data the CPU will need next.

```
Without readahead (default 256):
  Read request ──► [  256 sectors read  ] ──► next request waits

With readahead 4096:
  Read request ──► [        4096 sectors prefetched        ]
                   next requests served from cache ──► lower latency
```

### `[scsi_host]` — ALPM for SATA hosts only

```ini
devices=host0,host1
alpm=med_power_with_dipm
```

ALPM (Active Link Power Management) is a SATA power-saving feature managed by the `[scsi_host]` plugin — **not** the `[disk]` plugin as one might expect.

The `balanced` profile applies `alpm=med_power_with_dipm` to **all** SCSI hosts. On this system:

| Host | Device | Transport | ALPM sysfs |
|------|--------|-----------|------------|
| host0 | sda (SATA HDD) | SATA | present ✓ |
| host1 | sr0 (optical) | SATA | present ✓ |
| host2 | sdb (Samsung T7) | **USB** | absent ✗ |

`host2` is the boot USB SSD — USB devices have no `link_power_management_policy` file. Without `devices=host0,host1`, tuned attempts to write ALPM to host2, fails silently, then fails verification. Explicitly listing only SATA hosts solves both the runtime error and the verify failure.

### `[audio]` — disable auto-suspend

```ini
timeout=-1
reset_controller=false
```

The goal is to disable HDA Intel audio auto-suspend to prevent the ~500ms crackle at media playback start (Kodi, QMPlay2, Spotify). The actual setting is `power_save=0` in `/sys/module/snd_hda_intel/parameters/power_save`.

**Why not `timeout=0`?**

Setting `timeout=0` triggers a verified bug in tuned's `_norm_value()` function:

```python
# tuned/plugins/base.py — _norm_value()
def _norm_value(self, value):
    v = self._cmd.unquote(str(value))
    if re.match(r'\s*(0+,?)+([\da-fA-F]*,?)*\s*$', v):
        return re.sub(r'^\s*(0+,?)+', "", v)   # strips leading zeros
    return v

# _norm_value(0)      → str(0)='0'   → regex matches → strip '0' → ''
# _norm_value('0\n')  → '0\n' matches (trailing \n = \s*$) → strip '0' → '\n'
#
# verify: expected='' vs actual='\n' → False → FAIL
# log displays both as '' (str('\n').strip() = '') → misleading output
```

The kernel always appends `\n` to sysfs parameter files. After normalization, expected (`''`) and actual (`'\n'`) are not equal — verification fails even though the setting is correctly applied.

**Workaround:**

| Setting | Value | Effect |
|---------|-------|--------|
| `timeout=-1` | negative | `_set_timeout()` skips sysfs write (guard: `if timeout >= 0`), returns `None` → verify skips timeout check entirely |
| `reset_controller=false` | `'0'` written | both expected and actual normalize to `''` via `_norm_value` → verify passes |

The actual `power_save=0` is ensured by two layers:

1. **`/etc/modprobe.d/99-audio-nosuspend.conf`** — applied at kernel module load time
2. **`script.sh`** — writes `power_save=0` to sysfs after all plugins have run

### `[script]` — post-plugin reinforcement

```bash
script=${i:PROFILE_DIR}/script.sh
```

Runs `script.sh` after all plugins have applied their settings. Handles two tasks:

- **Audio**: writes `power_save=0` and `power_save_controller=N` directly to sysfs — reinforces what `modprobe.d` set at boot, overrides anything the balanced audio plugin may have written
- **ALPM verify**: custom `verify()` function that only checks hosts with the ALPM sysfs file — avoids false failures on USB hosts

### `[video]` — GPU performance

```ini
panel_power_savings=0
radeon_powersave=dpm-performance, auto
```

| Setting | Value | Effect |
|---------|-------|--------|
| `panel_power_savings` | 0 | Disables display brightness reduction — no dimming on AC |
| `radeon_powersave` | dpm-performance | Keeps the Radeon R5 at full GPU and memory clock — required for stutter-free hardware video decoding |

---

## 8. Repository structure

```
tuned-tumbleweed-config/
├── profiles/
│   └── crisis-desktop/
│       ├── tuned.conf      # Main profile — inherits balanced, overrides per section
│       └── script.sh       # Post-plugin script — audio power_save=0, ALPM verify
├── modprobe.d/
│   └── 99-audio-nosuspend.conf  # Boot-time audio fix (power_save=0 at module load)
└── LICENSE
```

---

## 9. Installation

### Requirements

| Component | Version |
|-----------|---------|
| openSUSE | Tumbleweed (also compatible with Leap) |
| tuned | 2.x+ |
| kernel | 4.7+ (schedutil required) |

### Install tuned (if not already installed)

```bash
sudo zypper install tuned
sudo systemctl enable --now tuned
```

### Deploy the profile

```bash
sudo mkdir -p /etc/tuned/profiles/crisis-desktop
sudo cp profiles/crisis-desktop/tuned.conf /etc/tuned/profiles/crisis-desktop/tuned.conf
sudo cp profiles/crisis-desktop/script.sh /etc/tuned/profiles/crisis-desktop/script.sh
sudo chmod 755 /etc/tuned/profiles/crisis-desktop/script.sh
```

### Disable audio auto-suspend at module level

```bash
sudo cp modprobe.d/99-audio-nosuspend.conf /etc/modprobe.d/
```

This ensures `power_save=0` is applied at kernel module load time, independently of tuned.

### Activate

```bash
sudo tuned-adm profile crisis-desktop
```

### Verify

```bash
tuned-adm active
tuned-adm verify
```

---

## 10. Useful commands

### tuned — profile management

```bash
# Show active profile
tuned-adm active

# List all available profiles
tuned-adm list

# Verify all tuned settings were correctly applied to the running system
tuned-adm verify

# Reload the active profile (re-apply all settings without reboot)
sudo tuned-adm profile crisis-desktop
```

---

### cpupower — the parallel view

`cpupower` is a standalone tool that reads and writes CPU frequency settings directly, independently from tuned. Understanding the relationship between the two is essential.

```
┌─────────────────────────────────────────────────────────────────┐
│                  Who controls what                              │
│                                                                 │
│   tuned (daemon)           cpupower (CLI tool)                  │
│   ───────────────          ───────────────────                  │
│   • Manages governor       • Reads governor                     │
│   • Sets EPP               • Can set governor manually          │
│   • Sets boost             • Can set boost manually             │
│   • Sets disk readahead    • Can set frequency range manually   │
│   • Sets audio timeout     • Shows full P-state table           │
│   • Sets video GPU mode    • Shows idle C-state stats           │
│                                                                 │
│   ⚠ If you set a governor manually with cpupower,              │
│     tuned will override it on next reload or profile change.   │
│     tuned always wins — it is a daemon, cpupower is one-shot.  │
└─────────────────────────────────────────────────────────────────┘
```

#### Full frequency info — verify the active governor and P-states

```bash
sudo cpupower frequency-info
```

Expected output on this system:

```
analyzing CPU 1:
  driver: acpi-cpufreq
  CPUs which run at the same hardware frequency: 1
  maximum transition latency: 4.0 us
  hardware limits: 1000 MHz - 2.00 GHz
  available frequency steps:  2.00 GHz, 1.80 GHz, 1.60 GHz, 1.40 GHz, 1.20 GHz, 1000 MHz
  available cpufreq governors: conservative ondemand performance schedutil
  current policy: frequency should be within 1000 MHz and 2.00 GHz.
                  The governor "schedutil" may decide which speed to use   ← governor confirmed
  current CPU frequency: 2.00 GHz (asserted by call to hardware)
  boost state support:
    Supported: yes
    Active: no       ← see explanation below
    Boost States: 2
    Total States: 8
    Pstate-Pb0: 2400MHz (boost state)   ← AMD boost P-state 1
    Pstate-Pb1: 2200MHz (boost state)   ← AMD boost P-state 2
    Pstate-P0:  2000MHz                 ← normal max (rated TDP)
    Pstate-P1:  1800MHz
    Pstate-P2:  1600MHz
    Pstate-P3:  1400MHz
    Pstate-P4:  1200MHz
    Pstate-P5:  1000MHz                 ← minimum
```

> **"Active: no" does NOT mean boost is disabled.**  
> It means no CPU core is *currently running* in a boost P-state at the moment the command was executed.  
> Boost is **enabled** (`/sys/devices/system/cpu/cpufreq/boost = 1`) — it activates automatically  
> when the scheduler requests it and thermal headroom allows. Under sustained load you will see  
> cores reaching 2200–2400 MHz transiently.

```
Boost state diagram:

  Boost enabled (boost=1), no current load:
  ┌────────────────────────────────────────┐
  │  Active: no                            │
  │  Current freq: 1600–2000 MHz           │  ← schedutil picks proportionally
  │  Boost P-states: available but idle    │
  └────────────────────────────────────────┘

  Boost enabled, CPU under burst load:
  ┌────────────────────────────────────────┐
  │  Active: yes                           │
  │  Current freq: 2200–2400 MHz           │  ← boost P-states engaged
  │  Duration: transient (thermal limit)   │
  └────────────────────────────────────────┘
```

#### Monitor all cores — frequency, C-states, idle time

```bash
sudo cpupower monitor
```

Expected output:

```
    | Mperf              || Idle_Stats
 CPU| C0   | Cx   | Freq  || POLL | C1   | C2
   0| 56.13| 43.87|  1803 ||  0.00| 12.30| 32.34
   1| 26.32| 73.68|  1875 ||  0.00| 16.13| 58.30
   2| 35.14| 64.86|  1818 ||  0.00| 18.29| 47.53
   3| 17.86| 82.14|  1813 ||  0.00| 20.90| 62.06
```

Reading the columns:

| Column | Meaning |
|--------|---------|
| `C0` | % of time the core was active (executing instructions) |
| `Cx` | % of time the core was in any idle state |
| `Freq` | Average frequency during the measurement window (MHz) |
| `C1` | % of time in shallow idle (fast wake, ~1 μs) |
| `C2` | % of time in deeper idle (slower wake, ~10 μs) |

A healthy desktop at rest: low C0 (< 30%), high C2, Freq around 1400–1800 MHz — schedutil correctly scaling down on idle cores.

---

### sysfs — low-level verification

```bash
# Confirm governor is schedutil on all 4 cores
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Confirm AMD boost is enabled (1 = on, 0 = off)
cat /sys/devices/system/cpu/cpufreq/boost

# Current frequency per core (in kHz — divide by 1000 for MHz)
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq

# Monitor frequency live across all cores
watch -n 1 "paste <(ls /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq) \
  <(cat /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq) | \
  awk '{printf \"CPU %s: %d MHz\n\", NR-1, \$2/1000}'"

# Confirm swappiness
sysctl vm.swappiness

# Show readahead for main block device (result in 512-byte sectors)
blockdev --getra /dev/sda
```

---

## Integration

| Component | Role |
|-----------|------|
| [sysctl-tumbleweed-config](https://github.com/crisis1er/sysctlconf) | `vm.swappiness=30` confirmed by both — no drift on profile reload |
| [firewalld-tumbleweed-config](https://github.com/crisis1er/firewalld-tumbleweed-config) | Network stack benefits from `balance_performance` EPP — lower latency for Squid/Unbound |
| KVM / libvirt | `boost=1` ensures VMs get full CPU headroom on burst workloads |
| Kodi / QMPlay2 | `dpm-performance` GPU + `timeout=0` audio = stutter-free, crackle-free playback |

---

## Contributing

Issues and pull requests are welcome.  
Please include your tuned version (`tuned-adm --version`), kernel version (`uname -r`), and CPU model (`grep "model name" /proc/cpuinfo | head -1`) in bug reports.

---

## License

MIT License — see [LICENSE](LICENSE) for details.
