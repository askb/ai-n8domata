#!/bin/bash

echo "🔗 AI Automata Data Directory Setup"
echo "==================================="

# This script creates the necessary data directories and symlinks
# for the AI Automata platform to function properly.

# Default data root - change this to your preferred location
DATA_ROOT="${DATA_ROOT:-/data/n8n/project}"

echo "Using data root: $DATA_ROOT"
echo ""

# Create base data directories if they don't exist
echo "📁 Creating base data directories..."
mkdir -p "$DATA_ROOT"/{backups,caches,daily-backups,data,postgres-data,videos}
mkdir -p "$DATA_ROOT"/{wan21-data,wan21-outputs,wan21-models,wan21-custom-nodes}
mkdir -p "$DATA_ROOT"/{cogvideo-data,cogvideo-outputs,cogvideo-custom-nodes}
mkdir -p "$DATA_ROOT"/{stable-diffusion-data,stable-diffusion-extensions,stable-diffusion-models,stable-diffusion-outputs}
mkdir -p "$DATA_ROOT"/{svd-data,svd-models,svd-outputs,svd-workflows}
mkdir -p "$DATA_ROOT"/comfyui-install

echo "✅ Base directories created"

# Create symlinks if they don't exist
echo ""
echo "🔗 Creating symlinks..."

create_link() {
    local target="$1"
    local link="$2"

    if [ ! -e "$link" ]; then
        ln -sf "$target" "$link"
        echo "  ✅ $link -> $target"
    else
        echo "  ⏭️  $link (already exists)"
    fi
}

# Core data directories
create_link "$DATA_ROOT/backups" "backups"
create_link "$DATA_ROOT/caches" "caches"
create_link "$DATA_ROOT/daily-backups" "daily-backups"
create_link "$DATA_ROOT/data" "data"
create_link "$DATA_ROOT/postgres-data" "postgres-data"
create_link "$DATA_ROOT/videos" "videos"

# WAN21 Video service
create_link "$DATA_ROOT/wan21-data" "wan21-data"
create_link "$DATA_ROOT/wan21-outputs" "wan21-outputs"
create_link "$DATA_ROOT/wan21-models" "wan21-models"
create_link "$DATA_ROOT/wan21-custom-nodes" "wan21-custom-nodes"

# CogVideo service
create_link "$DATA_ROOT/cogvideo-data" "cogvideo-data"
create_link "$DATA_ROOT/cogvideo-outputs" "cogvideo-outputs"
create_link "$DATA_ROOT/cogvideo-custom-nodes" "cogvideo-custom-nodes"

# Stable Diffusion service
create_link "$DATA_ROOT/stable-diffusion-data" "stable-diffusion-data"
create_link "$DATA_ROOT/stable-diffusion-extensions" "stable-diffusion-extensions"
create_link "$DATA_ROOT/stable-diffusion-models" "stable-diffusion-models"
create_link "$DATA_ROOT/stable-diffusion-outputs" "stable-diffusion-outputs"

# Stable Video Diffusion
create_link "$DATA_ROOT/svd-data" "svd-data"
create_link "$DATA_ROOT/svd-models" "svd-models"
create_link "$DATA_ROOT/svd-outputs" "svd-outputs"
create_link "$DATA_ROOT/svd-workflows" "svd-workflows"

# ComfyUI installation
create_link "$DATA_ROOT/comfyui-install" "comfyui-install"

echo ""
echo "🎉 Setup completed successfully!"
echo ""
echo "📝 Next steps:"
echo "1. Copy .env.example to .env and configure your environment variables"
echo "2. Run: docker compose --profile core up -d"
echo "3. Visit http://localhost:5678 for N8N interface"
echo ""
echo "📖 For detailed setup instructions, see GETTING_STARTED.md"
