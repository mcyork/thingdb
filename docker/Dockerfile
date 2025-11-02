FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    postgresql postgresql-contrib \
    nginx \
    supervisor \
    libpq-dev \
    gcc \
    curl \
    wget \
    openssl \
    && rm -rf /var/lib/apt/lists/*

# Create application user
RUN useradd -r -s /bin/bash -m inventory

# Set working directory
WORKDIR /var/lib/inventory/app

# Copy requirements and install Python dependencies
COPY requirements/ requirements/
RUN pip install --no-cache-dir -r requirements/base-requirements.txt
RUN pip install --no-cache-dir -r requirements/ml-requirements.txt

# Create virtual environment
RUN python3 -m venv /var/lib/inventory/app/venv
RUN /var/lib/inventory/app/venv/bin/pip install --upgrade pip
RUN /var/lib/inventory/app/venv/bin/pip install --no-cache-dir -r requirements/base-requirements.txt
RUN /var/lib/inventory/app/venv/bin/pip install --no-cache-dir -r requirements/ml-requirements.txt
RUN /var/lib/inventory/app/venv/bin/pip install gunicorn

# Copy application code
COPY src/ .

# Create necessary directories
RUN mkdir -p /var/lib/inventory/images \
    /var/lib/inventory/ml_cache \
    /var/lib/inventory/ssl \
    /var/lib/inventory/config \
    /var/lib/postgresql/data \
    /var/log/supervisor \
    /var/log/nginx \
    /var/log/postgresql

# Set permissions
RUN chown -R inventory:inventory /var/lib/inventory
RUN chown -R postgres:postgres /var/lib/postgresql
RUN chown -R postgres:postgres /var/log/postgresql

# Copy configuration files
COPY docker/nginx.conf /etc/nginx/nginx.conf
COPY docker/postgresql.conf /etc/postgresql/postgresql.conf
COPY docker/init-db.sh /usr/local/bin/init-db.sh
COPY docker/startup.sh /usr/local/bin/startup.sh

# Make scripts executable
RUN chmod +x /usr/local/bin/init-db.sh
RUN chmod +x /usr/local/bin/startup.sh

# Generate SSL certificates
RUN openssl req -x509 -newkey rsa:4096 -keyout /var/lib/inventory/ssl/key.pem \
    -out /var/lib/inventory/ssl/cert.pem -days 365 -nodes \
    -subj '/CN=inventory.local' > /dev/null 2>&1
RUN chmod 600 /var/lib/inventory/ssl/*
RUN chown inventory:inventory /var/lib/inventory/ssl/*

# Expose ports
EXPOSE 80 443

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

# Start all services
CMD ["/usr/local/bin/startup.sh"]
