#!/bin/bash

echo "🐳 Building Inventory Pi Image with Docker + pi-gen"
echo "=================================================="

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDER_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$BUILDER_DIR")"

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker Desktop and try again."
    exit 1
fi

# Configuration
PI_GEN_DIR="$BUILDER_DIR/pi-gen"
OUTPUT_DIR="$BUILDER_DIR/output"
DOCKER_IMAGE="pi-gen-builder"

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "🏗️ Building Docker image for pi-gen..."

# Create Dockerfile for pi-gen
cat > "$PI_GEN_DIR/Dockerfile" << 'DOCKERFILE'
FROM debian:bookworm

# Install pi-gen dependencies
RUN apt-get update && apt-get install -y \
    quilt parted qemu-user-static debootstrap zerofree \
    dosfstools libcap2-bin kmod pigz arch-test \
    git curl wget xz-utils sudo build-essential \
    && rm -rf /var/lib/apt/lists/*

# Create build user
RUN useradd -m -s /bin/bash builder && \
    echo 'builder ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Set working directory
WORKDIR /pi-gen

# Copy pi-gen source
COPY . /pi-gen/

# Set ownership
RUN chown -R builder:builder /pi-gen

# Switch to builder user
USER builder

# Default command
CMD ["./build-docker.sh"]
DOCKERFILE

# Create Docker build script
cat > "$PI_GEN_DIR/build-docker.sh" << 'BUILD_DOCKER'
#!/bin/bash

echo "🚀 Starting pi-gen build inside Docker..."

# Ensure we're in the right directory
cd /pi-gen

# Check if config exists
if [ ! -f config ]; then
    echo "❌ No config file found!"
    exit 1
fi

# Run the build
echo "Building with configuration:"
cat config
echo ""

./build.sh

echo "✅ Build completed!"
echo "📦 Listing output files:"
ls -la deploy/ || echo "No deploy directory found"
BUILD_DOCKER

chmod +x "$PI_GEN_DIR/build-docker.sh"

# Build the Docker image
echo "🔨 Building Docker image (this may take a few minutes)..."
cd "$PI_GEN_DIR"
docker build -t "$DOCKER_IMAGE" .

if [ $? -ne 0 ]; then
    echo "❌ Docker build failed"
    exit 1
fi

echo "🚀 Running pi-gen build in Docker container..."
echo "This will take 30-60 minutes..."

# Run the build in Docker with volume mount for output
docker run --rm --privileged \
    -v "$PI_GEN_DIR/deploy:/pi-gen/deploy" \
    -v "$PROJECT_ROOT:/project-root:ro" \
    "$DOCKER_IMAGE"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Build completed successfully!"
    echo "📦 Output images:"
    ls -la "$PI_GEN_DIR/deploy/"*.img* 2>/dev/null || echo "No image files found"
    
    # Copy images to our output directory
    if ls "$PI_GEN_DIR/deploy/"*.img* >/dev/null 2>&1; then
        cp "$PI_GEN_DIR/deploy/"*.img* "$OUTPUT_DIR/"
        echo "📁 Images copied to: $OUTPUT_DIR/"
    fi
else
    echo "❌ Build failed"
    echo "💡 Check Docker container logs above for details"
fi