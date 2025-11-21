# cAdvisor Memory Metrics Fix

## Issue

All container memory metrics show 0MB in Grafana, while CPU metrics work correctly.
`docker info` reports:
```
WARNING: No memory limit support
WARNING: No swap limit support
```

## Root Cause

The kernel command line contains `cgroup_disable=memory`, which explicitly disables cgroup memory support. This prevents cAdvisor from collecting memory statistics.

Check current status:
```bash
cat /proc/cmdline | grep -E "cgroup_disable|cgroup_enable|cgroup_memory"
```

If `cgroup_disable=memory` is present, memory metrics will not work.

## Solution

Enable cgroup memory support by modifying the Device Tree Blob (DTB) file.
On Raspberry Pi 5 with Ubuntu, the bootloader loads the DTB from
`/boot/firmware/current/`.

### Step 1: Identify Current Kernel and DTB

```bash
KERNEL_VER=$(uname -r)
DTB_FILE="bcm2712-rpi-5-b.dtb"  # For Raspberry Pi 5 Model B

echo "Kernel: $KERNEL_VER"
echo "DTB: $DTB_FILE"
```

### Step 2: Backup the DTB

```bash
sudo cp /boot/dtbs/${KERNEL_VER}/${DTB_FILE} /boot/dtbs/${KERNEL_VER}/${DTB_FILE}.backup
```

### Step 3: Decompile, Modify, and Recompile

```bash
# Decompile DTB to DTS
sudo dtc -I dtb -O dts /boot/dtbs/${KERNEL_VER}/${DTB_FILE}.backup -o /tmp/${DTB_FILE}.dts

# Replace cgroup_disable=memory with cgroup_enable=memory cgroup_memory=1
sudo sed -i 's/cgroup_disable=memory/cgroup_enable=memory cgroup_memory=1/g' /tmp/${DTB_FILE}.dts

# Recompile DTS to DTB
sudo dtc -I dts -O dtb /tmp/${DTB_FILE}.dts -o /boot/dtbs/${KERNEL_VER}/${DTB_FILE}
```

### Step 4: Copy to Bootloader Location

On Raspberry Pi 5 with Ubuntu, the bootloader loads from `/boot/firmware/current/`:

```bash
# Copy to current bootloader location
sudo cp /boot/dtbs/${KERNEL_VER}/${DTB_FILE} /boot/firmware/current/${DTB_FILE}

# Also copy to firmware root (for compatibility)
sudo cp /boot/dtbs/${KERNEL_VER}/${DTB_FILE} /boot/firmware/${DTB_FILE}
```

### Step 5: Reboot

```bash
sudo reboot
```

### Step 6: Verify

```bash
# Check kernel command line
cat /proc/cmdline | grep -E "cgroup_enable|cgroup_memory"

# Should show: cgroup_enable=memory cgroup_memory=1

# Check Docker
docker info | grep -i cgroup

# Should NOT show "No memory limit support" warnings
```

### Step 7: Restart cAdvisor

```bash
make restart DOMAIN=monitoring
```

Or manually:
```bash
docker restart monitoring-cadvisor
```

## Verification

Prometheus:

```bash
curl "http://localhost:9090/api/v1/query" \
  --data-urlencode 'query=container_memory_usage_bytes{job="cadvisor",name="forgejo"}'
```

The value should be non-zero (e.g., several hundred MB for Forgejo).

In Grafana, the "Forgejo Memory (MB)" panel should display actual memory usage instead of 0MB.

## Notes

- This is a system-level boot fix → reboot required
- The fix is persistent across reboots (DTB is loaded at boot)
- CPU metrics work because they don't require cgroup memory support
- This is a known limitation of Raspberry Pi OS/Ubuntu default configuration
- Kernel upgrades may require reapplying this fix

## Troubleshooting

### DTB Not Found

```bash
# List available DTBs
ls -la /boot/dtbs/*/

# Find the correct DTB for your Pi model
ls -la /boot/dtbs/*/bcm*.dtb
```

### Changes Not Applied After Reboot

1. Verify the DTB was copied to `/boot/firmware/current/`
2. Check `config.txt` for `os_prefix=current/` (should be present)
3. Verify the modified DTB is actually being loaded:
   ```bash
   # After reboot, check if the change persisted
   cat /proc/cmdline | grep cgroup_enable
   ```

### dtc Command Not Found

Install device tree compiler:

```bash
sudo apt-get update
sudo apt-get install device-tree-compiler
```

## Alternative: Kernel Command Line via flash-kernel

Not always effective on Pi 5 but possible to modify `/etc/default/flash-kernel`:

```bash
LINUX_KERNEL_CMDLINE_DEFAULT="cgroup_enable=memory cgroup_memory=1"
LINUX_KERNEL_CMDLINE="cgroup_enable=memory cgroup_memory=1"
```

However, on Raspberry Pi 5 with Ubuntu, the device tree bootargs typically override `flash-kernel` settings, so DTB modification is more reliable.

