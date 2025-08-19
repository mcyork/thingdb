"""
Relationship routes for Flask Inventory Management System
Handles parent/child relationships and nested item management
"""
from flask import Blueprint, request, jsonify, render_template
from database import get_db_connection
from utils.helpers import is_valid_guid

relationship_bp = Blueprint('relationship', __name__)

@relationship_bp.route('/item/<guid>/contained')
def view_contained_items(guid):
    """View all items contained within a specific item"""
    if not is_valid_guid(guid):
        return render_template('error.html',
            heading='❌ Invalid GUID Format',
            message=f'The provided GUID "{guid}" is not in the correct format.')
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Get parent item info
        cursor.execute('''
            SELECT guid, item_name, description, created_date
            FROM items 
            WHERE guid = %s
        ''', (guid,))
        
        parent_item = cursor.fetchone()
        if not parent_item:
            conn.close()
            return render_template('error.html',
                heading='❌ Item Not Found',
                message=f'No item found with GUID: {guid}')
        
        # Get all contained items (direct children only)
        cursor.execute('''
            SELECT guid, item_name, description, created_date,
                   (SELECT COUNT(*) FROM images WHERE item_guid = child_items.guid) as image_count,
                   (SELECT COUNT(*) FROM items WHERE parent_guid = child_items.guid) as contained_count,
                   primary_images.id as primary_image_id,
                   label_number
            FROM items child_items
            LEFT JOIN images as primary_images ON child_items.guid = primary_images.item_guid AND primary_images.is_primary = TRUE
            WHERE child_items.parent_guid = %s
            ORDER BY child_items.item_name
        ''', (guid,))
        
        contained_items = cursor.fetchall()
        
        # Get breadcrumb trail
        breadcrumbs = _get_breadcrumb_trail(cursor, guid, include_self=True)
        
        conn.close()
        
        return render_template('contained_items.html',
                             parent_item=parent_item,
                             contained_items=contained_items,
                             breadcrumbs=breadcrumbs)
    
    except Exception as e:
        return render_template('error.html',
            heading='❌ Database Error',
            message=f'Failed to load contained items: {str(e)}')

@relationship_bp.route('/api/move-item', methods=['POST'])
def move_item():
    """Move an item to a different parent (or make it top-level)"""
    try:
        data = request.json
        item_guid = data.get('item_guid', '').strip()
        new_parent_guid = data.get('new_parent_guid', '').strip()
        
        if not is_valid_guid(item_guid):
            return jsonify({"success": False, "error": "Invalid item GUID"}), 400
        
        # Allow empty parent_guid to make item top-level
        if new_parent_guid and not is_valid_guid(new_parent_guid):
            return jsonify({"success": False, "error": "Invalid parent GUID"}), 400
        
        # Prevent self-parenting
        if new_parent_guid == item_guid:
            return jsonify({"success": False, "error": "Item cannot be its own parent"}), 400
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Verify item exists
        cursor.execute('SELECT item_name FROM items WHERE guid = %s', (item_guid,))
        if not cursor.fetchone():
            conn.close()
            return jsonify({"success": False, "error": "Item not found"}), 404
        
        # Verify parent exists (if provided)
        if new_parent_guid:
            cursor.execute('SELECT item_name FROM items WHERE guid = %s', (new_parent_guid,))
            if not cursor.fetchone():
                conn.close()
                return jsonify({"success": False, "error": "Parent item not found"}), 404
            
            # Check for circular references
            if _creates_circular_reference(cursor, item_guid, new_parent_guid):
                conn.close()
                return jsonify({"success": False, "error": "Cannot create circular reference"}), 400
        
        # Update parent relationship
        cursor.execute('''
            UPDATE items 
            SET parent_guid = %s, updated_date = CURRENT_TIMESTAMP 
            WHERE guid = %s
        ''', (new_parent_guid if new_parent_guid else None, item_guid))
        
        conn.commit()
        conn.close()
        
        return jsonify({"success": True})
    
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@relationship_bp.route('/api/get-item-hierarchy/<guid>')
def get_item_hierarchy(guid):
    """Get the full hierarchy tree for an item (ancestors and descendants)"""
    if not is_valid_guid(guid):
        return jsonify({"error": "Invalid GUID"}), 400
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Get the root item info
        cursor.execute('''
            SELECT guid, item_name, parent_guid, created_date
            FROM items 
            WHERE guid = %s
        ''', (guid,))
        
        root_item = cursor.fetchone()
        if not root_item:
            return jsonify({"error": "Item not found"}), 404
        
        # Build hierarchy tree
        hierarchy = {
            "item": {
                "guid": root_item[0],
                "name": root_item[1],
                "parent_guid": root_item[2],
                "created_date": root_item[3].isoformat() if root_item[3] else None
            },
            "ancestors": _get_ancestors(cursor, root_item[2]) if root_item[2] else [],
            "descendants": _get_descendants(cursor, guid)
        }
        
        conn.close()
        return jsonify(hierarchy)
    
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@relationship_bp.route('/api/bulk-move', methods=['POST'])
def bulk_move_items():
    """Move multiple items to a new parent at once"""
    try:
        data = request.json
        item_guids = data.get('item_guids', [])
        new_parent_guid = data.get('new_parent_guid', '').strip()
        
        if not item_guids:
            return jsonify({"success": False, "error": "No items specified"}), 400
        
        # Validate all GUIDs
        for item_guid in item_guids:
            if not is_valid_guid(item_guid):
                return jsonify({"success": False, "error": f"Invalid GUID: {item_guid}"}), 400
        
        # Validate parent GUID if provided
        if new_parent_guid and not is_valid_guid(new_parent_guid):
            return jsonify({"success": False, "error": "Invalid parent GUID"}), 400
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Verify parent exists (if provided)
        if new_parent_guid:
            cursor.execute('SELECT item_name FROM items WHERE guid = %s', (new_parent_guid,))
            if not cursor.fetchone():
                conn.close()
                return jsonify({"success": False, "error": "Parent item not found"}), 404
        
        moved_count = 0
        errors = []
        
        for item_guid in item_guids:
            try:
                # Prevent self-parenting
                if new_parent_guid == item_guid:
                    errors.append(f"{item_guid}: Cannot be its own parent")
                    continue
                
                # Check for circular references
                if new_parent_guid and _creates_circular_reference(cursor, item_guid, new_parent_guid):
                    errors.append(f"{item_guid}: Would create circular reference")
                    continue
                
                # Verify item exists
                cursor.execute('SELECT item_name FROM items WHERE guid = %s', (item_guid,))
                if not cursor.fetchone():
                    errors.append(f"{item_guid}: Item not found")
                    continue
                
                # Update parent relationship
                cursor.execute('''
                    UPDATE items 
                    SET parent_guid = %s, updated_date = CURRENT_TIMESTAMP 
                    WHERE guid = %s
                ''', (new_parent_guid if new_parent_guid else None, item_guid))
                
                moved_count += 1
            
            except Exception as e:
                errors.append(f"{item_guid}: {str(e)}")
        
        conn.commit()
        conn.close()
        
        return jsonify({
            "success": True,
            "moved_count": moved_count,
            "total_requested": len(item_guids),
            "errors": errors
        })
    
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

def _get_breadcrumb_trail(cursor, guid, include_self=False):
    """Get breadcrumb trail for nested items"""
    breadcrumbs = []
    current_guid = guid
    max_depth = 10  # Prevent infinite loops
    
    # If include_self is True, start with the current item
    if include_self:
        cursor.execute('SELECT guid, item_name, parent_guid FROM items WHERE guid = %s', (current_guid,))
        current_item = cursor.fetchone()
        if current_item:
            breadcrumbs.append({
                'guid': current_item[0],
                'name': current_item[1]
            })
            current_guid = current_item[2]  # Move to parent
    else:
        # Get the parent GUID to start traversal
        cursor.execute('SELECT parent_guid FROM items WHERE guid = %s', (current_guid,))
        result = cursor.fetchone()
        current_guid = result[0] if result else None
    
    # Traverse up the parent chain
    for _ in range(max_depth):
        if not current_guid:
            break
            
        cursor.execute('SELECT guid, item_name, parent_guid FROM items WHERE guid = %s', (current_guid,))
        parent_item = cursor.fetchone()
        if not parent_item:
            break
            
        breadcrumbs.insert(0, {
            'guid': parent_item[0],
            'name': parent_item[1]
        })
        
        current_guid = parent_item[2]  # parent_guid
    
    return breadcrumbs

def _get_ancestors(cursor, parent_guid):
    """Get all ancestor items up the hierarchy"""
    ancestors = []
    current_guid = parent_guid
    max_depth = 10
    
    for _ in range(max_depth):
        if not current_guid:
            break
            
        cursor.execute('''
            SELECT guid, item_name, parent_guid, created_date
            FROM items 
            WHERE guid = %s
        ''', (current_guid,))
        
        ancestor = cursor.fetchone()
        if not ancestor:
            break
            
        ancestors.insert(0, {
            'guid': ancestor[0],
            'name': ancestor[1],
            'parent_guid': ancestor[2],
            'created_date': ancestor[3].isoformat() if ancestor[3] else None
        })
        
        current_guid = ancestor[2]
    
    return ancestors

def _get_descendants(cursor, parent_guid):
    """Get all descendant items in the hierarchy"""
    def get_children(guid):
        cursor.execute('''
            SELECT guid, item_name, parent_guid, created_date,
                   (SELECT COUNT(*) FROM items WHERE parent_guid = child_items.guid) as child_count
            FROM items child_items
            WHERE parent_guid = %s
            ORDER BY item_name
        ''', (guid,))
        
        children = []
        for row in cursor.fetchall():
            child = {
                'guid': row[0],
                'name': row[1],
                'parent_guid': row[2],
                'created_date': row[3].isoformat() if row[3] else None,
                'child_count': row[4],
                'children': get_children(row[0]) if row[4] > 0 else []
            }
            children.append(child)
        return children
    
    return get_children(parent_guid)

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

@relationship_bp.route('/associate-item/<guid>', methods=['POST'])
def associate_item(guid):
    """Associate a QR code with an existing item"""
    if not is_valid_guid(guid):
        return jsonify({"success": False, "error": "Invalid GUID"}), 400
    
    try:
        data = request.json
        target_guid = data.get('target_guid', '').strip()
        
        if not is_valid_guid(target_guid):
            return jsonify({"success": False, "error": "Invalid target GUID"}), 400
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Verify target item exists
        cursor.execute('SELECT item_name FROM items WHERE guid = %s', (target_guid,))
        target_item = cursor.fetchone()
        if not target_item:
            conn.close()
            return jsonify({"success": False, "error": "Target item not found"}), 404
        
        # Create QR alias mapping the scanned QR code to the target item
        cursor.execute('''
            INSERT INTO qr_aliases (qr_code, item_guid) 
            VALUES (%s, %s)
        ''', (guid, target_guid))
        
        # Delete the temporary item that was created for the scanned QR code
        cursor.execute('DELETE FROM items WHERE guid = %s', (guid,))
        
        conn.commit()
        conn.close()
        
        return jsonify({
            "success": True, 
            "redirect": f"/item/{target_guid}"
        })
    
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500