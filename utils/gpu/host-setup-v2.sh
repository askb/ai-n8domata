#!/bin/bash

# Troubleshoot current ROCm installation issues on Fedora 41

echo "=== ROCm Troubleshooting for Fedora 41 ==="
echo ""

# Check what ROCm packages are currently installed
echo "1. Currently installed ROCm packages:"
dnf list installed | grep rocm | sort

echo ""
echo "2. Available ROCm packages in repositories:"
dnf search rocm 2>/dev/null | grep "^rocm" | head -10

# Check the OpenCL conflict
echo ""
echo "3. OpenCL conflict analysis:"
echo "Currently installed OpenCL packages:"
dnf list installed | grep -i opencl

echo ""
echo "4. Checking GPU devices and permissions:"
ls -la /dev/dri/
echo ""
if [ -e /dev/kfd ]; then
    echo "/dev/kfd exists:"
    ls -la /dev/kfd
else
    echo "/dev/kfd does NOT exist"
fi

# Check amdgpu module
echo ""
echo "5. Checking amdgpu kernel module:"
if lsmod | grep -q amdgpu; then
    echo "✅ amdgpu module is loaded"
    lsmod | grep amdgpu
else
    echo "❌ amdgpu module is NOT loaded"
fi

# Check for conflicting packages
echo ""
echo "6. Checking for package conflicts:"
if dnf list installed | grep -q "ocl-icd"; then
    echo "⚠️  ocl-icd is installed - this conflicts with ROCm OpenCL"
    echo "   Consider removing: sudo dnf remove ocl-icd"
fi

# Environment check
echo ""
echo "7. Current environment variables:"
env | grep -E "(HSA_|HIP_|ROCM_)" || echo "No ROCm environment variables set"

echo ""
echo "=== Recommended Actions ==="
echo ""

# Provide specific recommendations based on current state
if [ ! -e /dev/kfd ]; then
    echo "PRIORITY 1: /dev/kfd is missing"
    echo "Solutions:"
    echo "  a) Load amdgpu module: sudo modprobe amdgpu"
    echo "  b) Check BIOS settings for GPU"
    echo "  c) Reboot system"
    echo ""
fi

if dnf list installed | grep -q "ocl-icd"; then
    echo "PRIORITY 2: Resolve OpenCL conflict"
    echo "Solutions:"
    echo "  a) Remove conflicting package: sudo dnf remove ocl-icd"
    echo "  b) Then try: sudo dnf install rocm-opencl"
    echo ""
fi

if ! lsmod | grep -q amdgpu; then
    echo "PRIORITY 3: amdgpu module not loaded"
    echo "Solutions:"
    echo "  a) Load module: sudo modprobe amdgpu"
    echo "  b) Check dmesg: dmesg | grep amdgpu"
    echo "  c) Verify GPU is detected: lspci | grep -i amd"
    echo ""
fi

echo "Quick fix commands to try:"
echo "1. sudo dnf remove ocl-icd"
echo "2. sudo modprobe amdgpu"
echo "3. sudo chmod 666 /dev/kfd /dev/dri/*"
echo "4. export HSA_OVERRIDE_GFX_VERSION=10.3.1"
echo "5. rocminfo | grep gfx"
