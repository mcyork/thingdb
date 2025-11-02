FROM python:3.13-slim

# Install system dependencies (PostgreSQL + build tools)
RUN apt-get update && apt-get install -y \
    postgresql \
    postgresql-contrib \
    libpq-dev \
    python3-dev \
    build-essential \
    git \
    curl \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy project files
COPY pyproject.toml .
COPY src/ src/
COPY docker/entrypoint.sh /entrypoint.sh

# Install ThingDB package
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -e .

# Setup PostgreSQL
RUN mkdir -p /var/lib/postgresql/data && \
    chown -R postgres:postgres /var/lib/postgresql && \
    chmod 700 /var/lib/postgresql/data

# Create directories for runtime data
RUN mkdir -p /var/lib/thingdb/cache/models /app/src/uploads && \
    chmod 755 /var/lib/thingdb/cache/models

# Make entrypoint executable
RUN chmod +x /entrypoint.sh

# Expose port
EXPOSE 5000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:5000/ || exit 1

# Start everything
ENTRYPOINT ["/entrypoint.sh"]
