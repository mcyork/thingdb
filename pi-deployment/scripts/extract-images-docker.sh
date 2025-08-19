#!/bin/bash

echo "🖼️ Extracting images from database via Docker..."

# Create a Python script to run inside the container
cat > /tmp/extract-images.py << 'EOF'
import psycopg2
import os

# Connect to database
conn = psycopg2.connect(
    host='localhost',
    database='docker_dev', 
    user='docker',
    password='docker'
)
cursor = conn.cursor()

# Create output directory in container
os.makedirs('/tmp/pi-images', exist_ok=True)

# Get all images
cursor.execute("""
    SELECT id, image_data, thumbnail_data, preview_data, content_type
    FROM images 
    ORDER BY id
""")

images = cursor.fetchall()
print(f"Found {len(images)} images to extract")

for row in images:
    image_id = row[0]
    
    # Determine extension
    content_type = row[4] or 'image/jpeg'
    ext = '.jpg'
    if 'png' in content_type:
        ext = '.png'
    elif 'gif' in content_type:
        ext = '.gif'
    
    # Save original image
    if row[1]:
        with open(f'/tmp/pi-images/image_{image_id}{ext}', 'wb') as f:
            f.write(row[1])
        print(f"  Extracted image_{image_id}{ext}")
    
    # Save thumbnail
    if row[2]:
        with open(f'/tmp/pi-images/thumbnail_{image_id}{ext}', 'wb') as f:
            f.write(row[2])
    
    # Save preview if exists
    if row[3]:
        with open(f'/tmp/pi-images/original_{image_id}{ext}', 'wb') as f:
            f.write(row[3])

print(f"✅ Extracted {len(images)} images to /tmp/pi-images")
EOF

# Copy script to container and run it
docker cp /tmp/extract-images.py docker-flask-app-1:/tmp/extract-images.py
docker-compose -f docker/docker-compose-dev.yml exec flask-app python3 /tmp/extract-images.py

# Copy extracted images back to host
echo "📥 Copying images from container to host..."
docker cp docker-flask-app-1:/tmp/pi-images/. pi-deployment/data/images/

# Count extracted files
IMAGE_COUNT=$(find pi-deployment/data/images -type f 2>/dev/null | wc -l)
echo "✅ Extracted $IMAGE_COUNT image files to pi-deployment/data/images/"