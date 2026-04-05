# Changelog

All notable changes to this configuration are documented here.

---

## [1.0] — 2026-04-04

### Added
- Initial production profile `crisis-desktop` for openSUSE Tumbleweed / AMD A8-6410
- CPU governor `ondemand` with `up_threshold=70`, `sampling_down_factor=100`
- Disk scheduler `bfq` for SSD USB — optimized for mixed read/write workloads
- `vm.swappiness=10`, `vm.dirty_ratio=15`, `vm.dirty_background_ratio=5`
- `net.core.rmem_max` / `wmem_max` tuned for streaming and proxy workloads
- Audio latency tuning with `timer_slack` workaround for upstream plugin bug
- `scsi_host` link_power_management policy set to `med_power_with_dipm`
- Full inline documentation — every parameter explained with rationale
- `cpupower` section in README — parallel tuning approach, C-states, boost explained
- All `tuned-adm verify` failures documented and resolved or justified
