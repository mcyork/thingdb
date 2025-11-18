"""
Scanner API routes for ESP32-based portable scanners
Handles scanner initialization, authentication, and item operations
"""
import os
import json
import socket
from flask import Blueprint, request, jsonify
from thingdb.database import get_db_connection
from thingdb.utils.helpers import is_valid_guid
from thingdb.services.scanner_service import (
    get_ephemeral_secret,
    validate_secret
)
from thingdb.routes.item_routes import _creates_circular_reference

scanner_bp = Blueprint('scanner', __name__)


def require_auth(f):
    """Decorator to require valid scanner secret"""
    def decorated_function(*args, **kwargs):
        data = request.get_json() or {}
        secret = data.get('secret', '').strip()
        
        if not secret or not validate_secret(secret):
            return jsonify({
                'success': False,
                'error': 'Invalid or missing authentication secret'
            }), 401
        
        return f(*args, **kwargs)
    decorated_function.__name__ = f.__name__
    return decorated_function


@scanner_bp.route('/api/scanner/init-qr', methods=['GET'])
def get_init_qr():
    """Generate initialization QR code JSON for scanner setup"""
    try:
        # Get Wi-Fi info (try auto-detect first)
        wifi_info = _get_wifi_info()
        
        # Get server IP address
        server_ip = get_server_ip()
        server_port = request.environ.get('SERVER_PORT', '5000')
        
        # Get or generate ephemeral secret
        secret = get_ephemeral_secret()
        
        # Build initialization payload
        init_data = {
            'ssid': wifi_info.get('ssid', ''),
            'password': wifi_info.get('password', ''),
            'secret': secret,
            'ip': server_ip,
            'port': int(server_port)
        }
        
        return jsonify({
            'success': True,
            'data': init_data
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@scanner_bp.route('/api/scanner/wifi-info', methods=['GET'])
def get_wifi_info():
    """Attempt to auto-detect Wi-Fi SSID/password from Pi"""
    return jsonify(_get_wifi_info())


def _get_wifi_info():
    """Get Wi-Fi information (auto-detect or return empty)"""
    wifi_info = {'ssid': '', 'password': ''}
    
    # Try NetworkManager via nmcli first (modern Raspberry Pi OS)
    # This works even if config files aren't readable
    try:
        import subprocess
        # First, get active wifi connections
        result = subprocess.run(
            ['nmcli', '-t', '-f', 'NAME,TYPE', 'connection', 'show', '--active'],
            capture_output=True,
            text=True,
            timeout=2
        )
        if result.returncode == 0:
            for line in result.stdout.strip().split('\n'):
                if line and ('802-11-wireless' in line or ':wifi' in line.lower()):
                    parts = line.split(':')
                    if len(parts) >= 2:
                        conn_name = parts[0].strip()
                        # Get SSID for this connection
                        ssid_result = subprocess.run(
                            ['nmcli', '-t', '-f', '802-11-wireless.ssid', 'connection', 'show', conn_name],
                            capture_output=True,
                            text=True,
                            timeout=2
                        )
                        if ssid_result.returncode == 0:
                            ssid_line = ssid_result.stdout.strip()
                            # Extract SSID value (format: "802-11-wireless.ssid:salty")
                            if ':' in ssid_line:
                                ssid = ssid_line.split(':', 1)[1].strip()
                                if ssid:
                                    wifi_info['ssid'] = ssid
                                    break
    except (subprocess.TimeoutExpired, FileNotFoundError, Exception):
        # nmcli not available or failed, try file-based methods
        pass
    
    # Fallback: Try reading NetworkManager config files directly
    if not wifi_info['ssid']:
        nm_connections_dir = '/etc/NetworkManager/system-connections'
        if os.path.exists(nm_connections_dir) and os.access(nm_connections_dir, os.R_OK):
            try:
                import re
                for filename in os.listdir(nm_connections_dir):
                    if filename.endswith('.nmconnection'):
                        nm_path = os.path.join(nm_connections_dir, filename)
                        try:
                            # Try to read with sudo if needed (but this may fail)
                            with open(nm_path, 'r') as f:
                                content = f.read()
                                
                                # Check if it's a wifi connection
                                if 'type=wifi' in content or '[wifi]' in content:
                                    # Extract SSID
                                    ssid_match = re.search(r'^ssid=([^\n]+)', content, re.MULTILINE)
                                    if ssid_match:
                                        wifi_info['ssid'] = ssid_match.group(1).strip()
                                    
                                    # Note: NetworkManager stores PSK as hash, can't get plaintext
                                    # Password will remain empty - user must enter manually
                                    
                                    if wifi_info['ssid']:
                                        break
                        except (PermissionError, IOError):
                            # File not readable, skip
                            continue
                        except Exception:
                            continue
            except Exception:
                pass
    
    # Fallback: Try wpa_supplicant.conf (older systems)
    if not wifi_info['ssid']:
        wpa_supplicant_paths = [
            '/etc/wpa_supplicant/wpa_supplicant.conf',
            '/etc/wpa_supplicant/wpa_supplicant-wlan0.conf'
        ]
        
        for wpa_path in wpa_supplicant_paths:
            try:
                if os.path.exists(wpa_path) and os.access(wpa_path, os.R_OK):
                    with open(wpa_path, 'r') as f:
                        content = f.read()
                        
                        # Simple parsing for ssid and psk
                        import re
                        ssid_match = re.search(r'ssid="([^"]+)"', content)
                        psk_match = re.search(r'psk="([^"]+)"', content)
                        
                        if ssid_match:
                            wifi_info['ssid'] = ssid_match.group(1)
                        if psk_match:
                            # Check if it's a hash (64 hex chars) or plaintext
                            psk_value = psk_match.group(1)
                            if len(psk_value) == 64 and all(c in '0123456789abcdefABCDEF' for c in psk_value):
                                # It's a hash, can't get plaintext
                                pass
                            else:
                                wifi_info['password'] = psk_value
                        
                        if wifi_info['ssid']:
                            break
            except Exception:
                # If we can't read it, that's fine - user will enter manually
                pass
    
    return wifi_info


def get_server_ip():
    """Get the server's IP address"""
    try:
        # Try to get from request host
        host = request.host.split(':')[0]
        if host and host != '0.0.0.0' and host != 'localhost' and host != '127.0.0.1':
            # Check if it's already an IP
            try:
                socket.inet_aton(host)
                return host
            except socket.error:
                # It's a hostname, try to resolve
                try:
                    return socket.gethostbyname(host)
                except socket.gaierror:
                    pass
        
        # Fallback: connect to external address to determine local IP
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            # Connect to a remote address (doesn't actually send data)
            s.connect(('8.8.8.8', 80))
            ip = s.getsockname()[0]
            return ip
        except Exception:
            pass
        finally:
            s.close()
        
        # Last resort: try hostname
        try:
            return socket.gethostbyname(socket.gethostname())
        except Exception:
            pass
        
        return '192.168.1.100'  # Default fallback
    except Exception:
        return '192.168.1.100'  # Default fallback


@scanner_bp.route('/api/scanner/scan-item', methods=['POST'])
@require_auth
def scan_item():
    """Scanner scans an item QR code - returns item information"""
    try:
        data = request.get_json()
        guid = data.get('guid', '').strip()
        
        if not guid:
            return jsonify({
                'success': False,
                'error': 'GUID is required'
            }), 400
        
        if not is_valid_guid(guid):
            return jsonify({
                'success': False,
                'error': 'Invalid GUID format'
            }), 400
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # First check if this is an alternative GUID (alias)
        cursor.execute('SELECT item_guid FROM qr_aliases WHERE qr_code = %s', (guid,))
        alias_result = cursor.fetchone()
        
        # Use the base GUID if this is an alias, otherwise use the scanned GUID
        base_guid = alias_result[0] if alias_result else guid
        
        # Get item information using the base GUID
        cursor.execute('''
            SELECT guid, item_name, label_number
            FROM items
            WHERE guid = %s
        ''', (base_guid,))
        
        item = cursor.fetchone()
        conn.close()
        
        if not item:
            return jsonify({
                'success': False,
                'error': 'Item not found'
            }), 404
        
        # Always return the base GUID, even if an alternative GUID was scanned
        return jsonify({
            'success': True,
            'guid': item[0],  # Base GUID
            'name': item[1] or 'Unnamed Item',
            'label_number': item[2]
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@scanner_bp.route('/api/scanner/move-item', methods=['POST'])
@require_auth
def move_item():
    """Move an item to a new parent - validates and executes in one call"""
    try:
        data = request.get_json()
        item_guid = data.get('item_guid', '').strip()
        parent_guid = data.get('parent_guid', '').strip()
        
        if not item_guid:
            return jsonify({
                'success': False,
                'error': 'item_guid is required'
            }), 400
        
        if not parent_guid:
            return jsonify({
                'success': False,
                'error': 'parent_guid is required'
            }), 400
        
        if not is_valid_guid(item_guid) or not is_valid_guid(parent_guid):
            return jsonify({
                'success': False,
                'error': 'Invalid GUID format'
            }), 400
        
        # Prevent self-parenting
        if item_guid == parent_guid:
            return jsonify({
                'success': False,
                'error': 'Item cannot be its own parent'
            }), 400
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Check if items exist
        cursor.execute('SELECT guid FROM items WHERE guid = %s', (item_guid,))
        if not cursor.fetchone():
            conn.close()
            return jsonify({
                'success': False,
                'error': 'Item not found'
            }), 404
        
        cursor.execute('SELECT guid FROM items WHERE guid = %s', (parent_guid,))
        if not cursor.fetchone():
            conn.close()
            return jsonify({
                'success': False,
                'error': 'Parent item not found'
            }), 404
        
        # Check for circular references
        if _creates_circular_reference(cursor, item_guid, parent_guid):
            conn.close()
            return jsonify({
                'success': False,
                'error': 'Cannot create circular reference'
            }), 400
        
        # Execute the move
        cursor.execute('''
            UPDATE items 
            SET parent_guid = %s, updated_date = CURRENT_TIMESTAMP 
            WHERE guid = %s
        ''', (parent_guid, item_guid))
        
        conn.commit()
        conn.close()
        
        return jsonify({
            'success': True,
            'message': 'Item moved successfully'
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@scanner_bp.route('/api/scanner/delete-item', methods=['POST'])
@require_auth
def delete_item():
    """Delete an item - validates and executes in one call"""
    try:
        data = request.get_json()
        guid = data.get('guid', '').strip()
        
        if not guid:
            return jsonify({
                'success': False,
                'error': 'GUID is required'
            }), 400
        
        if not is_valid_guid(guid):
            return jsonify({
                'success': False,
                'error': 'Invalid GUID format'
            }), 400
        
        from thingdb.routes.item_routes import cleanup_item_images
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Check if item exists
        cursor.execute('SELECT guid FROM items WHERE guid = %s', (guid,))
        if not cursor.fetchone():
            conn.close()
            return jsonify({
                'success': False,
                'error': 'Item not found'
            }), 404
        
        # Delete associated data
        cursor.execute('DELETE FROM images WHERE item_guid = %s', (guid,))
        cursor.execute('DELETE FROM categories WHERE item_guid = %s', (guid,))
        cursor.execute('DELETE FROM qr_aliases WHERE item_guid = %s', (guid,))
        
        # Clean up images from filesystem
        cleanup_item_images(guid)
        
        # Delete the item
        cursor.execute('DELETE FROM items WHERE guid = %s', (guid,))
        
        conn.commit()
        conn.close()
        
        return jsonify({
            'success': True,
            'message': 'Item deleted successfully'
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


def _resolve_to_base_guid(cursor, guid):
    """Resolve a GUID (which may be an alias) to its base GUID"""
    # Check if this is an alias
    cursor.execute(
        'SELECT item_guid FROM qr_aliases WHERE qr_code = %s',
        (guid,)
    )
    alias_result = cursor.fetchone()
    return alias_result[0] if alias_result else guid


@scanner_bp.route('/api/scanner/make-alias', methods=['POST'])
@require_auth
def make_alias():
    """Create an alias linking a QR code to an existing item"""
    try:
        data = request.get_json()
        first_code = data.get('first_code', '').strip()
        second_code = data.get('second_code', '').strip()
        
        if not first_code or not second_code:
            return jsonify({
                'success': False,
                'error': 'first_code and second_code are required'
            }), 400
        
        if not is_valid_guid(first_code) or not is_valid_guid(second_code):
            return jsonify({
                'success': False,
                'error': 'Invalid GUID format'
            }), 400
        
        # Prevent aliasing to itself
        if first_code == second_code:
            return jsonify({
                'success': False,
                'error': 'Cannot create alias to itself'
            }), 400
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Resolve first code to base GUID
        first_base_guid = _resolve_to_base_guid(cursor, first_code)
        
        # Verify first item exists
        cursor.execute('SELECT guid FROM items WHERE guid = %s',
                       (first_base_guid,))
        if not cursor.fetchone():
            conn.close()
            return jsonify({
                'success': False,
                'error': 'First item not found'
            }), 404
        
        # Resolve second code to base GUID (if it's an alias)
        second_base_guid = _resolve_to_base_guid(cursor, second_code)
        
        # Verify second item exists (either as base item or alias)
        cursor.execute('SELECT guid FROM items WHERE guid = %s',
                       (second_base_guid,))
        if not cursor.fetchone():
            conn.close()
            return jsonify({
                'success': False,
                'error': 'Second code does not exist as an item'
            }), 404
        
        # Check if alias already exists
        cursor.execute('SELECT id FROM qr_aliases WHERE qr_code = %s',
                       (second_code,))
        if cursor.fetchone():
            conn.close()
            return jsonify({
                'success': False,
                'error': 'Second code is already aliased to another item'
            }), 400
        
        # Create the alias: second_code -> first_base_guid
        cursor.execute('''
            INSERT INTO qr_aliases (qr_code, item_guid)
            VALUES (%s, %s)
        ''', (second_code, first_base_guid))
        
        conn.commit()
        conn.close()
        
        return jsonify({
            'success': True,
            'message': f'Alias created: {second_code} -> {first_base_guid}'
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@scanner_bp.route('/api/scanner/bulk-move', methods=['POST'])
@require_auth
def bulk_move():
    """Move multiple items to a new parent in one operation"""
    try:
        data = request.get_json()
        item_guids = data.get('item_guids', [])
        parent_guid = data.get('parent_guid', '').strip()
        
        if not item_guids:
            return jsonify({
                'success': False,
                'error': 'item_guids array is required'
            }), 400
        
        if not isinstance(item_guids, list):
            return jsonify({
                'success': False,
                'error': 'item_guids must be an array'
            }), 400
        
        if not parent_guid:
            return jsonify({
                'success': False,
                'error': 'parent_guid is required'
            }), 400
        
        if not is_valid_guid(parent_guid):
            return jsonify({
                'success': False,
                'error': 'Invalid parent_guid format'
            }), 400
        
        # Validate all item GUIDs
        for guid in item_guids:
            if not is_valid_guid(guid):
                return jsonify({
                    'success': False,
                    'error': f'Invalid GUID format: {guid}'
                }), 400
        
        # Remove duplicates
        item_guids = list(set(item_guids))
        
        # Prevent moving item to itself
        if parent_guid in item_guids:
            return jsonify({
                'success': False,
                'error': 'Cannot move item to itself'
            }), 400
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Verify parent exists
        cursor.execute('SELECT guid FROM items WHERE guid = %s',
                       (parent_guid,))
        if not cursor.fetchone():
            conn.close()
            return jsonify({
                'success': False,
                'error': 'Parent item not found'
            }), 404
        
        # Verify all items exist and check for circular references
        valid_items = []
        for item_guid in item_guids:
            cursor.execute('SELECT guid FROM items WHERE guid = %s',
                           (item_guid,))
            if not cursor.fetchone():
                conn.close()
                return jsonify({
                    'success': False,
                    'error': f'Item not found: {item_guid}'
                }), 404
            
            # Check for circular references
            if _creates_circular_reference(cursor, item_guid, parent_guid):
                conn.close()
                return jsonify({
                    'success': False,
                    'error': f'Cannot create circular reference for item: '
                             f'{item_guid}'
                }), 400
            
            valid_items.append(item_guid)
        
        # Execute bulk move in a single transaction
        moved_count = 0
        for item_guid in valid_items:
            cursor.execute('''
                UPDATE items
                SET parent_guid = %s, updated_date = CURRENT_TIMESTAMP
                WHERE guid = %s
            ''', (parent_guid, item_guid))
            moved_count += cursor.rowcount
        
        conn.commit()
        conn.close()
        
        return jsonify({
            'success': True,
            'message': f'Successfully moved {moved_count} item(s)',
            'moved_count': moved_count
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@scanner_bp.route('/api/scanner/audit-item', methods=['POST'])
@require_auth
def audit_item():
    """Update last seen timestamp for an item (audit trail)"""
    try:
        data = request.get_json()
        guid = data.get('guid', '').strip()
        
        if not guid:
            return jsonify({
                'success': False,
                'error': 'GUID is required'
            }), 400
        
        if not is_valid_guid(guid):
            return jsonify({
                'success': False,
                'error': 'Invalid GUID format'
            }), 400
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Resolve to base GUID if alias
        base_guid = _resolve_to_base_guid(cursor, guid)
        
        # Verify item exists
        cursor.execute('SELECT guid FROM items WHERE guid = %s',
                       (base_guid,))
        if not cursor.fetchone():
            conn.close()
            return jsonify({
                'success': False,
                'error': 'Item not found'
            }), 404
        
        # Update timestamp
        cursor.execute('''
            UPDATE items
            SET updated_date = CURRENT_TIMESTAMP
            WHERE guid = %s
        ''', (base_guid,))
        
        conn.commit()
        conn.close()
        
        return jsonify({
            'success': True,
            'message': 'Item audit timestamp updated'
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

