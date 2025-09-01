#!/bin/bash

# Quick PyTorch ROCm test for RX 6800M

echo "=== Quick PyTorch ROCm Test ==="
echo ""

# Set environment
export HSA_OVERRIDE_GFX_VERSION=10.3.1
export HIP_VISIBLE_DEVICES=0

echo "Installing PyTorch with ROCm 6.2..."
python3 -m pip install --user \
    torch==2.5.1+rocm6.2 \
    torchvision==0.20.1+rocm6.2 \
    --index-url https://download.pytorch.org/whl/rocm6.2 \
    --quiet

echo ""
echo "Testing GPU detection..."

python3 << 'EOF'
import torch
import os

print(f"Environment:")
print(f"  HSA_OVERRIDE_GFX_VERSION: {os.environ.get('HSA_OVERRIDE_GFX_VERSION', 'Not set')}")
print(f"  HIP_VISIBLE_DEVICES: {os.environ.get('HIP_VISIBLE_DEVICES', 'Not set')}")
print(f"  PyTorch version: {torch.__version__}")
print("")

print(f"GPU Detection:")
print(f"  CUDA available: {torch.cuda.is_available()}")

if torch.cuda.is_available():
    print(f"  Device count: {torch.cuda.device_count()}")
    for i in range(torch.cuda.device_count()):
        device_name = torch.cuda.get_device_name(i)
        props = torch.cuda.get_device_properties(i)
        memory_gb = props.total_memory // 1024**3
        print(f"  Device {i}: {device_name}")
        print(f"    Memory: {memory_gb} GB")
        print(f"    Compute capability: {props.major}.{props.minor}")

    print("")
    print("Testing GPU computation...")
    try:
        # Test basic computation
        x = torch.randn(1000, 1000, device='cuda')
        y = torch.randn(1000, 1000, device='cuda')
        z = torch.matmul(x, y)

        print(f"  ✅ Matrix multiplication successful!")
        print(f"  Memory allocated: {torch.cuda.memory_allocated() // 1024**2} MB")
        print(f"  Max memory allocated: {torch.cuda.max_memory_allocated() // 1024**2} MB")

    except Exception as e:
        print(f"  ❌ GPU computation failed: {e}")

else:
    print("  ❌ No CUDA/HIP devices detected")
    print("  Check environment variables and ROCm installation")

EOF

echo ""
echo "=== Test Complete ==="
echo ""
echo "If you see 'AMD Radeon RX 6800M' with ~12GB memory above:"
echo "✅ ROCm is working perfectly!"
echo "✅ Ready for Docker Stable Diffusion setup"
echo ""
echo "If you see issues:"
echo "⚠️  Check ROCm installation"
echo "⚠️  Try different HIP_VISIBLE_DEVICES values (0 or 1)"
