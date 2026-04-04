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
8. [Installation](#8-installation)
9. [Useful commands](#9-useful-commands)

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

  Fix     : timeout=0 in [audio] — audio never auto-suspends
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
       ├── [disk]  readahead=>4096 (USB SSD optimization)
       │
       ├── [audio] timeout=0 (no suspend — prevents playback crackles)
       │
       └── [video] panel_power_savings=0 (no screen dimming on AC)
                   radeon_powersave=dpm-performance (smooth decode)
```

The custom profile solves all the above problems while keeping the correct base (`balanced` with `schedutil`) — no need to rewrite from scratch.

---

## 7. Profile explained

```ini
[main]
summary=Profil desktop optimisé streaming/KVM/réseau — AC uniquement
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

### `[audio]` — no auto-suspend

```ini
timeout=0
```

Disables audio hardware power saving. The HDA audio controller stays active, eliminating the wake-up latency that causes the ~500ms crackle at the start of any media stream.

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

## 8. Installation

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
```

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

## 9. Useful commands

```bash
# Show active profile
tuned-adm active

# List all available profiles
tuned-adm list

# Check that tuned settings were correctly applied
tuned-adm verify

# Show current CPU governor on all cores
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Show current CPU frequency on all cores (in kHz)
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq

# Monitor CPU frequency live
watch -n 1 "cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq | awk '{print \$1/1000 \" MHz\"}'"

# Confirm AMD boost is enabled
cat /sys/devices/system/cpu/cpufreq/boost

# Check current swappiness
sysctl vm.swappiness

# Check EPP value
cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference

# Show readahead for main block device
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
