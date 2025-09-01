#!/bin/bash
# Docker rebuild and start script
# This handles the build issues and starts all services

cd /data/n8n/project || {
    echo "❌ Cannot access /data/n8n/project"
    exit 1
}

echo "🔧 Starting Docker rebuild and deployment..."

# Clean any problematic build state
echo "1. Cleaning Docker build cache..."
docker builder prune -af

# Stop any running services
echo "2. Stopping existing services..."
docker compose down 2>/dev/null || true

# Build custom images from scratch
echo "3. Building custom images (no cache)..."
echo "   Building intelligent-cropper..."
docker compose build intelligent-cropper --no-cache --progress=plain

echo "   Building n8n..."
docker compose build n8n --no-cache --progress=plain

echo "   Building redis-monitor..."
docker compose build redis-monitor --no-cache --progress=plain

echo "   Building n8n-autoscaler..."
docker compose build n8n-autoscaler --no-cache --progress=plain 2>/dev/null || echo "   Skipping n8n-autoscaler (not found)"

echo "   Building n8n-webhook..."
docker compose build n8n-webhook --no-cache --progress=plain 2>/dev/null || echo "   Skipping n8n-webhook (not found)"

echo "   Building n8n-worker..."
docker compose build n8n-worker --no-cache --progress=plain 2>/dev/null || echo "   Skipping n8n-worker (not found)"

# Start all services
echo "4. Starting all services..."
docker compose up -d

# Wait a moment for services to initialize
echo "5. Waiting for services to start..."
sleep 10

# Check status
echo "6. Service status:"
docker compose ps

echo ""
echo "✅ Deployment complete!"
echo ""
echo "🌐 Test your services:"
echo "   n8n:              http://localhost:5678"
echo "   Baserow:          http://localhost:85"
echo "   Stable Diffusion: http://localhost:7860"
echo "   SVD:              http://localhost:8188"
echo ""
echo "📊 Check status: docker compose ps"
echo "📋 View logs:    docker compose logs -f"
