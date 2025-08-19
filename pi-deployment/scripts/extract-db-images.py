#!/usr/bin/env python3
"""
Extract images from PostgreSQL database to filesystem for Pi deployment
"""
import os
import sys
import psycopg2
from psycopg2.extras import RealDictCursor

def extract_images(db_config, output_dir):
    """Extract all images from database to filesystem"""
    
    # Create output directory
    os.makedirs(output_dir, exist_ok=True)
    
    # Connect to database
    conn = psycopg2.connect(**db_config)
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    
    # Get all images
    cursor.execute("""
        SELECT id, filename, image_data, thumbnail_data, preview_data, content_type
        FROM images 
        ORDER BY id
    """)
    
    images = cursor.fetchall()
    print(f"Found {len(images)} images to extract")
    
    for image in images:
        image_id = image['id']
        filename = image['filename']
        content_type = image['content_type']
        
        # Determine file extension from content type
        ext_map = {
            'image/jpeg': '.jpg',
            'image/jpg': '.jpg',
            'image/png': '.png',
            'image/gif': '.gif',
            'image/webp': '.webp'
        }
        ext = ext_map.get(content_type, '.jpg')
        
        # Extract original image
        if image['image_data']:
            image_path = os.path.join(output_dir, f"image_{image_id}{ext}")
            with open(image_path, 'wb') as f:
                f.write(image['image_data'])
            print(f"  ✅ Extracted image_{image_id}{ext}")
        
        # Extract thumbnail
        if image['thumbnail_data']:
            thumb_path = os.path.join(output_dir, f"thumbnail_{image_id}{ext}")
            with open(thumb_path, 'wb') as f:
                f.write(image['thumbnail_data'])
            print(f"  ✅ Extracted thumbnail_{image_id}{ext}")
        
        # Extract preview (if exists)
        if image['preview_data']:
            preview_path = os.path.join(output_dir, f"original_{image_id}{ext}")
            with open(preview_path, 'wb') as f:
                f.write(image['preview_data'])
            print(f"  ✅ Extracted original_{image_id}{ext}")
    
    cursor.close()
    conn.close()
    
    print(f"\n✅ Extracted {len(images)} images to {output_dir}")

def main():
    # Database configuration
    db_config = {
        'host': 'localhost',
        'database': 'docker_dev',
        'user': 'docker',
        'password': 'docker',
        'port': 5432
    }
    
    # Output directory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    pi_deployment_dir = os.path.dirname(script_dir)
    output_dir = os.path.join(pi_deployment_dir, 'data', 'images')
    
    print("🖼️ Extracting images from database for Pi deployment...")
    print(f"Database: {db_config['host']}:{db_config['port']}/{db_config['database']}")
    print(f"Output: {output_dir}")
    
    try:
        extract_images(db_config, output_dir)
    except Exception as e:
        print(f"❌ Error extracting images: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()