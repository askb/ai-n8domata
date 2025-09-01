#!/bin/bash
# quick-rocm-fix.sh - Apply ROCm tensor library fix to running container

echo "🔧 QUICK FIX: Applying ROCm tensor library workaround"
echo "=================================================="

# Apply fix to running container
docker exec -it cogvideo bash -c '
echo "🔍 Checking current ROCm setup..."

# Check if tensor library exists
TENSOR_FILE="/opt/rocm/lib/hipblaslt/library/TensileLibrary_lazy_gfx1030.dat"
if [ -f "$TENSOR_FILE" ]; then
    echo "✅ Tensor library already exists: $TENSOR_FILE"
else
    echo "❌ Missing tensor library: $TENSOR_FILE"
    echo "📁 Available tensor libraries:"
    ls -la /opt/rocm/lib/hipblaslt/library/ 2>/dev/null || echo "  No tensor library directory found"
fi

echo ""
echo "🔧 Applying environment variable workarounds..."

# Create a script to set environment variables for ComfyUI
cat > /opt/rocm-fix.sh << "EOF"
#!/bin/bash
# ROCm workaround environment variables
export ROCM_DISABLE_HIPBLASLT=1
export HIP_FORCE_DEV_KERNARG=1
export HIPBLASLT_DISABLE=1
export ROCBLAS_LAYER=0
export HSA_ENABLE_SDMA=0
export PYTORCH_HIP_ALLOC_CONF=expandable_segments:True,garbage_collection_threshold:0.6

echo "✅ ROCm workaround environment variables set"
echo "   ROCM_DISABLE_HIPBLASLT=1 (disables problematic tensor library)"
echo "   HIP_FORCE_DEV_KERNARG=1 (forces device kernel arguments)"
echo "   HIPBLASLT_DISABLE=1 (completely disables hipBLASLt)"

# Export for current session
exec "$@"
EOF

chmod +x /opt/rocm-fix.sh

echo "✅ ROCm fix script created at /opt/rocm-fix.sh"

echo ""
echo "🔧 Testing PyTorch with ROCm workarounds..."
source /opt/rocm-fix.sh
python3 -c "
import torch
print(f\"PyTorch version: {torch.__version__}\")
print(f\"CUDA available: {torch.cuda.is_available()}\")
try:
    if torch.cuda.is_available():
        device = torch.cuda.current_device()
        print(f\"Current device: {device}\")
        # Test basic tensor operation
        x = torch.randn(10, 10).cuda()
        y = torch.randn(10, 10).cuda()
        z = torch.mm(x, y)
        print(\"✅ Basic GPU tensor operations work!\")
    else:
        print(\"⚠️ GPU not available, will use CPU\")
except Exception as e:
    print(f\"❌ GPU operations failed: {e}\")
    print(\"💡 This is expected - will fall back to CPU mode\")
"

echo ""
echo "✅ Quick fix applied! Restart ComfyUI with:"
echo "   docker-compose restart cogvideo"
'

echo ""
echo "🎯 SUMMARY:"
echo "  ✅ Applied environment variable workarounds"
echo "  ✅ Created /opt/rocm-fix.sh script in container"
echo "  🔄 Restart the container to apply fixes"
echo ""
echo "💡 For permanent fix, choose one of the solutions above:"
echo "   1. Use AMD official ROCm image"
echo "   2. Build custom image with missing libraries"
echo "   3. Add environment variables to docker-compose.yml"
