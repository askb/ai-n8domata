#!/bin/bash

# Script to activate RX 6800M on ASUS G15 laptop
# Addresses the discrete GPU initialization issue

set -e

echo "=== Activating RX 6800M on ASUS G15 ==="
echo ""

echo "Current status:"
echo "- RX 6800M detected but not active (03:00.0)"
echo "- Only iGPU active (08:00.0 = card0)"
echo ""

echo "Step 1: Checking current GPU state..."
echo "Active DRI devices:"
ls -la /dev/dri/

echo ""
echo "Step 2: Loading amdgpu module with force detection..."
# Remove amdgpu module if loaded
sudo modprobe -r amdgpu 2>/dev/null || echo "amdgpu not loaded"

# Load amdgpu module with parameters to force detection of both GPUs
echo "Loading amdgpu with multi-GPU support..."
sudo modprobe amdgpu si_support=1 cik_support=1 || echo "amdgpu load failed"

echo ""
echo "Step 3: Checking what happened..."
echo "Checking dmesg for amdgpu messages (last 20 lines):"
sudo dmesg | grep -i amdgpu | tail -20 || echo "No amdgpu messages in dmesg"

echo ""
echo "Step 4: Checking for new DRI devices..."
echo "DRI devices after amdgpu load:"
ls -la /dev/dri/

# Check if /dev/kfd was created
echo ""
if [ -e /dev/kfd ]; then
    echo "✅ /dev/kfd created successfully!"
    ls -la /dev/kfd
else
    echo "⚠️  /dev/kfd still missing"
fi

echo ""
echo "Step 5: Trying to force GPU initialization..."
# Try to enable the discrete GPU power
echo "Attempting to power up RX 6800M..."

# Look for GPU power control
for gpu_path in /sys/bus/pci/devices/0000:03:00.0/power/*; do
    if [ -f "$gpu_path" ]; then
        echo "Found power control: $gpu_path"
        cat "$gpu_path" 2>/dev/null || echo "Cannot read $gpu_path"
    fi
done

# Try to rescan PCI bus
echo ""
echo "Step 6: Rescanning PCI bus..."
echo 1 | sudo tee /sys/bus/pci/rescan > /dev/null
sleep 2

echo ""
echo "Step 7: Final status check..."
echo "DRI devices:"
ls -la /dev/dri/

echo ""
echo "GPU detection:"
lspci | grep -E "(VGA|Display)" | grep AMD

echo ""
echo "=== Results ==="
if [ -e /dev/dri/card1 ]; then
    echo "🎉 SUCCESS! RX 6800M activated!"
    echo "Available devices:"
    ls -la /dev/dri/
    echo ""
    echo "Next steps:"
    echo "1. Install ROCm packages"
    echo "2. Configure Docker with both GPUs"
    echo "3. Test Stable Diffusion"
elif [ -e /dev/kfd ]; then
    echo "✅ PARTIAL SUCCESS: /dev/kfd created but RX 6800M may need more work"
    echo "Try rebooting and running this script again"
else
    echo "⚠️  RX 6800M still not fully activated"
    echo "Additional steps may be needed:"
    echo "1. BIOS/UEFI GPU settings"
    echo "2. ASUS GPU switching utilities"
    echo "3. Kernel parameters for dual GPU"
fi
