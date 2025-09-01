# Getting Started - N8N AI Services Platform

Welcome to the N8N AI Services Platform! This guide will walk you through setting up your first automation workflow with AI capabilities in just a few minutes.

## 🎯 What You'll Build

By the end of this tutorial, you'll have:

- ✅ A fully functional N8N automation platform
- ✅ Auto-scaling workers that adapt to your workload
- ✅ AI services for video generation and text processing
- ✅ Real-time monitoring and observability
- ✅ Your first workflow with AI integration

## ⏱️ Time Required

- **Basic Setup:** 10-15 minutes
- **First Workflow:** 5-10 minutes
- **AI Integration:** 10-15 minutes

## 🛠️ Prerequisites Checklist

Before starting, ensure you have:

- [ ] **Docker & Docker Compose v2+** installed ([Installation Guide](https://docs.docker.com/compose/install/))
- [ ] **16GB+ RAM** available (8GB minimum, 32GB+ for AI services)
- [ ] **100GB+ free disk space**
- [ ] **Linux/macOS/WSL2** environment
- [ ] **Internet connection** for downloading images
- [ ] **Cloudflare account** (optional but recommended for secure access)

**Quick Docker Check:**

```bash
docker --version
docker compose version
```

Expected output: `Docker version 24.0+` and `Docker Compose version v2.20+`

## 🚀 Step-by-Step Setup

### Step 1: Download and Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/ai-automata.git
cd ai-automata

# Initialize AI service submodules
git submodule update --init --recursive

# Create Docker network for integrations
docker network create shark

# Verify setup
ls -la
```

You should see files like `docker-compose.yml`, `.env.example`, and directories like `queue-metrics/`, `dynamic-scaler/`.

### Step 2: Configure Environment

```bash
# Copy the example configuration
cp .env.example .env

# Open the configuration file
nano .env  # or use your preferred editor
```

**🔑 Minimum Required Changes:**

1. **Generate a secure encryption key:**

   ```bash
   openssl rand -base64 32
   ```

   Replace `N8N_ENCRYPTION_KEY=REPLACE_WITH_STRONG_KEY`

2. **Set a secure database password:**
   Replace `POSTGRES_PASSWORD=change_me_please`

3. **Configure your domain (if using Cloudflare):**

   ```bash
   N8N_HOST=n8n.yourdomain.com
   N8N_WEBHOOK=webhook.yourdomain.com
   TRAEFIK_HOST=traefik.yourdomain.com
   ```

**💡 Quick Setup (localhost only):**
If you just want to test locally, you can use the defaults and access via `localhost:5678`

### Step 3: Start Core Services

```bash
# Start with core services only (recommended for first run)
docker compose --profile core up -d

# Monitor the startup process
docker compose logs -f n8n-main n8n-queue-metrics n8n-dynamic-scaler
```

**What to expect:**

- Initial setup takes 2-5 minutes
- You'll see services starting up in order
- Look for messages like "Connected to Redis" and "N8N ready"

### Step 4: Verify Everything is Running

```bash
# Check service status
docker compose ps

# Verify health checks
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Health}}"

# Quick connectivity test
curl -I http://localhost:5678
```

**Expected Output:**

- All services should be `Up` or `Up (healthy)`
- N8N should respond with HTTP 200 on port 5678

### Step 5: Access N8N

**Local Access:**
Open your browser to: `http://localhost:5678`

**Domain Access (with Cloudflare):**
Open: `https://n8n.yourdomain.com`

**First Login:**

- N8N will prompt you to create an admin account
- Choose a strong password
- Complete the setup wizard

## 🎯 Create Your First Workflow

### Simple Health Check Workflow

1. **Create a new workflow** in N8N
2. **Add a Schedule Trigger:**
   - Set to run every 5 minutes
3. **Add an HTTP Request node:**
   - Method: GET
   - URL: `http://n8n-queue-metrics:8000/health` (internal service check)
4. **Add a webhook response** (optional)
5. **Save and Activate** the workflow

Watch the auto-scaler logs to see workers scaling based on activity:

```bash
docker compose logs -f n8n-dynamic-scaler
```

### AI-Enhanced Workflow

1. **Add a Webhook Trigger**
2. **Add HTTP Request to AI Agent:**
   - Method: POST  
   - URL: `http://n8n-ai-agent-cpu:8000/process`
   - Body: `{"text": "{{$json.input_text}}", "task": "summarize"}`
3. **Process the AI response**
4. **Return results via webhook**

Test it:

```bash
curl -X POST http://localhost:5678/webhook/your-workflow-id \
  -H "Content-Type: application/json" \
  -d '{"input_text": "This is a long text that needs summarizing..."}'
```

## 📊 Monitor Your Platform

### Queue Metrics Dashboard

```bash
# Watch real-time queue metrics
docker compose logs -f n8n-queue-metrics

# Check queue length manually
docker compose exec redis redis-cli LLEN bull:jobs:wait
```

### Auto-Scaling in Action

```bash
# Monitor scaling decisions
docker compose logs -f n8n-dynamic-scaler

# Watch worker containers scale
watch docker compose ps
```

### Service Health

```bash
# All services health check
docker compose ps --format "table {{.Name}}\t{{.Health}}"

# Resource usage monitoring
docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
```

## 🤖 Enable AI Services

### Add Video Generation

```bash
# Stop current services
docker compose down

# Start with AI services
docker compose --profile core --profile anim up -d

# Monitor AI service startup (takes longer due to model downloads)
docker compose logs -f n8n-short-video-maker-cpu
```

### Test Video Generation API

```bash
# Check if video service is ready
curl http://localhost:3123/health

# Create a simple video (replace with actual API endpoint)
curl -X POST http://localhost:3123/generate \
  -H "Content-Type: application/json" \
  -d '{"prompt": "A beautiful sunset", "duration": 5}'
```

### Integrate AI in N8N Workflows

1. **HTTP Request Node** pointing to `http://n8n-ai-agent-cpu:8000`
2. **Use internal Docker network names** for service communication
3. **Process responses** and chain multiple AI services

## 🔧 Common Customizations

### Increase Auto-Scaling Limits

Edit `.env`:

```bash
MAX_REPLICAS=10                    # More workers for heavy loads
SCALE_UP_QUEUE_THRESHOLD=3         # Scale earlier
POLLING_INTERVAL_SECONDS=15        # Check more frequently
```

Restart services:

```bash
docker compose restart n8n-dynamic-scaler
```

### Add Custom Domains

1. **Configure Cloudflare tunnel** with your subdomains
2. **Update .env** with your domains:

   ```bash
   AI_AGENT_HOST=ai.yourdomain.com
   SHORT_VIDEO_MAKER_HOST=video.yourdomain.com
   ```

3. **Restart Traefik:**

   ```bash
   docker compose restart n8n-traefik
   ```

### Performance Tuning

For high-volume workflows, edit `.env`:

```bash
N8N_CONCURRENCY_PRODUCTION_LIMIT=20    # More tasks per worker
POSTGRES_SHARED_BUFFERS=256MB           # Better database performance
REDIS_MAXMEMORY=2gb                     # More Redis memory
```

## 🚨 Troubleshooting Common Issues

### Services Won't Start

```bash
# Check configuration
docker compose config

# Look for specific errors
docker compose logs service-name

# Check system resources
free -h
df -h
```

### N8N Can't Access Database

```bash
# Verify PostgreSQL
docker compose exec postgres pg_isready -U postgres

# Check credentials match
grep POSTGRES .env
```

### Auto-Scaling Not Working

```bash
# Check queue monitor
docker compose logs n8n-queue-metrics

# Verify scaler logs
docker compose logs n8n-dynamic-scaler

# Test Docker access
docker compose exec n8n-dynamic-scaler docker ps
```

### AI Services Failing

```bash
# Check memory usage
docker stats

# Verify model downloads
docker compose logs n8n-short-video-maker-cpu | grep -i download

# GPU issues (if using GPU services)
docker run --rm --device=/dev/kfd --device=/dev/dri rocm/pytorch:latest rocminfo
```

## 🎉 Next Steps

### Advanced Features to Explore

1. **GPU Acceleration** - Enable ROCm services for faster AI processing
2. **Custom AI Models** - Add your own models to the AI services
3. **Workflow Templates** - Create reusable automation templates
4. **Monitoring Dashboard** - Set up Grafana for advanced metrics
5. **Backup Automation** - Configure automated backups

### Learning Resources

- 📚 [N8N Documentation](https://docs.n8n.io/)
- 🎥 [N8N YouTube Tutorials](https://youtube.com/n8nio)
- 💬 [N8N Community Forum](https://community.n8n.io/)
- 🐳 [Docker Compose Guide](https://docs.docker.com/compose/)

### Community and Support

- 🐛 **Issues:** [GitHub Issues](https://github.com/yourusername/ai-automata/issues)
- 💬 **Discussions:** [GitHub Discussions](https://github.com/yourusername/ai-automata/discussions)
- 📧 **Email:** <support@yourdomain.com>

## 🎯 Success Checklist

After completing this guide, you should have:

- [ ] ✅ N8N platform running and accessible
- [ ] ✅ Auto-scaling working (watch worker containers scale)
- [ ] ✅ At least one workflow created and running
- [ ] ✅ Queue metrics showing activity
- [ ] ✅ AI services responding to requests
- [ ] ✅ Monitoring and logs accessible
- [ ] ✅ Understanding of how to troubleshoot issues

**🎊 Congratulations!** You now have a production-ready N8N platform with AI capabilities!

---

## 📋 Quick Command Reference

```bash
# Start platform
docker compose --profile core up -d

# Stop platform  
docker compose down

# View logs
docker compose logs -f service-name

# Check status
docker compose ps

# Scale manually
docker compose up -d --scale n8n-worker=3

# Update services
docker compose pull && docker compose up -d

# Backup data
docker compose exec n8n-backup /backup-script.sh

# Clean up (⚠️ removes data)
docker compose down -v
```

---

*Need help? Check the main [README.md](README.md) for detailed documentation or open an issue on GitHub.*

**Generated with [Claude Code](https://claude.ai/code)**
