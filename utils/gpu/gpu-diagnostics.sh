#!/bin/bash

# GPU Hardware Diagnostic Script for RX 6800M
# Let's first understand what's happening with your GPU hardware

echo "=== GPU Hardware Diagnostic for RX 6800M ==="
echo ""

echo "1. Checking PCI devices for AMD GPUs:"
lspci | grep -i amd
echo ""

echo "2. Detailed GPU information:"
lspci -v | grep -A 10 -i amd
echo ""

echo "3. Checking if GPU is detected by kernel:"
lspci -nn | grep -E "(VGA|3D|Display)"
echo ""

echo "4. Current DRI devices:"
ls -la /dev/dri/ 2>/dev/null || echo "No /dev/dri directory found"
echo ""

echo "5. Checking for amdgpu in kernel messages:"
echo "Recent amdgpu messages from dmesg:"
dmesg | grep -i amdgpu | tail -10 || echo "No amdgpu messages in dmesg"
echo ""

echo "6. Checking available kernel modules for amdgpu:"
find /lib/modules/$(uname -r) -name "*amdgpu*" 2>/dev/null || echo "No amdgpu kernel modules found"
echo ""

echo "7. Checking if amdgpu module exists:"
modinfo amdgpu 2>/dev/null | head -5 || echo "amdgpu module not available"
echo ""

echo "8. Current kernel version:"
uname -r
echo ""

echo "9. Checking GPU power state (if available):"
for gpu in /sys/class/drm/card*/device/power_state; do
    if [ -f "$gpu" ]; then
        echo "$(dirname $gpu): $(cat $gpu)"
    fi
done 2>/dev/null || echo "No GPU power state information available"
echo ""

echo "10. Checking BIOS/UEFI GPU settings:"
echo "GPU PCI configuration:"
for device in $(lspci | grep -i amd | cut -d' ' -f1); do
    echo "Device $device:"
    lspci -v -s $device | grep -E "(Subsystem|Kernel driver|Kernel modules)"
done 2>/dev/null || echo "Could not read PCI configuration"
echo ""

echo "=== Analysis ==="
echo ""

# Check if RX 6800M is detected
if lspci | grep -i -q "6800"; then
    echo "✅ RX 6800M detected in PCI bus"
else
    echo "❌ RX 6800M not found in PCI bus"
    echo "   Possible issues:"
    echo "   - GPU disabled in BIOS/UEFI"
    echo "   - Hardware problem"
    echo "   - Power management issue"
fi

# Check for kernel modules
if find /lib/modules/$(uname -r) -name "*amdgpu*" | grep -q amdgpu; then
    echo "✅ amdgpu kernel module is available"
else
    echo "❌ amdgpu kernel module not found"
    echo "   Need to install: sudo dnf install akmod-amdgpu"
fi

# Check for conflicts
if lsmod | grep -E "(nouveau|nvidia)" > /dev/null; then
    echo "⚠️  Conflicting GPU drivers detected:"
    lsmod | grep -E "(nouveau|nvidia)"
    echo "   These may conflict with amdgpu"
fi

echo ""
echo "=== Next Steps ==="
echo "Based on the diagnostic above:"
echo ""
echo "If RX 6800M is detected:"
echo "1. sudo modprobe amdgpu"
echo "2. dmesg | grep amdgpu"
echo "3. Install ROCm packages"
echo ""
echo "If RX 6800M is NOT detected:"
echo "1. Check BIOS/UEFI settings"
echo "2. Ensure discrete GPU is enabled"
echo "3. Check power management settings"
echo "4. Verify hardware connections (if applicable)"
