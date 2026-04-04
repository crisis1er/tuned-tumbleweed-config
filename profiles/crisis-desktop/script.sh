#!/bin/bash
#
# crisis-desktop tuned script
# Handles two settings that cannot be cleanly managed via plugin config:
#
#   1. Audio power saving — disabled (overrides balanced timeout=10)
#      [audio] timeout=0 has a tuned verify bug; direct sysfs write avoids it
#
#   2. ALPM — applied only to SATA hosts (host0/sda, host1/sr0)
#      host2/sdb is USB (Samsung T7) — no link_power_management_policy file
#      balanced tries to set ALPM on all hosts; this script applies only where supported
#

. /usr/lib/tuned/functions

start() {
    # --- Audio ---
    # Disable HDA Intel auto-suspend (overrides balanced's 10s timeout)
    echo 0 > /sys/module/snd_hda_intel/parameters/power_save 2>/dev/null
    echo N > /sys/module/snd_hda_intel/parameters/power_save_controller 2>/dev/null

    # --- ALPM ---
    # Apply med_power_with_dipm only to hosts that have the sysfs control file
    # (SATA hosts only — USB host2 has no link_power_management_policy)
    for policy in /sys/class/scsi_host/host*/link_power_management_policy; do
        [ -f "$policy" ] && echo "med_power_with_dipm" > "$policy" 2>/dev/null
    done

    return 0
}

stop() {
    # Restore balanced defaults on profile change
    echo 10 > /sys/module/snd_hda_intel/parameters/power_save 2>/dev/null
    echo Y > /sys/module/snd_hda_intel/parameters/power_save_controller 2>/dev/null

    for policy in /sys/class/scsi_host/host*/link_power_management_policy; do
        [ -f "$policy" ] && echo "max_performance" > "$policy" 2>/dev/null
    done

    return 0
}

verify() {
    local retval=0

    # Verify audio power save is 0
    local audio_val
    audio_val=$(cat /sys/module/snd_hda_intel/parameters/power_save 2>/dev/null)
    if [ "$audio_val" != "0" ]; then
        echo "verify: failed: snd_hda_intel power_save = '$audio_val', expected '0'" >&2
        retval=1
    fi

    # Verify ALPM only on hosts that have the sysfs file
    for policy in /sys/class/scsi_host/host*/link_power_management_policy; do
        [ -f "$policy" ] || continue
        local alpm_val
        alpm_val=$(cat "$policy" 2>/dev/null)
        if [ "$alpm_val" != "med_power_with_dipm" ]; then
            echo "verify: failed: ${policy} = '$alpm_val', expected 'med_power_with_dipm'" >&2
            retval=1
        fi
    done

    return $retval
}

$1
