"""
Printing routes for Flask Inventory Management System
Handles printing operations for inventory lists, QR codes, and item details
"""
from flask import Blueprint, request, jsonify, render_template
from thingdb.database import get_db_connection
from thingdb.services.printing_service import PrintingService
from thingdb.utils.helpers import is_valid_guid

printing_bp = Blueprint('printing', __name__)
printing_service = PrintingService()


@printing_bp.route('/print/inventory-list', methods=['GET', 'POST'])
def print_inventory_list():
    """Print inventory list with optional filtering"""
    if request.method == 'GET':
        return render_template('print_inventory_list.html')
    
    try:
        # Get filter parameters
        parent_guid = request.form.get('parent_guid', '').strip()
        printer_name = request.form.get('printer_name', '').strip() or None
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Build query based on filters
        if parent_guid and is_valid_guid(parent_guid):
            # Get items contained within a specific parent
            cursor.execute('''
                SELECT items.guid, items.item_name, items.description, 
                       items.created_date, items.label_number,
                       (SELECT COUNT(*) FROM images WHERE item_guid = items.guid) as image_count
                FROM items 
                WHERE items.parent_guid = %s
                ORDER BY items.label_number ASC, items.item_name ASC
            ''', (parent_guid,))
        else:
            # Get all root items (no parent)
            cursor.execute('''
                SELECT items.guid, items.item_name, items.description, 
                       items.created_date, items.label_number,
                       (SELECT COUNT(*) FROM images WHERE item_guid = items.guid) as image_count
                FROM items 
                WHERE items.parent_guid IS NULL
                ORDER BY items.label_number ASC, items.item_name ASC
            ''')
        
        items = cursor.fetchall()
        conn.close()
        
        # Convert to list of dictionaries
        items_list = []
        for item in items:
            items_list.append({
                'guid': item[0],
                'item_name': item[1] or f'Item {item[0][:8]}',
                'description': item[2] or '',
                'created_date': item[3].isoformat() if item[3] else None,
                'label_number': item[4],
                'image_count': item[5]
            })
        
        # Print the inventory list
        success = printing_service.print_inventory_list(items_list, printer_name)
        
        if success:
            return jsonify({
                'success': True,
                'message': f'Successfully printed inventory list ({len(items_list)} items)',
                'item_count': len(items_list)
            })
        else:
            return jsonify({
                'success': False,
                'error': 'Failed to print inventory list'
            }), 500
            
    except Exception as e:
        return jsonify({
            'success': False,
            'error': f'Print error: {str(e)}'
        }), 500


@printing_bp.route('/print/qr-codes', methods=['GET', 'POST'])
def print_qr_codes():
    """Print QR codes for items"""
    if request.method == 'GET':
        return render_template('print_qr_codes.html')
    
    try:
        # Get filter parameters
        parent_guid = request.form.get('parent_guid', '').strip()
        printer_name = request.form.get('printer_name', '').strip() or None
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Build query based on filters
        if parent_guid and is_valid_guid(parent_guid):
            # Get items contained within a specific parent
            cursor.execute('''
                SELECT items.guid, items.item_name, items.label_number
                FROM items 
                WHERE items.parent_guid = %s
                ORDER BY items.label_number ASC, items.item_name ASC
            ''', (parent_guid,))
        else:
            # Get all root items (no parent)
            cursor.execute('''
                SELECT items.guid, items.item_name, items.label_number
                FROM items 
                WHERE items.parent_guid IS NULL
                ORDER BY items.label_number ASC, items.item_name ASC
            ''')
        
        items = cursor.fetchall()
        conn.close()
        
        # Convert to list of dictionaries
        items_list = []
        for item in items:
            items_list.append({
                'guid': item[0],
                'item_name': item[1] or f'Item {item[0][:8]}',
                'label_number': item[2]
            })
        
        # Print the QR codes
        success = printing_service.print_qr_codes(items_list, printer_name)
        
        if success:
            return jsonify({
                'success': True,
                'message': f'Successfully printed QR codes ({len(items_list)} items)',
                'item_count': len(items_list)
            })
        else:
            return jsonify({
                'success': False,
                'error': 'Failed to print QR codes'
            }), 500
            
    except Exception as e:
        return jsonify({
            'success': False,
            'error': f'Print error: {str(e)}'
        }), 500


@printing_bp.route('/print/item/<guid>', methods=['POST'])
def print_item_details(guid):
    """Print detailed information for a specific item"""
    if not is_valid_guid(guid):
        return jsonify({
            'success': False,
            'error': 'Invalid GUID format'
        }), 400
    
    try:
        printer_name = request.form.get('printer_name', '').strip() or None
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Get item details
        cursor.execute('''
            SELECT items.guid, items.item_name, items.description, 
                   items.created_date, items.label_number,
                   (SELECT COUNT(*) FROM images WHERE item_guid = items.guid) as image_count
            FROM items 
            WHERE items.guid = %s
        ''', (guid,))
        
        item = cursor.fetchone()
        conn.close()
        
        if not item:
            return jsonify({
                'success': False,
                'error': 'Item not found'
            }), 404
        
        # Convert to dictionary
        item_dict = {
            'guid': item[0],
            'item_name': item[1] or f'Item {item[0][:8]}',
            'description': item[2] or '',
            'created_date': item[3].isoformat() if item[3] else None,
            'label_number': item[4],
            'image_count': item[5]
        }
        
        # Print the item details
        success = printing_service.print_item_details(item_dict, printer_name)
        
        if success:
            return jsonify({
                'success': True,
                'message': f'Successfully printed details for {item_dict["item_name"]}'
            })
        else:
            return jsonify({
                'success': False,
                'error': 'Failed to print item details'
            }), 500
            
    except Exception as e:
        return jsonify({
            'success': False,
            'error': f'Print error: {str(e)}'
        }), 500


@printing_bp.route('/print/printers', methods=['GET'])
def get_printers():
    """Get list of available printers"""
    try:
        printers = printing_service.get_available_printers()
        return jsonify({
            'success': True,
            'printers': printers,
            'default_printer': printing_service.default_printer
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'error': f'Failed to get printers: {str(e)}'
        }), 500


@printing_bp.route('/print/test-printer', methods=['POST'])
def test_printer():
    """Test printer connection"""
    try:
        printer_name = request.form.get('printer_name', '').strip() or None
        result = printing_service.test_printer_connection(printer_name)
        return jsonify(result)
    except Exception as e:
        return jsonify({
            'success': False,
            'error': f'Printer test failed: {str(e)}'
        }), 500


@printing_bp.route('/print/print-all', methods=['POST'])
def print_all():
    """Print everything: inventory list and QR codes"""
    try:
        printer_name = request.form.get('printer_name', '').strip() or None
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Get all items
        cursor.execute('''
            SELECT items.guid, items.item_name, items.description, 
                   items.created_date, items.label_number,
                   (SELECT COUNT(*) FROM images WHERE item_guid = items.guid) as image_count
            FROM items 
            ORDER BY items.label_number ASC, items.item_name ASC
        ''')
        
        items = cursor.fetchall()
        conn.close()
        
        # Convert to list of dictionaries
        items_list = []
        for item in items:
            items_list.append({
                'guid': item[0],
                'item_name': item[1] or f'Item {item[0][:8]}',
                'description': item[2] or '',
                'created_date': item[3].isoformat() if item[3] else None,
                'label_number': item[4],
                'image_count': item[5]
            })
        
        # Print inventory list
        list_success = printing_service.print_inventory_list(items_list, printer_name)
        
        # Print QR codes
        qr_success = printing_service.print_qr_codes(items_list, printer_name)
        
        if list_success and qr_success:
            return jsonify({
                'success': True,
                'message': f'Successfully printed complete inventory ({len(items_list)} items)',
                'item_count': len(items_list),
                'list_printed': True,
                'qr_codes_printed': True
            })
        else:
            return jsonify({
                'success': False,
                'error': 'Some print jobs failed',
                'list_printed': list_success,
                'qr_codes_printed': qr_success
            }), 500
            
    except Exception as e:
        return jsonify({
            'success': False,
            'error': f'Print error: {str(e)}'
        }), 500
