#!/bin/bash

# Test ROCm PyTorch functionality before Docker setup

echo "=== Testing ROCm PyTorch Functionality ==="
echo ""

# Set environment
export HSA_OVERRIDE_GFX_VERSION=10.3.1
export HIP_VISIBLE_DEVICES=0  # Use discrete GPU (Device 0)

echo "Environment:"
echo "HSA_OVERRIDE_GFX_VERSION=$HSA_OVERRIDE_GFX_VERSION"
echo "HIP_VISIBLE_DEVICES=$HIP_VISIBLE_DEVICES"
echo ""

echo "Step 1: Install PyTorch with ROCm support..."
# Install PyTorch with ROCm 6.2 (matches your ROCm version)
python3 -m pip install --user \
    torch==2.4.0+rocm6.2 \
    torchvision==0.19.0+rocm6.2 \
    --index-url https://download.pytorch.org/whl/rocm6.2 \
    --force-reinstall

echo ""
echo "Step 2: Test PyTorch GPU detection..."
python3 << 'EOF'
import torch
print(f"PyTorch version: {torch.__version__}")
print(f"CUDA/HIP available: {torch.cuda.is_available()}")
print(f"Device count: {torch.cuda.device_count()}")

if torch.cuda.is_available():
    for i in range(torch.cuda.device_count()):
        print(f"Device {i}: {torch.cuda.get_device_name(i)}")
        props = torch.cuda.get_device_properties(i)
        print(f"  Memory: {props.total_memory // 1024**3} GB")
        print(f"  Compute capability: {props.major}.{props.minor}")

    # Test basic computation
    print("\nTesting GPU computation...")
    device = torch.cuda.current_device()
    print(f"Using device: {device}")

    # Create test tensors
    x = torch.randn(1000, 1000).cuda()
    y = torch.randn(1000, 1000).cuda()

    # Perform computation
    z = torch.matmul(x, y)
    print(f"Matrix multiplication successful!")
    print(f"Result shape: {z.shape}")
    print(f"GPU memory allocated: {torch.cuda.memory_allocated() // 1024**2} MB")

else:
    print("❌ No CUDA/HIP devices detected")
    print("Check HSA_OVERRIDE_GFX_VERSION and HIP_VISIBLE_DEVICES")
EOF

echo ""
echo "Step 3: GPU Selection Test..."
echo "Testing different HIP_VISIBLE_DEVICES values:"

for device in 0 1; do
    echo ""
    echo "Testing HIP_VISIBLE_DEVICES=$device..."
    HIP_VISIBLE_DEVICES=$device python3 << EOF
import torch
if torch.cuda.is_available():
    print(f"  Device name: {torch.cuda.get_device_name(0)}")
    print(f"  Memory: {torch.cuda.get_device_properties(0).total_memory // 1024**3} GB")
else:
    print("  No CUDA/HIP device available")
EOF
done

echo ""
echo "=== Results Summary ==="
echo ""
echo "If PyTorch detected your RX 6800M:"
echo "✅ ROCm is fully functional"
echo "✅ Ready for Docker Stable Diffusion setup"
echo ""
echo "If PyTorch shows issues:"
echo "⚠️  May need different PyTorch version"
echo "⚠️  Environment variables may need adjustment"
echo ""
echo "Next step: Configure Docker with these device mappings:"
echo "- /dev/kfd:/dev/kfd"
echo "- /dev/dri/card1:/dev/dri/card0 (discrete GPU)"
echo "- /dev/dri/renderD129:/dev/dri/renderD128 (discrete render)"
echo "- HIP_VISIBLE_DEVICES=0 (to use RX 6800M)"
