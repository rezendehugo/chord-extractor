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
# - wget: For downloading
# - build-essential: For compiling C/C++ code
# - pkg-config: For finding libraries during compilation
# - libtool, automake, autoconf: Build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsndfile1 \
    ffmpeg \
    ca-certificates \
    wget \
    build-essential \
    pkg-config \
    libtool \
    automake \
    autoconf \
    && rm -rf /var/lib/apt/lists/*

# Create Vamp plugin directory
RUN mkdir -p /usr/local/lib/vamp

# Download, extract, and build Vamp Plugin Pack from source
# Using v2.0 from https://github.com/vamp-plugins/vamp-plugin-pack/archive/refs/tags/v2.0.tar.gz
RUN cd /tmp && \
    echo "Downloading Vamp Plugin Pack v2.0 source..." && \
    wget -q https://github.com/vamp-plugins/vamp-plugin-pack/archive/refs/tags/v2.0.tar.gz -O vamp-plugin-pack-2.0.tar.gz && \
    echo "Extracting source..." && \
    tar -xzf vamp-plugin-pack-2.0.tar.gz && \
    echo "Listing extracted directory..." && \
    ls -la /tmp/ | grep vamp && \
    cd vamp-plugin-pack-v2.0 && \
    echo "Current directory: $(pwd)" && \
    echo "Configuring build..." && \
    ./configure --prefix=/usr/local && \
    echo "Building plugins (this may take a few minutes)..." && \
    make && \
    echo "Installing plugins..." && \
    make install && \
    echo "Verifying installed plugins..." && \
    ls -la /usr/local/lib/vamp/ && \
    cd /tmp && \
    rm -rf vamp-plugin-pack-2.0.tar.gz vamp-plugin-pack-v2.0

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
