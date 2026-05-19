# Stage 1: Build the React frontend
# This stage builds your Vite/React app into static files
FROM node:20-slim AS frontend-builder

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install Node dependencies
RUN npm ci

# Copy source code
COPY src ./src
COPY public ./public
COPY index.html vite.config.js eslint.config.js ./

# Build the React app - outputs to dist/
RUN npm run build


# Stage 2: Build the Python backend with Vamp plugins
# This is the main runtime image
FROM python:3.8-slim

WORKDIR /app

# Install system dependencies required by chord-extractor and audio processing
# - libsndfile1: Required for audio file handling
# - ffmpeg: Required for audio/video conversion
# - ca-certificates: For HTTPS connections
# - curl: For downloading Vamp plugins
# - libc6: C library (usually present but ensuring)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsndfile1 \
    ffmpeg \
    ca-certificates \
    curl \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Create Vamp plugin directory
RUN mkdir -p /usr/local/lib/vamp

# Download and install Vamp plugins (nnls-chroma and chordino)
# Using pre-compiled Linux 64-bit binaries from vamp-plugins.org
RUN cd /tmp && \
    echo "Downloading Vamp Plugin Pack..." && \
    wget -q https://vamp-plugins.org/download/vamp-plugin-pack-2.7.1-linux64.tar.bz2 -O vamp-plugins.tar.bz2 && \
    echo "Extracting plugins..." && \
    tar -xjf vamp-plugins.tar.bz2 && \
    echo "Installing .so files to /usr/local/lib/vamp..." && \
    find vamp-plugin-pack-2.7.1-linux64 -name "*.so" -exec cp {} /usr/local/lib/vamp/ \; && \
    echo "Verifying nnls-chroma plugin..." && \
    ls -la /usr/local/lib/vamp/ && \
    rm -rf vamp-plugins.tar.bz2 vamp-plugin-pack-2.7.1-linux64

# Set VAMP_PATH environment variable to ensure plugins are found
ENV VAMP_PATH=/usr/local/lib/vamp

# Copy Python requirements
COPY requirements.txt ./

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy Python application code
COPY chord.py ./

# Copy the built frontend from Stage 1
COPY --from=frontend-builder /app/dist ./dist

# Create a directory for temporary files (audio/video uploads)
RUN mkdir -p /app/uploads && chmod 777 /app/uploads

# Expose the port the app runs on
EXPOSE 8000

# Health check to verify the container is healthy
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import http.client; http.client.HTTPConnection('localhost', 8000).request('GET', '/'); exit(0)" || exit 1

# Run the application
CMD ["python", "chord.py", "sample_audio.mp3"]
