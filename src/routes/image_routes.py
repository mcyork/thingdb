"""
Image routes for Flask Inventory Management System
Handles image upload, serving, rotation, and deletion
"""
import os
from flask import Blueprint, request, jsonify, Response
from werkzeug.utils import secure_filename
from thingdb.database import get_db_connection, return_db_connection
from thingdb.services.image_service import generate_thumbnail, generate_preview, is_valid_image, save_image_to_file, apply_rotation_to_image
from thingdb.models import thumbnail_cache, image_cache
from thingdb.utils.helpers import is_valid_guid, generate_etag, get_content_type
from thingdb.config import IMAGE_STORAGE_METHOD, IMAGE_DIR

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
        
        raw_image_data = file.read()
        
        if not is_valid_image(raw_image_data):
            return 'Invalid image file', 400
        
        thumbnail_data = generate_thumbnail(raw_image_data)
        preview_data = generate_preview(raw_image_data)
        content_type = get_content_type(filename)
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute('SELECT COUNT(*) FROM images WHERE item_guid = %s', (guid,))
        image_count = cursor.fetchone()[0]
        is_primary = (image_count == 0)
        
        if IMAGE_STORAGE_METHOD == 'filesystem':
            image_paths = save_image_to_file(raw_image_data, thumbnail_data, preview_data, filename)
            cursor.execute('''
                INSERT INTO images (item_guid, filename, image_data, thumbnail_data, preview_data, 
                                  content_type, is_primary, description, image_path, thumbnail_path, preview_path)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            ''', (guid, filename, b'', b'', b'', content_type, is_primary, description, 
                  image_paths['image_path'], image_paths['thumbnail_path'], image_paths['preview_path']))
        else:
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
    conn = get_db_connection()
    cursor = conn.cursor()
    
    if IMAGE_STORAGE_METHOD == 'filesystem':
        cursor.execute('SELECT preview_path, content_type, rotation_degrees FROM images WHERE id = %s', (image_id,))
        result = cursor.fetchone()
        if not result:
            return_db_connection(conn)
            return 'Image not found', 404
        
        preview_path, content_type, rotation_degrees = result
        full_path = os.path.join(IMAGE_DIR, preview_path)
        
        if not os.path.exists(full_path):
            return 'Image file not found', 404
            
        with open(full_path, 'rb') as f:
            image_data = f.read()
            
        if rotation_degrees != 0:
            image_data = apply_rotation_to_image(image_data, rotation_degrees)
            
        response = Response(image_data, mimetype=content_type)
        response.headers['Cache-Control'] = 'public, max-age=3600'
        return response
    else:
        cursor.execute('SELECT preview_data, content_type, rotation_degrees FROM images WHERE id = %s', (image_id,))
        result = cursor.fetchone()
        return_db_connection(conn)
        
        if not result:
            return 'Image not found', 404
            
        preview_data, content_type, rotation_degrees = result
        
        if rotation_degrees != 0:
            # This case is tricky as original data is needed. For now, we assume preview_data is pre-rotated or rotation is handled client-side.
            # A more robust solution would be to fetch original image_data and apply rotation.
            pass

        response = Response(preview_data, mimetype=content_type)
        response.headers['Cache-Control'] = 'public, max-age=3600'
        return response

@image_bp.route('/thumbnail/<int:image_id>')
def serve_thumbnail(image_id):
    """Serve optimized thumbnail"""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    if IMAGE_STORAGE_METHOD == 'filesystem':
        cursor.execute('SELECT thumbnail_path, content_type, rotation_degrees FROM images WHERE id = %s', (image_id,))
        result = cursor.fetchone()
        return_db_connection(conn)
        
        if not result:
            return 'Thumbnail not found', 404
            
        thumbnail_path, content_type, rotation_degrees = result
        full_path = os.path.join(IMAGE_DIR, thumbnail_path)
        
        if not os.path.exists(full_path):
            return 'Thumbnail file not found', 404
            
        with open(full_path, 'rb') as f:
            image_data = f.read()
            
        if rotation_degrees != 0:
            image_data = apply_rotation_to_image(image_data, rotation_degrees)
            
        response = Response(image_data, mimetype='image/webp')
        response.headers['Cache-Control'] = 'public, max-age=1800'
        return response
    else:
        cursor.execute('SELECT thumbnail_data FROM images WHERE id = %s', (image_id,))
        result = cursor.fetchone()
        return_db_connection(conn)
        
        if not result or not result[0]:
            return 'Thumbnail not found', 404
            
        thumbnail_data = result[0]
        
        response = Response(thumbnail_data, mimetype='image/webp')
        response.headers['Cache-Control'] = 'public, max-age=1800'
        return response

@image_bp.route('/rotate-image/<int:image_id>', methods=['POST'])
def rotate_image_handler(image_id):
    """Handle image rotation (90 degrees clockwise)"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Get current image data and rotation
        cursor.execute('SELECT rotation_degrees FROM images WHERE id = %s', (image_id,))
        result = cursor.fetchone()
        
        if not result:
            conn.close()
            return jsonify({"success": False, "error": "Image not found"}), 404
        
        current_rotation = result[0] or 0
        new_rotation = (current_rotation + 90) % 360
        
        # Update only the rotation degrees. The rotation is applied dynamically when served.
        cursor.execute('UPDATE images SET rotation_degrees = %s WHERE id = %s', (new_rotation, image_id))
        conn.commit()
        conn.close()
        
        # Clear cache entries for this image
        thumbnail_cache.cache.pop(f"thumb_{image_id}", None)
        image_cache.cache.pop(f"image_{image_id}", None)
        
        return jsonify({"success": True, "rotation": new_rotation})
    
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@image_bp.route('/delete-image/<int:image_id>', methods=['POST'])
def delete_image(image_id):
    """Delete a single image from DB and optionally from filesystem"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Get item GUID and file paths before deleting
        cursor.execute('SELECT item_guid, image_path, thumbnail_path, preview_path FROM images WHERE id = %s', (image_id,))
        result = cursor.fetchone()
        
        if not result:
            conn.close()
            return jsonify({"success": False, "error": "Image not found"}), 404
        
        item_guid, image_path, thumb_path, preview_path = result
        
        # Delete the image record from the database
        cursor.execute('DELETE FROM images WHERE id = %s', (image_id,))
        conn.commit()
        conn.close()
        
        # If using filesystem, delete the actual files
        if IMAGE_STORAGE_METHOD == 'filesystem':
            for path in [image_path, thumb_path, preview_path]:
                if path:
                    try:
                        full_path = os.path.join(IMAGE_DIR, path)
                        if os.path.exists(full_path):
                            os.remove(full_path)
                    except OSError as e:
                        print(f"Error deleting file {path}: {e}")

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
    
    if IMAGE_STORAGE_METHOD == 'filesystem':
        cursor.execute('SELECT image_path, content_type, filename, rotation_degrees FROM images WHERE id = %s', (image_id,))
        result = cursor.fetchone()
        return_db_connection(conn)
        
        if not result:
            return 'Image not found', 404
            
        image_path, content_type, filename, rotation = result
        full_path = os.path.join(IMAGE_DIR, image_path)
        
        if not os.path.exists(full_path):
            return 'Image file not found', 404
            
        with open(full_path, 'rb') as f:
            image_data = f.read()
    else:
        cursor.execute('SELECT image_data, content_type, filename, rotation_degrees FROM images WHERE id = %s', (image_id,))
        result = cursor.fetchone()
        return_db_connection(conn)
        
        if not result:
            return 'Image not found', 404
            
        image_data, content_type, filename, rotation = result

    if rotation != 0:
        image_data = apply_rotation_to_image(image_data, rotation)
    
    response = Response(image_data, mimetype=content_type)
    response.headers['Content-Disposition'] = f'inline; filename="{filename}"'
    response.headers['Cache-Control'] = 'public, max-age=86400'
    return response