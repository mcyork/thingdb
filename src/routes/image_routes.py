"""
Image routes for Flask Inventory Management System
Handles image upload, serving, rotation, and deletion
"""
from flask import Blueprint, request, jsonify, Response
from werkzeug.utils import secure_filename
from database import get_db_connection, return_db_connection
from services.image_service import generate_thumbnail, generate_preview, is_valid_image
from models import thumbnail_cache, image_cache
from utils.helpers import is_valid_guid, generate_etag, get_content_type

image_bp = Blueprint('image', __name__)

@image_bp.route('/upload-image/<guid>', methods=['POST'])
def upload_image(guid):
    """Handle image upload for an item"""
    if not is_valid_guid(guid):
        return 'Invalid GUID', 400
    
    if 'image' not in request.files:
        return 'No image file', 400
    
    file = request.files['image']
    if file.filename == '':
        return 'No selected file', 400
    
    if file:
        filename = secure_filename(file.filename)
        description = request.form.get('description', '')
        
        # Read image data
        raw_image_data = file.read()
        
        if not is_valid_image(raw_image_data):
            return 'Invalid image file', 400
        
        # Generate thumbnails and preview
        thumbnail_data = generate_thumbnail(raw_image_data)
        preview_data = generate_preview(raw_image_data)
        content_type = get_content_type(filename)
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Check if this is the first image (make it primary)
        cursor.execute('SELECT COUNT(*) FROM images WHERE item_guid = %s', (guid,))
        image_count = cursor.fetchone()[0]
        is_primary = (image_count == 0)
        
        # Insert image
        cursor.execute('''
            INSERT INTO images (item_guid, filename, image_data, thumbnail_data, preview_data, 
                              content_type, is_primary, description)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        ''', (guid, filename, raw_image_data, thumbnail_data, preview_data, 
              content_type, is_primary, description))
        
        conn.commit()
        conn.close()
        
        return jsonify({"success": True}), 200

@image_bp.route('/image/<int:image_id>')
def serve_image(image_id):
    """Serve optimized preview image"""
    cache_key = f"image_{image_id}"
    
    # Try cache first
    cached_data = image_cache.get(cache_key)
    if cached_data:
        image_data, etag = cached_data
        if request.headers.get('If-None-Match') == etag:
            return '', 304
        
        # Auto-detect content type
        content_type = 'image/jpeg'
        if image_data and len(image_data) > 20:
            data_bytes = bytes(image_data) if isinstance(image_data, memoryview) else image_data
            if data_bytes.startswith(b'RIFF') and b'WEBP' in data_bytes[:20]:
                content_type = 'image/webp'
        
        response = Response(image_data, mimetype=content_type)
        response.headers['ETag'] = etag
        response.headers['Cache-Control'] = 'public, max-age=3600'
        return response
    
    # Get from database
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('''
        SELECT preview_data, content_type, rotation_degrees, image_data
        FROM images WHERE id = %s
    ''', (image_id,))
    result = cursor.fetchone()
    return_db_connection(conn)
    
    if not result:
        return 'Image not found', 404
    
    preview_data, content_type, rotation_degrees, image_data = result
    
    # Check if preview needs regeneration due to rotation
    if rotation_degrees and rotation_degrees != 0:
        # Regenerate preview with the stored rotation applied
        from services.image_service import generate_preview
        preview_data = generate_preview(image_data, rotation=rotation_degrees)
        if preview_data:
            # Update database with new preview
            conn = get_db_connection()
            cursor = conn.cursor()
            cursor.execute(
                'UPDATE images SET preview_data = %s WHERE id = %s',
                (preview_data, image_id)
            )
            conn.commit()
            return_db_connection(conn)
    
    # Use simple hash for ETag
    etag = f'"{hash(preview_data) % 2**32}"'
    image_cache.set(cache_key, (preview_data, etag))
    
    if request.headers.get('If-None-Match') == etag:
        return '', 304
    
    # Auto-detect content type
    if preview_data and len(preview_data) > 20:
        data_bytes = bytes(preview_data) if isinstance(preview_data, memoryview) else preview_data
        if data_bytes.startswith(b'RIFF') and b'WEBP' in data_bytes[:20]:
            content_type = 'image/webp'
    
    response = Response(preview_data, mimetype=content_type)
    response.headers['ETag'] = etag
    response.headers['Cache-Control'] = 'public, max-age=3600'
    return response

@image_bp.route('/thumbnail/<int:image_id>')
def serve_thumbnail(image_id):
    """Serve optimized thumbnail from cache or database"""
    cache_key = f"thumb_{image_id}"
    
    # Try cache first
    cached_data = thumbnail_cache.get(cache_key)
    if cached_data:
        thumbnail_data, etag = cached_data
        
        # Check if client has cached version
        if request.headers.get('If-None-Match') == etag:
            return '', 304
        
        # Auto-detect WebP content type for generated thumbnails
        content_type = 'image/jpeg'
        if thumbnail_data and len(thumbnail_data) > 20:
            # Convert memoryview to bytes if needed
            data_bytes = bytes(thumbnail_data) if isinstance(thumbnail_data, memoryview) else thumbnail_data
            if data_bytes.startswith(b'RIFF') and b'WEBP' in data_bytes[:20]:
                content_type = 'image/webp'
            
        # Convert memoryview to bytes for Response
        thumbnail_bytes = bytes(thumbnail_data) if isinstance(thumbnail_data, memoryview) else thumbnail_data
        
        response = Response(thumbnail_bytes, mimetype=content_type)
        response.headers['Cache-Control'] = 'public, max-age=1800'  # 30 minutes
        response.headers['ETag'] = etag
        return response
    
    # Cache miss - fetch from database
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute(
        'SELECT thumbnail_data, filename, image_data, rotation_degrees FROM images WHERE id = %s',
        (image_id,)
    )
    result = cursor.fetchone()
    return_db_connection(conn)
    
    if result:
        thumbnail_data, filename, image_data, rotation_degrees = result
        if thumbnail_data:
            # Check if thumbnail needs regeneration due to rotation
            if rotation_degrees and rotation_degrees != 0:
                # Regenerate thumbnail with the stored rotation applied
                from services.image_service import generate_thumbnail
                thumbnail_data = generate_thumbnail(image_data, rotation=rotation_degrees)
                if thumbnail_data:
                    # Update database with new thumbnail
                    conn = get_db_connection()
                    cursor = conn.cursor()
                    cursor.execute(
                        'UPDATE images SET thumbnail_data = %s WHERE id = %s',
                        (thumbnail_data, image_id)
                    )
                    conn.commit()
                    return_db_connection(conn)
            
            # Use simple hash instead of MD5 for speed
            etag = f'"{hash(thumbnail_data) % 2**32}"'
            
            # Store in cache
            thumbnail_cache.set(cache_key, (thumbnail_data, etag))
            
            # Check if client has cached version
            if request.headers.get('If-None-Match') == etag:
                return '', 304
            
            # Auto-detect WebP content type for generated thumbnails  
            content_type = 'image/jpeg'
            if thumbnail_data and len(thumbnail_data) > 20:
                # Convert memoryview to bytes if needed
                data_bytes = bytes(thumbnail_data) if isinstance(thumbnail_data, memoryview) else thumbnail_data
                if data_bytes.startswith(b'RIFF') and b'WEBP' in data_bytes[:20]:
                    content_type = 'image/webp'
                
            # Convert memoryview to bytes for Response
            thumbnail_bytes = bytes(thumbnail_data) if isinstance(thumbnail_data, memoryview) else thumbnail_data
            
            response = Response(thumbnail_bytes, mimetype=content_type)
            response.headers['Cache-Control'] = 'public, max-age=1800'  # 30 minutes
            response.headers['ETag'] = etag
            return response
        else:
            # Generate thumbnail if missing
            from services.image_service import generate_thumbnail
            new_thumbnail = generate_thumbnail(image_data, rotation=rotation_degrees or 0)
            if new_thumbnail:
                # Update database
                conn = get_db_connection()
                cursor = conn.cursor()
                cursor.execute(
                    'UPDATE images SET thumbnail_data = %s WHERE id = %s',
                    (new_thumbnail, image_id)
                )
                conn.commit()
                return_db_connection(conn)
                
                # Use simple hash for ETag
                etag = f'"{hash(new_thumbnail) % 2**32}"'
                thumbnail_cache.set(cache_key, (new_thumbnail, etag))
                
                # Auto-detect content type
                content_type = 'image/jpeg'
                if new_thumbnail and len(new_thumbnail) > 20:
                    data_bytes = bytes(new_thumbnail)
                    if data_bytes.startswith(b'RIFF') and b'WEBP' in data_bytes[:20]:
                        content_type = 'image/webp'
                
                response = Response(new_thumbnail, mimetype=content_type)
                response.headers['Cache-Control'] = 'public, max-age=1800'
                response.headers['ETag'] = etag
                return response
    
    return 'Thumbnail not found', 404

@image_bp.route('/rotate-image/<int:image_id>', methods=['POST'])
def rotate_image_handler(image_id):
    """Handle image rotation (90 degrees clockwise)"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Get current image data and rotation
        cursor.execute('SELECT image_data, rotation_degrees FROM images WHERE id = %s', (image_id,))
        result = cursor.fetchone()
        
        if not result:
            conn.close()
            return jsonify({"success": False, "error": "Image not found"}), 404
        
        image_data, current_rotation = result
        current_rotation = current_rotation or 0
        new_rotation = (current_rotation + 90) % 360
        
        print(f"[DEBUG] Rotating image {image_id}: {current_rotation}° -> {new_rotation}°", flush=True)
        
        # Update only the rotation degrees (don't regenerate thumbnail - rotation applied on serving)
        cursor.execute('UPDATE images SET rotation_degrees = %s WHERE id = %s', (new_rotation, image_id))
        conn.commit()
        conn.close()
        
        # Clear cache entries for this image (simplified keys)
        thumbnail_cache.cache.pop(f"thumb_{image_id}", None)
        image_cache.cache.pop(f"image_{image_id}", None)
        
        return jsonify({"success": True, "rotation": new_rotation})
    
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@image_bp.route('/delete-image/<int:image_id>', methods=['POST'])
def delete_image(image_id):
    """Delete a single image"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Get item GUID for redirect
        cursor.execute('SELECT item_guid FROM images WHERE id = %s', (image_id,))
        result = cursor.fetchone()
        
        if not result:
            conn.close()
            return jsonify({"success": False, "error": "Image not found"}), 404
        
        item_guid = result[0]
        
        # Delete the image
        cursor.execute('DELETE FROM images WHERE id = %s', (image_id,))
        conn.commit()
        conn.close()
        
        # Clear cache
        thumbnail_cache.cache.pop(f"thumb_{image_id}", None)
        image_cache.cache.pop(f"image_{image_id}", None)
        
        return jsonify({"success": True, "item_guid": item_guid})
    
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@image_bp.route('/set-primary-image/<int:image_id>', methods=['POST'])
def set_primary_image(image_id):
    """Set an image as the primary image for an item"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Get the item_guid for this image
        cursor.execute('SELECT item_guid FROM images WHERE id = %s', (image_id,))
        result = cursor.fetchone()
        
        if not result:
            conn.close()
            return jsonify({"success": False, "error": "Image not found"}), 404
            
        item_guid = result[0]
        
        # Unset all images for this item as primary
        cursor.execute('UPDATE images SET is_primary = FALSE WHERE item_guid = %s', (item_guid,))
        
        # Set the selected image as primary
        cursor.execute('UPDATE images SET is_primary = TRUE WHERE id = %s', (image_id,))
        
        conn.commit()
        conn.close()
        
        return jsonify({"success": True})
    
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@image_bp.route('/original/<int:image_id>')
def serve_original(image_id):
    """Serve original full-resolution image"""
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('''
        SELECT image_data, content_type, filename, rotation_degrees 
        FROM images WHERE id = %s
    ''', (image_id,))
    result = cursor.fetchone()
    return_db_connection(conn)
    
    if not result:
        return 'Image not found', 404
    
    image_data, content_type, filename, rotation = result
    
    # Apply rotation if needed
    if rotation != 0:
        from services.image_service import apply_rotation_to_image
        image_data = apply_rotation_to_image(image_data, rotation)
    
    response = Response(image_data, mimetype=content_type)
    response.headers['Content-Disposition'] = f'inline; filename="{filename}"'
    response.headers['Cache-Control'] = 'public, max-age=86400'  # 24 hours
    return response