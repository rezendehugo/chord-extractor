# Comprehensive Docker Guide for Chord Extractor

## What is Docker?

Docker is a **containerization platform** that packages your entire application with all its dependencies into a single portable unit. Think of it as a lightweight virtual machine.

### Why Docker for this project?
- **No dependency hell**: Python 3.8 + Node 20 + ffmpeg all pre-installed
- **Consistency**: Works the same on Linux, macOS, Windows
- **Isolation**: Doesn't interfere with your system Python/Node
- **Easy deployment**: Just one `docker-compose up` command

---

## Architecture: Multi-Stage Build

Your Dockerfile uses a **professional multi-stage build** strategy:

```
┌──────────────────────────────────────────┐
│  STAGE 1: Node.js Build Environment      │
│  - npm ci (install dependencies)         │
│  - npm run build (compile React → dist/) │
│  - Result: Static HTML/CSS/JS files      │
│  - Temporary (~600MB, discarded after)   │
└───────────────┬──────────────────────────┘
                │
         ┌──────┴──────┐
         │ Copy dist/  │
         │ folder only │
         └──────┬──────┘
                │
┌───────────────▼──────────────────────────┐
│  STAGE 2: Python Runtime (Final Image)   │
│  - Base: python:3.8-slim (~150MB)        │
│  - System packages (libsndfile1, ffmpeg) │
│  - Python dependencies (chord-extractor) │
│  - App code (chord.py)                   │
│  - Final size: ~1GB (includes frontend)  │
└──────────────────────────────────────────┘
```

**Benefit**: Node.js is NOT in the final image = saves 300MB!

---

## Step-by-Step Breakdown

### Step 1: Frontend Build (Stage 1)
```dockerfile
FROM node:20-slim AS frontend-builder
```
- Starts with Node.js 20 (slim = minimal, no extra tools)
- Named "frontend-builder" so we can reference it later

```dockerfile
COPY package*.json ./
RUN npm ci
```
- `package*.json` = package.json AND package-lock.json
- `npm ci` = clean install (deterministic, better than `npm install`)

```dockerfile
RUN npm run build
```
- Runs the Vite build process
- Creates optimized static files in `dist/` folder

### Step 2: Python Runtime (Stage 2)
```dockerfile
FROM python:3.8-slim
```
- Fresh Python 3.8 image (Node.js from Stage 1 is gone!)
- "slim" = minimal: ~150MB vs ~900MB for full image

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsndfile1 \
    ffmpeg \
    libvamp0
```

**Why each package?**
- `libsndfile1`: Audio I/O (WAV, FLAC reading/writing)
- `ffmpeg`: Convert video formats (YouTube downloads)
- `libvamp0`: VAMP plugin system (Chordino extracts chords using this)

```dockerfile
COPY --from=frontend-builder /app/dist ./dist
```
- **Key line**: Copies built React files from Stage 1
- This is why multi-stage is powerful!

### Step 3: Application Setup
```dockerfile
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
```
- `--no-cache-dir`: Don't store pip's cache (saves space)

```dockerfile
COPY chord.py ./
```
- Copy the main Python script

### Step 4: Health & Execution
```dockerfile
EXPOSE 8000
```
- Documents which port the app uses (informational)

```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD python -c "import http.client; ..."
```
- Checks if app is still running every 30 seconds
- If 3 checks fail, container marked as unhealthy
- docker-compose can restart unhealthy containers

```dockerfile
CMD ["python", "chord.py", "sample_audio.mp3"]
```
- Default command (you can override when running)

---

## Docker Compose Configuration

```yaml
version: '3.8'
services:
  chord-extractor:
    build:
      context: .          # Build from current directory
      dockerfile: Dockerfile
    ports:
      - "8000:8000"       # Host port 8000 → Container port 8000
    volumes:
      - ./uploads:/app/uploads    # Bind mount (share files)
      - ./dist:/app/dist          # Output files
    environment:
      - PYTHONUNBUFFERED=1        # See Python output immediately
    restart: unless-stopped        # Auto-restart if crashes
```

### Volumes Explained

**What is a volume?** A bridge between your computer and the container's filesystem.

```
Your Machine              Docker Container
┌────────────┐            ┌────────────┐
│ ./uploads/ │ ◄───────► │ /app/uploads│  (same files!)
│ ./dist/    │ ◄───────► │ /app/dist   │
└────────────┘            └────────────┘
```

- When chord.py writes to `/app/dist/chords.json` in the container
- It appears as `./dist/chords.json` on your machine
- **Persists** even if you delete the container

---

## .dockerignore File

Like `.gitignore`, but for Docker builds. Tells Docker to skip certain files:

```
node_modules          # Don't copy into container (npm ci will reinstall)
.git                  # Not needed in container
__pycache__           # Python cache (will be recreated)
.env                  # Secrets (set via environment variables instead)
```

**Why?** Speeds up builds and keeps images smaller.

---

## How to Use

### Option 1: Docker Compose (Recommended)

```bash
# Build image and start container
docker-compose up

# Or run in background
docker-compose up -d

# View logs
docker-compose logs -f

# Stop everything
docker-compose down
```

### Option 2: Docker CLI (Manual)

```bash
# Build image
docker build -t chord-extractor:latest .

# Run container
docker run -it \
  -p 8000:8000 \
  -v $(pwd)/uploads:/app/uploads \
  -v $(pwd)/dist:/app/dist \
  chord-extractor:latest
```

### Access the App

Open: `http://localhost:8000`

---

## Common Docker Commands Reference

```bash
# Images (like templates)
docker build -t name:tag .         # Build image
docker images                      # List images
docker rmi image_id                # Delete image

# Containers (running instances)
docker run -it image_name          # Run container interactively
docker ps                          # List running containers
docker ps -a                       # List all containers
docker logs container_id           # View output
docker exec -it container_id bash  # SSH into running container
docker stop container_id           # Stop container
docker rm container_id             # Delete container

# Docker Compose
docker-compose up                  # Start services
docker-compose up -d               # Start in background
docker-compose logs -f             # View logs
docker-compose down                # Stop & remove containers
docker-compose build --no-cache    # Rebuild from scratch

# Cleanup
docker system prune -a             # Remove all unused images/containers
```

---

## Troubleshooting

### Issue: Container exits immediately

```bash
docker-compose logs chord-extractor
```

**Common cause**: `chord.py` requires an audio file argument.

**Fix**: Modify `chord.py` line 223 to provide a default file or handle missing args:
```python
args.file = args.file or "sample_audio.mp3"
```

### Issue: "Port 8000 already in use"

**Solution**: Change port in `docker-compose.yml`:
```yaml
ports:
  - "8001:8000"  # Now access at http://localhost:8001
```

### Issue: "Permission denied" when accessing uploaded files

```bash
chmod 777 uploads/
```

### Issue: Image is too large (takes forever to build)

```bash
# Use build cache (don't rebuild unchanged layers)
docker build -t name:tag .

# Or start fresh
docker build -t name:tag --no-cache .
```

### Issue: Want to debug inside the container

```bash
docker-compose run --rm chord-extractor bash
# Now you're inside the container - explore the filesystem!
```

---

## Best Practices Used in Your Setup

✅ **Multi-stage builds** - Minimize final image size  
✅ **Slim base images** - python:3.8-slim instead of full image  
✅ **Layer caching** - Dependencies cached, only rebuild when changed  
✅ **.dockerignore** - Faster builds by excluding unnecessary files  
✅ **Explicit versions** - `node:20-slim`, `python:3.8-slim` (reproducible)  
✅ **Health checks** - Auto-restart unhealthy containers  
✅ **Volumes** - Easy file sharing between host & container  
✅ **Environment variables** - PYTHONUNBUFFERED for immediate output  

---

## Advanced: Optimizing Build Speed

**Dockerfile layer order matters** (earlier = cached longer):

```dockerfile
# ❌ SLOW: Code changes invalidate everything below
COPY . .
RUN pip install -r requirements.txt

# ✅ FAST: If only code changes, Python deps cached
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
```

---

## Next Steps

1. **Local testing**: `docker-compose up`
2. **GitHub Actions CI/CD**: Auto-build on push
3. **Docker Hub**: Push image for sharing
4. **Production deployment**: Use on AWS/Google Cloud/DigitalOcean

---

## Resources

- **Docker Docs**: https://docs.docker.com
- **Dockerfile Best Practices**: https://docs.docker.com/develop/develop-images/dockerfile_best-practices/
- **Multi-stage Builds**: https://docs.docker.com/build/building/multi-stage/
- **Docker Compose**: https://docs.docker.com/compose/
