"""
Item CRUD routes for Flask Inventory Management System
Handles item creation, editing, deletion, and relationship management
"""
import json
import os
from flask import Blueprint, request, jsonify, redirect, url_for, send_file
from thingdb.database import get_db_connection
from thingdb.utils.helpers import is_valid_guid, validate_item_data, generate_guid
from thingdb.services.embedding_service import generate_embedding
from thingdb.services.qr_pdf_service import qr_pdf_service
from thingdb.config import IMAGE_STORAGE_METHOD, IMAGE_DIR

item_bp = Blueprint('item', __name__)


def cleanup_item_images(item_guid):
    """Clean up image files from filesystem when item is deleted"""
    if IMAGE_STORAGE_METHOD != 'filesystem':
        return
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Get all image file paths for this item
        cursor.execute('''
            SELECT image_path, thumbnail_path, preview_path 
            FROM images 
            WHERE item_guid = %s
        ''', (item_guid,))
        
        image_files = cursor.fetchall()
        conn.close()
        
        # Delete each image file from filesystem
        for image_path, thumbnail_path, preview_path in image_files:
            if image_path and os.path.exists(os.path.join(IMAGE_DIR, image_path)):
                try:
                    os.remove(os.path.join(IMAGE_DIR, image_path))
                except Exception as e:
                    print(f"Failed to delete image file {image_path}: {e}")
            
            if thumbnail_path and os.path.exists(os.path.join(IMAGE_DIR, thumbnail_path)):
                try:
                    os.remove(os.path.join(IMAGE_DIR, thumbnail_path))
                except Exception as e:
                    print(f"Failed to delete thumbnail file {thumbnail_path}: {e}")
            
            if preview_path and os.path.exists(os.path.join(IMAGE_DIR, preview_path)):
                try:
                    os.remove(os.path.join(IMAGE_DIR, preview_path))
                except Exception as e:
                    print(f"Failed to delete preview file {preview_path}: {e}")
                    
    except Exception as e:
        print(f"Error cleaning up images for item {item_guid}: {e}")


@item_bp.route('/update-item-name/<guid>', methods=['POST'])
def update_item_name(guid):
    """Update item name via AJAX"""
    if not is_valid_guid(guid):
        return jsonify({"success": False, "error": "Invalid GUID"}), 400
    
    try:
        # Support both form data and JSON for compatibility
        if request.is_json:
            new_name = request.json.get('name', '').strip()
        else:
            new_name = request.form.get('item_name', '').strip()
            
        if not new_name:
            return jsonify({"success": False, "error": "Name cannot be empty"}), 400
        
        if len(new_name) > 255:
            return jsonify({"success": False, "error": "Name too long (max 255 characters)"}), 400
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Update item name and timestamp
        cursor.execute('''
            UPDATE items 
            SET item_name = %s, updated_date = CURRENT_TIMESTAMP 
            WHERE guid = %s
        ''', (new_name, guid))
        
        # Generate new embedding for updated name
        try:
            embedding_vector = generate_embedding(new_name)
            if embedding_vector:
                embedding_json = json.dumps(embedding_vector)
                cursor.execute('''
                    UPDATE items 
                    SET embedding_vector = %s 
                    WHERE guid = %s
                ''', (embedding_json, guid))
        except Exception as e:
            print(f"Failed to update embedding: {e}")
        
        conn.commit()
        conn.close()
        
        return jsonify({"success": True})
    
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@item_bp.route('/update-item-description/<guid>', methods=['POST'])
def update_item_description(guid):
    """Update item description via AJAX"""
    if not is_valid_guid(guid):
        return jsonify({"success": False, "error": "Invalid GUID"}), 400
    
    try:
        # Support both form data and JSON for compatibility
        if request.is_json:
            new_description = request.json.get('description', '').strip()
        else:
            new_description = request.form.get('description', '').strip()
        
        if len(new_description) > 10000:
            return jsonify({"success": False, "error": "Description too long (max 10,000 characters)"}), 400
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Get current item name for embedding regeneration
        cursor.execute('SELECT item_name FROM items WHERE guid = %s', (guid,))
        result = cursor.fetchone()
        if not result:
            conn.close()
            return jsonify({"success": False, "error": "Item not found"}), 404
        
        item_name = result[0]
        
        # Update description and timestamp
        cursor.execute('''
            UPDATE items 
            SET description = %s, updated_date = CURRENT_TIMESTAMP 
            WHERE guid = %s
        ''', (new_description, guid))
        
        # Generate new embedding combining name and description
        try:
            combined_text = f"{item_name} {new_description}" if new_description else item_name
            embedding_vector = generate_embedding(combined_text)
            if embedding_vector:
                embedding_json = json.dumps(embedding_vector)
                cursor.execute('''
                    UPDATE items 
                    SET embedding_vector = %s 
                    WHERE guid = %s
                ''', (embedding_json, guid))
        except Exception as e:
            print(f"Failed to update embedding: {e}")
        
        conn.commit()
        conn.close()
        
        return jsonify({"success": True})
    
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@item_bp.route('/delete-item/<guid>', methods=['POST'])
def delete_item(guid):
    """Delete an item and all its associated data"""
    if not is_valid_guid(guid):
        return jsonify({"success": False, "error": "Invalid GUID"}), 400
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Check if item exists
        cursor.execute('SELECT item_name FROM items WHERE guid = %s', (guid,))
        result = cursor.fetchone()
        if not result:
            conn.close()
            return jsonify({"success": False, "error": "Item not found"}), 404
        
        # Check if item has children
        cursor.execute('SELECT COUNT(*) FROM items WHERE parent_guid = %s', (guid,))
        child_count = cursor.fetchone()[0]
        if child_count > 0:
            conn.close()
            return jsonify({
                "success": False, 
                "error": f"Cannot delete item with {child_count} contained items. Move or delete contained items first."
            }), 400
        
        # Clean up image files from filesystem before deleting database records
        cleanup_item_images(guid)
        
        # Delete associated data (images, categories, text_content will cascade)
        cursor.execute('DELETE FROM qr_aliases WHERE item_guid = %s', (guid,))
        cursor.execute('DELETE FROM items WHERE guid = %s', (guid,))
        
        conn.commit()
        conn.close()
        
        return jsonify({"success": True})
    
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@item_bp.route('/update-item-label/<guid>', methods=['POST'])
def update_item_label(guid):
    """Update item label number"""
    if not is_valid_guid(guid):
        return jsonify({"success": False, "error": "Invalid GUID"}), 400
    
    try:
        # Support both form data and JSON for compatibility
        if request.is_json:
            label_number = request.json.get('label_number', '').strip()
        else:
            label_number = request.form.get('label_number', '').strip()
        
        # Validate label number (should be numeric if provided)
        if label_number and not label_number.isdigit():
            return jsonify({"success": False, "error": "Label number must be numeric"}), 400
        
        # Convert to integer or None
        label_value = int(label_number) if label_number else None
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute(
            'UPDATE items SET label_number = %s, updated_date = CURRENT_TIMESTAMP WHERE guid = %s',
            (label_value, guid)
        )
        
        conn.commit()
        conn.close()
        
        return jsonify({"success": True, "label_number": label_value})
        
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@item_bp.route('/add-category/<guid>', methods=['POST'])
def add_category(guid):
    """Add a category/tag to an item"""
    if not is_valid_guid(guid):
        return jsonify({"success": False, "error": "Invalid GUID"}), 400
    
    try:
        # Support both form data and JSON for compatibility
        if request.is_json:
            category_name = request.json.get('category', '').strip()
        else:
            category_name = request.form.get('category_name', '').strip()
            
        if not category_name:
            return jsonify({"success": False, "error": "Category name cannot be empty"}), 400
        
        if len(category_name) > 100:
            return jsonify({"success": False, "error": "Category name too long (max 100 characters)"}), 400
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Check if category already exists for this item
        cursor.execute('''
            SELECT id FROM categories 
            WHERE item_guid = %s AND LOWER(category_name) = LOWER(%s)
        ''', (guid, category_name))
        
        if cursor.fetchone():
            conn.close()
            return jsonify({"success": False, "error": "Category already exists"}), 400
        
        # Add new category
        cursor.execute('''
            INSERT INTO categories (item_guid, category_name) 
            VALUES (%s, %s)
        ''', (guid, category_name))
        
        # Update embeddings with new category
        # Get current item data
        cursor.execute('''
            SELECT item_name, description FROM items WHERE guid = %s
        ''', (guid,))
        item_data = cursor.fetchone()
        
        if item_data:
            item_name = item_data[0] or ""
            description = item_data[1] or ""
            
            # Get all categories for this item (including the one we just added)
            cursor.execute('''
                SELECT category_name FROM categories WHERE item_guid = %s
            ''', (guid,))
            categories = cursor.fetchall()
            category_text = " ".join([cat[0] for cat in categories])
            
            # Combine name, description, and categories for comprehensive embedding
            combined_text = f"{item_name} {description} {category_text}".strip()
            
            if combined_text:
                embedding_vector = generate_embedding(combined_text)
                embedding_json = json.dumps(embedding_vector) if embedding_vector else None
                
                cursor.execute('''
                    UPDATE items SET embedding_vector = %s, updated_date = CURRENT_TIMESTAMP 
                    WHERE guid = %s
                ''', (embedding_json, guid))
        
        conn.commit()
        conn.close()
        
        return redirect(url_for('core.item_detail', guid=guid))
    
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@item_bp.route('/remove-category/<int:category_id>', methods=['POST'])
def remove_category(category_id):
    """Remove a category/tag from an item"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Delete the category
        cursor.execute('DELETE FROM categories WHERE id = %s', (category_id,))
        
        if cursor.rowcount == 0:
            conn.close()
            return jsonify({"success": False, "error": "Category not found"}), 404
        
        conn.commit()
        conn.close()
        
        return jsonify({"success": True})
    
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@item_bp.route('/set-parent/<guid>', methods=['POST'])
def set_parent_item(guid):
    """Set or change the parent item for nested relationships"""
    if not is_valid_guid(guid):
        return jsonify({"success": False, "error": "Invalid GUID"}), 400
    
    try:
        parent_guid = request.json.get('parent_guid', '').strip()
        
        # Allow empty parent_guid to remove parent relationship
        if parent_guid and not is_valid_guid(parent_guid):
            return jsonify({"success": False, "error": "Invalid parent GUID"}), 400
        
        # Prevent self-parenting
        if parent_guid == guid:
            return jsonify({"success": False, "error": "Item cannot be its own parent"}), 400
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Check if parent exists (if provided)
        if parent_guid:
            cursor.execute('SELECT guid FROM items WHERE guid = %s', (parent_guid,))
            if not cursor.fetchone():
                conn.close()
                return jsonify({"success": False, "error": "Parent item not found"}), 404
            
            # Check for circular references
            if _creates_circular_reference(cursor, guid, parent_guid):
                conn.close()
                return jsonify({"success": False, "error": "Cannot create circular reference"}), 400
        
        # Update parent relationship
        cursor.execute('''
            UPDATE items 
            SET parent_guid = %s, updated_date = CURRENT_TIMESTAMP 
            WHERE guid = %s
        ''', (parent_guid if parent_guid else None, guid))
        
        conn.commit()
        conn.close()
        
        return jsonify({"success": True})
    
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@item_bp.route('/create-item', methods=['POST'])
def create_item():
    """Create a new item with specified properties"""
    try:
        data = request.json
        
        # Validate required fields
        errors = validate_item_data(data)
        if errors:
            return jsonify({"success": False, "errors": errors}), 400
        
        # Generate new GUID if not provided
        guid = data.get('guid')
        if not guid:
            guid = generate_guid()
        elif not is_valid_guid(guid):
            return jsonify({"success": False, "error": "Invalid GUID format"}), 400
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Check if GUID already exists
        cursor.execute('SELECT guid FROM items WHERE guid = %s', (guid,))
        if cursor.fetchone():
            conn.close()
            return jsonify({"success": False, "error": "Item with this GUID already exists"}), 400
        
        # Get next label number
        cursor.execute('SELECT nextval(%s)', ('label_number_seq',))
        label_number = cursor.fetchone()[0]
        
        # Generate item name based on label number if not provided
        item_name = data.get('item_name')
        if not item_name:
            item_name = f"Item_{label_number}"
        description = data.get('description', '')
        source_url = data.get('source_url', '')
        parent_guid = data.get('parent_guid')
        
        # Validate parent if provided
        if parent_guid:
            if not is_valid_guid(parent_guid):
                conn.close()
                return jsonify({"success": False, "error": "Invalid parent GUID"}), 400
            
            cursor.execute('SELECT guid FROM items WHERE guid = %s', (parent_guid,))
            if not cursor.fetchone():
                conn.close()
                return jsonify({"success": False, "error": "Parent item not found"}), 404
        
        # Generate embedding for new item
        try:
            combined_text = f"{item_name} {description}" if description else item_name
            embedding_vector = generate_embedding(combined_text)
            embedding_json = json.dumps(embedding_vector) if embedding_vector else None
        except Exception as e:
            print(f"Failed to generate embedding: {e}")
            embedding_json = None
        
        # Create new item
        cursor.execute('''
            INSERT INTO items (guid, item_name, description, source_url, label_number, parent_guid, embedding_vector)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
        ''', (guid, item_name, description, source_url, label_number, parent_guid, embedding_json))
        
        conn.commit()
        conn.close()
        
        return jsonify({"success": True, "guid": guid, "label_number": label_number})
    
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

def _creates_circular_reference(cursor, child_guid, proposed_parent_guid):
    """Check if setting proposed_parent_guid as parent of child_guid would create a cycle"""
    visited = set()
    current = proposed_parent_guid
    max_depth = 20  # Prevent infinite loops
    
    for _ in range(max_depth):
        if current == child_guid:
            return True  # Found a cycle
        
        if current in visited:
            break  # Already checked this path
        
        visited.add(current)
        
        # Get parent of current item
        cursor.execute('SELECT parent_guid FROM items WHERE guid = %s', (current,))
        result = cursor.fetchone()
        
        if not result or not result[0]:
            break  # No parent, end of chain
        
        current = result[0]
    
    return False

@item_bp.route('/delete-category/<int:category_id>', methods=['POST'])
def delete_category(category_id):
    """Delete a category/tag"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Get category info for verification
        cursor.execute('SELECT item_guid, category_name FROM categories WHERE id = %s', (category_id,))
        result = cursor.fetchone()
        
        if not result:
            conn.close()
            return jsonify({"success": False, "error": "Category not found"}), 404
        
        item_guid, category_name = result
        
        # Delete the category
        cursor.execute('DELETE FROM categories WHERE id = %s', (category_id,))
        
        # Update embeddings after category deletion
        # Get current item data
        cursor.execute('''
            SELECT item_name, description FROM items WHERE guid = %s
        ''', (item_guid,))
        current_item = cursor.fetchone()
        
        if current_item:
            item_name = current_item[0] or ""
            description = current_item[1] or ""
            
            # Get remaining categories for this item
            cursor.execute('''
                SELECT category_name FROM categories WHERE item_guid = %s
            ''', (item_guid,))
            categories = cursor.fetchall()
            category_text = " ".join([cat[0] for cat in categories])
            
            # Combine name, description, and remaining categories for updated embedding
            combined_text = f"{item_name} {description} {category_text}".strip()
            
            if combined_text:
                embedding_vector = generate_embedding(combined_text)
                embedding_json = json.dumps(embedding_vector) if embedding_vector else None
                
                cursor.execute('''
                    UPDATE items SET embedding_vector = %s, updated_date = CURRENT_TIMESTAMP 
                    WHERE guid = %s
                ''', (embedding_json, item_guid))
        
        conn.commit()
        conn.close()
        
        return jsonify({"success": True, "deleted_category": category_name}), 200
        
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@item_bp.route('/api/item/<guid>/qr-code.png', methods=['GET'])
def get_item_qr_png(guid):
    """Serve QR code as PNG image for display on item page"""
    try:
        if not is_valid_guid(guid):
            return jsonify({"success": False, "error": "Invalid GUID"}), 400
        
        # Get item name for label
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute('SELECT item_name FROM items WHERE guid = %s', (guid,))
        result = cursor.fetchone()
        conn.close()
        
        item_name = result[0] if result else None
        
        # Generate PNG
        png_buffer = qr_pdf_service.generate_single_qr_png(guid, item_name)
        
        return send_file(
            png_buffer,
            mimetype='image/png',
            as_attachment=False,
            download_name=f'qr_{guid[:8]}.png'
        )
        
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@item_bp.route('/api/item/<guid>/qr-code.pdf', methods=['GET'])
def get_item_qr_pdf(guid):
    """Download QR code as PDF label for printing"""
    try:
        if not is_valid_guid(guid):
            return jsonify({"success": False, "error": "Invalid GUID"}), 400
        
        # Get item name for label
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute('SELECT item_name FROM items WHERE guid = %s', (guid,))
        result = cursor.fetchone()
        conn.close()
        
        item_name = result[0] if result else None
        
        # Generate PDF
        pdf_buffer = qr_pdf_service.generate_single_qr_pdf(guid, item_name)
        
        # Create filename
        safe_name = item_name.replace(' ', '_') if item_name else guid[:8]
        filename = f'qr_label_{safe_name}.pdf'
        
        return send_file(
            pdf_buffer,
            as_attachment=True,
            download_name=filename,
            mimetype='application/pdf'
        )
        
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500