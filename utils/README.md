# AI Services Utilities

This directory contains utility scripts organized by function to help manage and maintain your AI services infrastructure.

## Directory Structure

### 🖥️ GPU Utilities (`/gpu`)

Scripts for GPU setup, diagnostics, and ROCm management:

- `gpu-diagnostics.sh` - Hardware diagnostic script for RX 6800M
- `activate-rx-6800M.sh` - GPU activation utilities
- `host-setup*.sh` - Host system setup for ROCm + Stable Diffusion
- `quick-rocm-fix.sh` - Quick fixes for ROCm issues
- `test-rocm-pytorch.sh` - PyTorch ROCm testing utilities

### 💾 Backup Utilities (`/backup`)

Backup and data management scripts:

- `manual-backup.sh` - Manual N8N backup with SQL dumps
- `simple-backup.sh` - Simple backup utilities
- `space-efficient-backup.sh` - Space-optimized backup
- `ultra-simple-backup.sh` - Minimal backup solution

### 🔧 Maintenance Utilities (`/maintenance`)

System maintenance, cleanup, and performance scripts:

- `n8n_execution_data_analysis.sh` - N8N database analysis
- `vacuum_and_analysis_fix.sh` - Database maintenance
- `execution_data_immediate_cleanup.sh` - Clean execution data
- `ai_agent_memory_fix.sh` - AI agent memory issue fixes
- `n8n-perf-debug.sh` - N8N performance debugging
- `safe-cleanup-scanner.sh` - Safe file cleanup
- `interactive-model-remover.sh` - Interactive model management
- `migrate-to-persistent.sh` - Data migration utilities

### 🚀 Deployment Utilities (`/deployment`)

Docker and deployment management:

- `docker-rebuild-and-start.sh` - Complete rebuild and restart
- `docker-log-analyzer.sh` - Docker log analysis
- `fix_video_ownership.sh` - Fix video file permissions

### 📊 Monitoring Utilities (`/monitoring`)

System monitoring and analysis:

- `wan21-model-analyser.sh` - Model analysis for Wan2.1
- `complete-model-analysis.sh` - Comprehensive model analysis
- `video-services-manager.sh` - Video services monitoring

## Usage

Make scripts executable before running:

```bash
chmod +x utils/category/script-name.sh
./utils/category/script-name.sh
```

## Safety Notes

- Always review scripts before running them
- Most maintenance scripts require the services to be running
- Backup scripts should be run regularly
- GPU scripts are optimized for AMD RX 6800M hardware

## Environment Variables

Many scripts use these environment variables:

- `POSTGRES_PASSWORD` - Database password
- `POSTGRES_USER` - Database user
- `POSTGRES_DB` - Database name
- `COMPOSE_PROJECT_NAME` - Docker Compose project name
