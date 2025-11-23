"""
Core routes for Flask Inventory Management System
Handles home page, GUID processing, and item viewing
"""
import json
from flask import Blueprint, render_template, request, redirect, url_for, jsonify
from thingdb.database import get_db_connection
from thingdb.utils.helpers import is_valid_guid, generate_guid
from thingdb.config import APP_VERSION

core_bp = Blueprint('core', __name__)

def extract_guid_from_url(url_input):
    """Extract GUID from various URL formats"""
    import re
    # Look for GUID pattern in the input
    guid_pattern = r'([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})'
    match = re.search(guid_pattern, url_input, re.IGNORECASE)
    return match.group(1) if match else None

@core_bp.route('/')
def home():
    """Home page with GUID entry and QR code scanning"""
    # Get list of existing items
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute('''
        SELECT items.guid, items.item_name, items.created_date, 
               (SELECT COUNT(*) FROM images WHERE item_guid = items.guid) as image_count,
               (SELECT COUNT(*) FROM text_content WHERE item_guid = items.guid) as text_count,
               primary_images.id as primary_image_id,
               items.label_number
        FROM items 
        LEFT JOIN images as primary_images ON items.guid = primary_images.item_guid AND primary_images.is_primary = TRUE
        ORDER BY items.created_date DESC
    ''')
    items = cursor.fetchall()
    conn.close()
    
    return render_template('home.html', items=items, version=APP_VERSION)

@core_bp.route('/process-guid', methods=['POST'])
def process_guid():
    """Process GUID input and redirect to item page"""
    guid_input = request.form.get('guid', '').strip()
    
    if not guid_input:
        return redirect(url_for('core.home'))
    
    # Extract GUID from URL if provided
    guid = extract_guid_from_url(guid_input)
    if not guid:
        # Assume it's a direct GUID
        guid = guid_input
    
    # Validate GUID format
    if not is_valid_guid(guid):
        return render_template('error.html', 
            heading='❌ Invalid GUID Format',
            message=f'The provided GUID "{guid_input}" is not in the correct format.',
            details='Expected format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx')
    
    # Check if this QR code is an alias
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # First check if the original input is an alias (for pure GUID QR codes)
    cursor.execute('SELECT item_guid FROM qr_aliases WHERE qr_code = %s', (guid_input,))
    alias_result = cursor.fetchone()
    
    if alias_result:
        # This QR code is an alias, redirect to the actual item
        actual_guid = alias_result[0]
        conn.close()
        return redirect(url_for('core.item_detail', guid=actual_guid))
    
    # If no match found with original input, check if the extracted GUID is an alias (for URL-based QR codes)
    if guid != guid_input:  # Only check if we extracted a GUID from a URL
        cursor.execute('SELECT item_guid FROM qr_aliases WHERE qr_code = %s', (guid,))
        alias_result = cursor.fetchone()
        
        if alias_result:
            # This extracted GUID is an alias, redirect to the actual item
            actual_guid = alias_result[0]
            conn.close()
            return redirect(url_for('core.item_detail', guid=actual_guid))
    
    # Check if item exists
    cursor.execute('SELECT guid FROM items WHERE guid = %s', (guid,))
    existing_item = cursor.fetchone()
    
    if existing_item:
        conn.close()
        return redirect(url_for('core.item_detail', guid=guid))
    
    # Item doesn't exist, create it temporarily and show association dialog
    cursor.execute('SELECT nextval(%s)', ('label_number_seq',))
    label_number = cursor.fetchone()[0]
    
    default_name = f"Item_{label_number:04d}"
    
    # Generate embedding for new item (skip for faster creation)
    cursor.execute('''
        INSERT INTO items (guid, item_name, label_number, embedding_vector) 
        VALUES (%s, %s, %s, %s)
    ''', (guid, default_name, label_number, None))
    
    conn.commit()
    conn.close()
    
    # Redirect to item page with new_item to show association banner
    # The banner will trigger edit_title when dismissed
    return redirect(url_for('core.item_detail', guid=guid, new_item='1'))

@core_bp.route('/item/<guid>')
def item_detail(guid):
    """Item detail page"""
    # Validate GUID format
    if not is_valid_guid(guid):
        return render_template('error.html',
            heading='❌ Invalid GUID Format',
            message=f'The provided GUID "{guid}" is not in the correct format.')
    
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # Get item data
    cursor.execute('''
        SELECT guid, item_name, description, source_url, created_date, updated_date, label_number, parent_guid
        FROM items 
        WHERE guid = %s
    ''', (guid,))
    
    item_data = cursor.fetchone()
    if not item_data:
        conn.close()
        return render_template('error.html',
            heading='❌ Item Not Found',
            message=f'No item found with GUID: {guid}')
    
    # Get breadcrumb trail if item has parents
    breadcrumbs = []
    if item_data[7]:  # parent_guid
        breadcrumbs = _get_breadcrumb_trail(cursor, item_data[7])
    
    # Get item images
    cursor.execute('''
        SELECT id, filename, content_type, rotation_degrees, is_primary, upload_date
        FROM images 
        WHERE item_guid = %s 
        ORDER BY is_primary DESC, upload_date DESC
    ''', (guid,))
    images = cursor.fetchall()
    
    # Get item categories/tags
    cursor.execute('''
        SELECT id, category_name
        FROM categories 
        WHERE item_guid = %s 
        ORDER BY category_name
    ''', (guid,))
    categories = cursor.fetchall()
    
    # Get contained items (children)
    cursor.execute('''
        SELECT child_items.guid, child_items.item_name, child_items.created_date,
               (SELECT COUNT(*) FROM images WHERE item_guid = child_items.guid) as image_count,
               primary_images.id as primary_image_id
        FROM items child_items
        LEFT JOIN images as primary_images ON child_items.guid = primary_images.item_guid AND primary_images.is_primary = TRUE
        WHERE child_items.parent_guid = %s
        ORDER BY child_items.item_name, child_items.created_date DESC
    ''', (guid,))
    contained_items = cursor.fetchall()
    
    conn.close()
    
    # Check if recently created (for showing association UI)
    import datetime
    created_date = item_data[4]  # created_date from item_data
    is_recently_created = False
    if created_date:
        time_diff = datetime.datetime.now() - created_date
        is_recently_created = time_diff.total_seconds() < 300  # 5 minutes
    
    # Show association dialog when new_item parameter is present
    # Also trigger edit mode when edit_title parameter is present
    is_new_from_param = request.args.get('new_item') == '1'
    show_association = is_new_from_param
    # Note: edit_title parameter is handled in the template JavaScript
    
    # Build structured item_data dictionary to match original
    item_data_dict = {
        'item': item_data,
        'parent_item': None,  # TODO: fetch if needed
        'breadcrumb': breadcrumbs,
        'contained_items': contained_items,
        'images': images,
        'text_content': [],  # Legacy, not used
        'categories': categories,
        'is_recently_created': is_recently_created,
        'item_name': item_data[1],
        'description': item_data[2]
    }
    
    # Format GUID display (last 4 chars in XX-XX format)
    guid_display = f"{guid[-4:-2]}-{guid[-2:]}".upper()
    
    return render_template('item.html', 
                         guid=guid,
                         guid_display=guid_display,
                         item_data=item_data_dict,
                         images=images,
                         categories=categories,
                         show_association=show_association)

def _get_breadcrumb_trail(cursor, parent_guid):
    """Get breadcrumb trail for nested items"""
    breadcrumbs = []
    current_guid = parent_guid
    max_depth = 10  # Prevent infinite loops
    
    for _ in range(max_depth):
        if not current_guid:
            break
            
        cursor.execute('''
            SELECT guid, item_name, parent_guid 
            FROM items 
            WHERE guid = %s
        ''', (current_guid,))
        
        parent_item = cursor.fetchone()
        if not parent_item:
            break
            
        breadcrumbs.insert(0, {
            'guid': parent_item[0],
            'name': parent_item[1]
        })
        
        current_guid = parent_item[2]  # parent_guid
    
    return breadcrumbs

@core_bp.route('/api/tree-data')
def get_tree_data():
    """API endpoint to fetch hierarchical tree data for the tree view"""
    from flask import request
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # Get sort parameter (default to alpha)
    sort_mode = request.args.get('sort', 'alpha')
    
    # Build ORDER BY clause based on sort mode (PostgreSQL syntax)
    if sort_mode == 'alpha':
        order_clause = 'ORDER BY LOWER(items.item_name) ASC'
    elif sort_mode == 'recent':
        order_clause = 'ORDER BY items.created_date DESC'
    elif sort_mode == 'number':
        order_clause = 'ORDER BY items.label_number ASC, LOWER(items.item_name) ASC'
    else:
        order_clause = 'ORDER BY LOWER(items.item_name) ASC'  # default to alpha
    
    try:
        # Get all root items (items with no parent)
        cursor.execute(f'''
            SELECT items.guid, items.item_name, items.created_date, 
                   (SELECT COUNT(*) FROM images WHERE item_guid = items.guid) as image_count,
                   (SELECT COUNT(*) FROM text_content WHERE item_guid = items.guid) as text_count,
                   primary_images.id as primary_image_id,
                   items.label_number,
                   (SELECT COUNT(*) FROM items children WHERE children.parent_guid = items.guid) as child_count
            FROM items 
            LEFT JOIN images as primary_images ON items.guid = primary_images.item_guid AND primary_images.is_primary = TRUE
            WHERE items.parent_guid IS NULL
            {order_clause}
        ''')
        root_items = cursor.fetchall()
        
        # Build tree structure
        tree_data = []
        for item in root_items:
            tree_item = {
                'guid': item[0],
                'name': item[1] or f'Item {item[0][:8]}',
                'created_date': item[2].isoformat() if item[2] else None,
                'image_count': item[3],
                'text_count': item[4],
                'primary_image_id': item[5], 
                'label_number': item[6],
                'child_count': item[7],
                'children': [],
                'expanded': False
            }
            tree_data.append(tree_item)
        
        return jsonify({
            'success': True,
            'data': tree_data,
            'total_root_items': len(tree_data)
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500
    finally:
        conn.close()

@core_bp.route('/api/tree-children/<guid>')
def get_tree_children(guid):
    """API endpoint to fetch children of a specific item for tree expansion"""
    from flask import request
    if not is_valid_guid(guid):
        return jsonify({
            'success': False,
            'error': 'Invalid GUID format'
        }), 400
    
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # Get sort parameter (default to alpha)
    sort_mode = request.args.get('sort', 'alpha')
    
    # Build ORDER BY clause based on sort mode (PostgreSQL syntax)
    if sort_mode == 'alpha':
        order_clause = 'ORDER BY LOWER(items.item_name) ASC'
    elif sort_mode == 'recent':
        order_clause = 'ORDER BY items.created_date DESC'
    elif sort_mode == 'number':
        order_clause = 'ORDER BY items.label_number ASC, LOWER(items.item_name) ASC'
    else:
        order_clause = 'ORDER BY LOWER(items.item_name) ASC'  # default to alpha
    
    try:
        # Get children of the specified item
        cursor.execute(f'''
            SELECT items.guid, items.item_name, items.created_date, 
                   (SELECT COUNT(*) FROM images WHERE item_guid = items.guid) as image_count,
                   (SELECT COUNT(*) FROM text_content WHERE item_guid = items.guid) as text_count,
                   primary_images.id as primary_image_id,
                   items.label_number,
                   (SELECT COUNT(*) FROM items children WHERE children.parent_guid = items.guid) as child_count
            FROM items 
            LEFT JOIN images as primary_images ON items.guid = primary_images.item_guid AND primary_images.is_primary = TRUE
            WHERE items.parent_guid = %s
            {order_clause}
        ''', (guid,))
        children = cursor.fetchall()
        
        # Build children data
        children_data = []
        for item in children:
            child_item = {
                'guid': item[0],
                'name': item[1] or f'Item {item[0][:8]}',
                'created_date': item[2].isoformat() if item[2] else None,
                'image_count': item[3],
                'text_count': item[4],
                'primary_image_id': item[5],
                'label_number': item[6],
                'child_count': item[7],
                'children': [],
                'expanded': False
            }
            children_data.append(child_item)
        
        return jsonify({
            'success': True,
            'data': children_data,
            'parent_guid': guid,
            'total_children': len(children_data)
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500
    finally:
        conn.close()