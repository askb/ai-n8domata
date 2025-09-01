#!/bin/bash
set -e

echo "🔧 Starting CogVideo with smart caching (models + dependencies)"
echo "💡 To force fresh install: rm ./caches/cogvideo-pip/cogvideo_*"
echo "💡 Models are automatically cached via Docker volumes"
echo "💡 All caches stored in host ./caches/ directory"
echo "🔍 Environment info: Python $(python3 --version), Pip $(pip --version)"

# Use clean container paths (mapped to host ./caches/ dirs)
export PIP_DISABLE_PIP_VERSION_CHECK=1
export HF_HOME=/app/cache/huggingface
export PIP_CACHE_DIR=/app/cache/pip

# Verify mapped cache directories exist and fix permissions
if [ ! -d "/app/cache/pip" ]; then
    echo "❌ Pip cache volume not properly mapped from host ./caches/cogvideo-pip"
    exit 1
fi

if [ ! -d "/app/cache/huggingface" ]; then
    echo "❌ HuggingFace cache volume not properly mapped from host ./caches/cogvideo-huggingface"
    exit 1
fi

# Fix cache permissions (container runs as root)
chown -R root:root /app/cache/pip /app/cache/huggingface 2>/dev/null || true
chmod -R 755 /app/cache/pip /app/cache/huggingface 2>/dev/null || true

echo "✅ Cache volumes properly mapped from host ./caches/ directories"

# SMART ComfyUI installation - separate location to avoid volume conflicts
COMFYUI_INSTALL_DIR="/opt/ComfyUI-install"
COMFYUI_RUNTIME_DIR="/opt/ComfyUI"

if [ ! -f "$COMFYUI_INSTALL_DIR/main.py" ] || [ ! -d "$COMFYUI_INSTALL_DIR/comfy/ldm/models" ]; then
    echo "📦 Installing ComfyUI to separate location (avoiding volume conflicts)..."
    echo "  🔍 Checking current ComfyUI state:"
    echo "    main.py exists: $([ -f "$COMFYUI_INSTALL_DIR/main.py" ] && echo "YES" || echo "NO")"
    echo "    ldm/models exists: $([ -d "$COMFYUI_INSTALL_DIR/comfy/ldm/models" ] && echo "YES" || echo "NO")"

    # Check if ComfyUI source files are available
    if [ -d "/opt/ComfyUI-core" ]; then
        # Copy ComfyUI to separate install directory (complete copy)
        echo "  📁 Copying complete ComfyUI installation..."
        mkdir -p "$COMFYUI_INSTALL_DIR"
        cp -r /opt/ComfyUI-core/* "$COMFYUI_INSTALL_DIR/"

        if [ $? -eq 0 ]; then
            echo "  ✅ Complete ComfyUI installation successful"

            # Install ComfyUI requirements
            if [ -f "$COMFYUI_INSTALL_DIR/requirements.txt" ]; then
                echo "  📦 Installing ComfyUI requirements..."
                pip install -r "$COMFYUI_INSTALL_DIR/requirements.txt"
            fi
        else
            echo "  ❌ Copy failed!"
            exit 1
        fi
    else
        echo "❌ ComfyUI source files not found at /opt/ComfyUI-core"
        echo "💡 Run: git clone https://github.com/comfyanonymous/ComfyUI.git ./comfyui-install"
        exit 1
    fi
else
    echo "✅ ComfyUI already installed at $COMFYUI_INSTALL_DIR"
fi

# Create runtime directory with symlinks to avoid volume conflicts
echo "🔗 Setting up ComfyUI runtime with symlinks..."
mkdir -p "$COMFYUI_RUNTIME_DIR"

# Symlink all ComfyUI files except directories that have volume mounts
cd "$COMFYUI_INSTALL_DIR"
for item in *; do
    if [ "$item" != "models" ] && [ "$item" != "output" ] && [ "$item" != "custom_nodes" ]; then
        ln -sf "$COMFYUI_INSTALL_DIR/$item" "$COMFYUI_RUNTIME_DIR/$item" 2>/dev/null || true
    fi
done

# 🔧 CRITICAL: Fix model path detection - direct file modification approach
echo "🔧 Fixing model path detection for volume-mounted directories..."

# Method 1: Ensure the install and runtime directories are properly linked
echo "🔗 Creating proper model directory links..."
if [ -d "/opt/ComfyUI/models" ] && [ -d "/opt/ComfyUI-install" ]; then
    # Remove any existing models directory in install location
    rm -rf "/opt/ComfyUI-install/models" 2>/dev/null || true
    # Create symlink from install to runtime models
    ln -sf "/opt/ComfyUI/models" "/opt/ComfyUI-install/models"
    echo "✅ Linked /opt/ComfyUI-install/models -> /opt/ComfyUI/models"
fi

# Method 2: Ensure both directories point to the same models
echo "🔧 Ensuring model directory consistency..."
mkdir -p "$COMFYUI_RUNTIME_DIR/models/checkpoints"
mkdir -p "$COMFYUI_RUNTIME_DIR/models/vae"
mkdir -p "$COMFYUI_RUNTIME_DIR/models/unet"
mkdir -p "$COMFYUI_RUNTIME_DIR/models/diffusion_models"
mkdir -p "$COMFYUI_RUNTIME_DIR/models/t5"
mkdir -p "$COMFYUI_RUNTIME_DIR/models/CogVideo"

# Method 3: Verify the checkpoint file is accessible from both paths
echo "🔍 Verifying checkpoint accessibility..."
CHECKPOINT_FILE="/opt/ComfyUI/models/checkpoints/v1-5-pruned-emaonly.ckpt"
if [ -f "$CHECKPOINT_FILE" ]; then
    echo "✅ Checkpoint accessible at runtime path: $(ls -la "$CHECKPOINT_FILE")"
    # Ensure it's also accessible from install path
    INSTALL_CHECKPOINT="/opt/ComfyUI-install/models/checkpoints/v1-5-pruned-emaonly.ckpt"
    if [ -f "$INSTALL_CHECKPOINT" ] || [ -L "$INSTALL_CHECKPOINT" ]; then
        echo "✅ Checkpoint also accessible from install path"
    else
        echo "⚠️ Checkpoint not accessible from install path, creating link..."
        mkdir -p "$(dirname "$INSTALL_CHECKPOINT")"
        ln -sf "$CHECKPOINT_FILE" "$INSTALL_CHECKPOINT" 2>/dev/null || true
    fi
else
    echo "❌ Checkpoint not found at $CHECKPOINT_FILE"
fi

# Volume-mounted directories (models, output, custom_nodes) are handled by Docker
echo "  ✅ ComfyUI runtime setup complete (using original main.py, paths fixed)"

# Function to check model existence and size
check_model() {
    local path="$1"
    local min_size="$2"
    if [ -f "$path" ]; then
        size=$(stat -c%s "$path" 2>/dev/null || echo 0)
        if [ "$size" -gt "$min_size" ]; then
            echo "✅ Found valid model: $path ($(du -h "$path" | cut -f1))"
            return 0
        else
            echo "❌ Model exists but too small: $path"
            return 1
        fi
    else
        echo "❌ Model not found: $path"
        return 1
    fi
}

# Smart dependency caching - use mapped cache volumes only
DEPS_CACHE_FILE="/app/cache/pip/cogvideo_deps_installed"
ROCM_CACHE_FILE="/app/cache/pip/rocm_pytorch_installed"
NODES_CACHE_FILE="/app/cache/pip/cogvideo_nodes_installed"

REQUIRED_DEPS="einops aiohttp yarl pyyaml numpy transformers diffusers accelerate safetensors huggingface-hub scipy pillow psutil tqdm torchsde spandrel kornia opencv-python opencv-contrib-python matplotlib imageio imageio-ffmpeg pytorch_lightning"

echo "📦 Checking dependency cache..."
if [ -f "$DEPS_CACHE_FILE" ]; then
    echo "✅ Dependencies cache found - checking validity..."
    # Quick check if core packages exist
    if python3 -c "import torch, einops, transformers, diffusers, cv2, pytorch_lightning" 2>/dev/null; then
        echo "✅ All core dependencies cached and available - skipping installation"
        SKIP_DEPS_INSTALL=true
    else
        echo "❌ Some dependencies missing - will reinstall"
        SKIP_DEPS_INSTALL=false
    fi
else
    echo "📦 No dependency cache found - will install all dependencies"
    SKIP_DEPS_INSTALL=false
fi

# Install core dependencies only if needed
if [ "$SKIP_DEPS_INSTALL" = false ]; then
    echo "Installing core dependencies..."
    pip install $REQUIRED_DEPS
    if [ $? -eq 0 ]; then
        echo "$(date)" > "$DEPS_CACHE_FILE"
        echo "✅ Dependencies installed and cached"
    else
        echo "❌ Some dependencies failed to install"
    fi
fi

# Install PyTorch ROCm only if needed (with smart caching)
if [ -f "$ROCM_CACHE_FILE" ] && python3 -c "import torch; exit(0 if 'rocm' in torch.__version__ else 1)" 2>/dev/null; then
    echo "✅ PyTorch ROCm already installed and cached"
else
    echo "📦 Installing PyTorch ROCm..."
    pip uninstall -y torch torchvision torchaudio 2>/dev/null || true
    pip install torch==2.5.1+rocm6.2 torchvision==0.20.1+rocm6.2 torchaudio==2.5.1+rocm6.2 --index-url https://download.pytorch.org/whl/rocm6.2
    if [ $? -eq 0 ]; then
        echo "$(date)" > "$ROCM_CACHE_FILE"
        echo "✅ PyTorch ROCm installed and cached"
    fi
fi

# Check existing CogVideo models
echo "🔍 Checking existing CogVideo models..."

# Debug: List actual directory contents
echo "Actual CogVideo directory contents:"
ls -la /opt/ComfyUI/models/CogVideo/ 2>/dev/null || echo "CogVideo directory not found"

# Define model paths
COGVIDEO_2B_FILE="/opt/ComfyUI/models/CogVideo/CogVideoX-2b/transformer/diffusion_pytorch_model.safetensors"
COGVIDEO_5B_FILE="/opt/ComfyUI/models/CogVideo/CogVideoX-5b/transformer/diffusion_pytorch_model-00001-of-00002.safetensors"
T5_ENCODER_FILE="/opt/ComfyUI/models/t5/google_t5-v1_1-xxl_encoderonly-fp8_e4m3fn.safetensors"
SD15_FILE="/opt/ComfyUI/models/checkpoints/v1-5-pruned-emaonly.ckpt"

# Check models
echo "Checking CogVideoX-2b at: $COGVIDEO_2B_FILE"
if check_model "$COGVIDEO_2B_FILE" 2000000000; then
    COGVIDEO_2B_READY="true"
else
    COGVIDEO_2B_READY="false"
fi

echo "Checking CogVideoX-5b at: $COGVIDEO_5B_FILE"
if check_model "$COGVIDEO_5B_FILE" 5000000000; then
    COGVIDEO_5B_READY="true"
else
    COGVIDEO_5B_READY="false"
fi

echo "Checking T5 encoder at: $T5_ENCODER_FILE"
# Debug T5 encoder path
if [ -f "$T5_ENCODER_FILE" ]; then
    T5_SIZE=$(stat -c%s "$T5_ENCODER_FILE" 2>/dev/null || echo 0)
    echo "  T5 file exists, size: $T5_SIZE bytes ($(du -h "$T5_ENCODER_FILE" | cut -f1))"
    if [ "$T5_SIZE" -gt 10000000 ]; then  # 10MB minimum
        T5_READY="true"
        echo "  ✅ T5 encoder ready"
    else
        T5_READY="false"
        echo "  ❌ T5 file too small or corrupted (0 bytes)"
        echo "  💡 To fix: Re-download T5 encoder to ./cogvideo-models/t5/"
    fi
else
    echo "  ❌ T5 file not found at $T5_ENCODER_FILE"
    # List t5 directory contents for debugging
    echo "  T5 directory contents:"
    ls -la /opt/ComfyUI/models/t5/ 2>/dev/null || echo "  T5 directory not found"
    T5_READY="false"
fi

# Download SD 1.5 if missing (required for ComfyUI compatibility)
if ! check_model "$SD15_FILE" 3000000000; then
    echo "📥 Downloading minimal SD 1.5 checkpoint (silent mode)..."
    mkdir -p /opt/ComfyUI/models/checkpoints
    cd /opt/ComfyUI/models/checkpoints
    wget -q --progress=bar:force -O v1-5-pruned-emaonly.ckpt.tmp \
        "https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.ckpt"
    if [ -f "v1-5-pruned-emaonly.ckpt.tmp" ]; then
        mv v1-5-pruned-emaonly.ckpt.tmp v1-5-pruned-emaonly.ckpt
        echo "✅ SD 1.5 checkpoint downloaded"
    fi
else
    echo "✅ SD 1.5 checkpoint already exists"
fi

# Setup custom nodes
echo "Setting up custom nodes..."
cd /opt/ComfyUI/custom_nodes

# Remove problematic ComfyUI Manager if it exists
if [ -d "ComfyUI-Manager" ]; then
    echo "🗑️ Removing problematic ComfyUI Manager..."
    rm -rf ComfyUI-Manager
fi

# Install CogVideo nodes with smart caching
if [ -d "ComfyUI-CogVideoXWrapper" ] && [ -f "$NODES_CACHE_FILE" ]; then
    echo "✅ CogVideoX wrapper already installed and cached"
else
    echo "📥 Installing CogVideoX wrapper..."
    rm -rf ComfyUI-CogVideoXWrapper 2>/dev/null || true
    git clone --depth 1 https://github.com/kijai/ComfyUI-CogVideoXWrapper.git
    if [ $? -eq 0 ]; then
        echo "$(date)" > "$NODES_CACHE_FILE"
        echo "✅ CogVideoX wrapper installed and cached"
    fi
fi

# Install custom node requirements
echo "Installing custom node requirements..."
for dir in */; do
    if [ ! -d "$dir" ]; then
        continue
    fi

    if [ -f "$dir/requirements.txt" ]; then
        HASH_FILE="$dir/.requirements_hash"
        INSTALLED_FILE="$dir/.requirements_installed"

        if [ -f "$HASH_FILE" ] && [ -f "$INSTALLED_FILE" ]; then
            echo "✅ Requirements already installed for $dir"
        else
            echo "📦 Installing requirements for $dir"
            pip install -r "$dir/requirements.txt" 2>/dev/null
            if [ $? -eq 0 ]; then
                touch "$HASH_FILE"
                touch "$INSTALLED_FILE"
                echo "✅ Requirements installed for $dir"
            fi
        fi
    fi
done

# Model summary
echo "🎬 Model Summary:"
if [ "$COGVIDEO_2B_READY" = "true" ]; then
    echo "  ✅ CogVideoX-2b: Ready (cached)"
else
    echo "  ❌ CogVideoX-2b: Missing/Invalid"
fi

if [ "$COGVIDEO_5B_READY" = "true" ]; then
    echo "  ✅ CogVideoX-5b: Ready (cached)"
else
    echo "  ❌ CogVideoX-5b: Missing/Invalid"
fi

if [ "$T5_READY" = "true" ]; then
    echo "  ✅ T5 Encoder: Ready (cached)"
else
    echo "  ❌ T5 Encoder: Missing/Invalid"
fi

if check_model "$SD15_FILE" 3000000000 >/dev/null 2>&1; then
    echo "  ✅ SD 1.5 Checkpoint: Ready (cached)"
else
    echo "  ❌ SD 1.5 Checkpoint: Missing/Invalid"
fi

# GPU check
echo "🎮 GPU Check:"
python3 -c "import torch; print(f'GPU Available: {torch.cuda.is_available()}'); print(f'PyTorch Version: {torch.__version__}'); print(f'CUDA Version: {torch.version.cuda}')"
echo "💡 Compare with working Stable Diffusion container PyTorch version"

# Complete cache summary
echo "📊 Complete Cache Summary:"
echo "  Dependencies:"
[ "$SKIP_DEPS_INSTALL" = true ] && echo "    ✅ Core packages: Cached (skip install)" || echo "    📦 Core packages: Fresh install"
[ -f "$ROCM_CACHE_FILE" ] && echo "    ✅ PyTorch ROCm: Cached (skip install)" || echo "    📦 PyTorch ROCm: Fresh install"
[ -f "$NODES_CACHE_FILE" ] && echo "    ✅ CogVideo nodes: Cached (skip clone)" || echo "    📦 CogVideo nodes: Fresh install"
echo "  Models:"
[ "$COGVIDEO_2B_READY" = "true" ] && echo "    ✅ CogVideoX-2b: Cached (~3.2GB saved)" || echo "    ❌ CogVideoX-2b: Missing"
[ "$COGVIDEO_5B_READY" = "true" ] && echo "    ✅ CogVideoX-5b: Cached (~9.0GB saved)" || echo "    ❌ CogVideoX-5b: Missing"
[ "$T5_READY" = "true" ] && echo "    ✅ T5 Encoder: Cached (~1GB saved)" || echo "    ❌ T5 Encoder: Missing"

echo "  Container → Host Path Mapping:"
echo "    📁 /app/cache/pip → ./caches/cogvideo-pip/"
echo "    📁 /app/cache/huggingface → ./caches/cogvideo-huggingface/"
echo "    📁 /opt/ComfyUI/models → ./cogvideo-models/"
echo "    📁 /opt/ComfyUI/output → ./cogvideo-outputs/"

echo "🚀 Starting ComfyUI with CogVideo support..."
echo "📍 ComfyUI will be available at: http://localhost:8190"
echo "📍 Or via Traefik at: http://cogvideo.askb.dev"
echo ""
if [ "$T5_READY" = "false" ]; then
    echo "⚠️  Known Issues to Check:"
    echo "   🔧 T5 Encoder needs re-download (0 byte file detected)"
    echo ""
fi

echo "🔧 Final working directory fix..."
export PYTHONPATH="/opt/ComfyUI:$PYTHONPATH"
cd /opt/ComfyUI
pwd
ls -la main.py

# Verify basic ComfyUI structure and model detection fix
echo "🔍 Testing ComfyUI structure and model detection fix..."
if [ -f "/opt/ComfyUI/main.py" ]; then
    echo "✅ main.py found"
else
    echo "❌ main.py missing"
fi

if [ -d "/opt/ComfyUI/models/checkpoints" ]; then
    echo "✅ Checkpoints directory exists"
    ls -la /opt/ComfyUI/models/checkpoints/ | head -3

    # Check if the checkpoint is accessible
    if [ -f "/opt/ComfyUI/models/checkpoints/v1-5-pruned-emaonly.ckpt" ]; then
        echo "✅ v1-5-pruned-emaonly.ckpt found and accessible"
    else
        echo "❌ v1-5-pruned-emaonly.ckpt not found"
    fi
else
    echo "❌ Checkpoints directory missing"
fi

# Verify folder_paths.py was modified correctly
if [ -f "/opt/ComfyUI/folder_paths.py" ]; then
    echo "✅ folder_paths.py exists"
    if grep -q "/opt/ComfyUI" /opt/ComfyUI/folder_paths.py; then
        echo "✅ folder_paths.py contains correct runtime paths"
    else
        echo "⚠️ folder_paths.py might not be properly fixed"
    fi
else
    echo "❌ folder_paths.py missing"
fi

echo "🎬 Starting ComfyUI with conservative settings for AMD RX 6800M..."

# Wait a moment for file system changes to settle
sleep 2

echo "🚀 Attempting GPU mode with conservative memory settings..."
exec python3 main.py --listen 0.0.0.0 --port 8190 --cpu-vae --lowvram --use-pytorch-cross-attention --disable-auto-launch
