"""
Scanner API routes for ESP32-based portable scanners
Handles scanner initialization, authentication, and item operations
"""
import os
import json
import socket
import logging
from datetime import datetime
from collections import deque
from flask import Blueprint, request, jsonify
from thingdb.database import get_db_connection
from thingdb.utils.helpers import is_valid_guid
from thingdb.services.scanner_service import (
    get_ephemeral_secret,
    validate_secret
)
from thingdb.routes.item_routes import _creates_circular_reference

scanner_bp = Blueprint('scanner', __name__)
logger = logging.getLogger(__name__)

# In-memory cache for recent scans (dumb scanner mode)
# Stores last 100 scans for browser polling
_recent_scans = deque(maxlen=100)


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
        
        response = jsonify({
            'success': True,
            'data': init_data
        })
        # Prevent caching to ensure fresh secret is always returned
        response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
        response.headers['Pragma'] = 'no-cache'
        response.headers['Expires'] = '0'
        return response
        
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


# In-memory cache for recent scans (dumb scanner mode)
# Stores last 100 scans for browser polling
_recent_scans = deque(maxlen=100)


@scanner_bp.route('/api/scanner/receive-scan', methods=['POST'])
def receive_scan():
    """
    Receive scanned data from dumb scanners (DS2800, ESP32 dumb mode).
    No authentication required. Validates scan and triggers browser notifications.
    
    Accepts both JSON and application/x-www-form-urlencoded formats.
    """
    # Log incoming request for debugging
    client_ip = request.remote_addr
    user_agent = request.headers.get('User-Agent', 'Unknown')
    content_type = request.headers.get('Content-Type', '').lower()
    logger.info(f"Scanner request received from {client_ip} (User-Agent: {user_agent}, Content-Type: {content_type})")
    
    try:
        device_id = ''
        scanned_data = ''
        
        # Handle different content types
        if 'application/json' in content_type:
            # JSON format: {"id": "device_id", "msg": "scanned_data"}
            data = request.get_json() or {}
            device_id = data.get('id', '').strip()
            scanned_data = data.get('msg', '').strip()
        elif 'application/x-www-form-urlencoded' in content_type or 'x-www-form-urlencoded' in content_type:
            # Form-encoded format: either form fields or raw body as GUID
            # Try form fields first
            if request.form:
                device_id = request.form.get('id', '').strip()
                scanned_data = request.form.get('msg', '').strip()
            
            # If no form data, try raw body (scanner might send GUID directly)
            if not scanned_data and request.data:
                body_text = request.data.decode('utf-8', errors='replace').strip()
                # If it's just a GUID, use it as scanned_data
                if is_valid_guid(body_text):
                    scanned_data = body_text
                    device_id = 'ESP32-Scanner'  # Default device ID
                else:
                    # Try to parse as form-encoded string
                    scanned_data = body_text
                    device_id = 'ESP32-Scanner'
        else:
            # Try JSON first, then form, then raw data
            data = request.get_json()
            if data:
                device_id = data.get('id', '').strip()
                scanned_data = data.get('msg', '').strip()
            elif request.form:
                device_id = request.form.get('id', '').strip()
                scanned_data = request.form.get('msg', '').strip()
            elif request.data:
                body_text = request.data.decode('utf-8', errors='replace').strip()
                if is_valid_guid(body_text):
                    scanned_data = body_text
                    device_id = 'ESP32-Scanner'
                else:
                    scanned_data = body_text
                    device_id = 'ESP32-Scanner'
        
        # Default device ID if not provided
        if not device_id:
            device_id = 'ESP32-Scanner'
        
        logger.info(f"Scanner data - Device ID: {device_id}, Scanned: {scanned_data[:50]}...")
        
        # Default device ID if not provided (for form-encoded scanners that only send GUID)
        if not device_id:
            device_id = 'ESP32-Scanner'
        
        if not scanned_data:
            logger.warning(f"Scanner request missing scanned data from {client_ip} (device: {device_id})")
            return jsonify({
                'success': False,
                'error': 'Scanned data (msg) is required'
            }), 400
        
        # Validate if scanned data is a GUID
        is_valid_guid_format = is_valid_guid(scanned_data)
        
        # Try to extract GUID from URL if present
        # Handle formats like: https://example.com/qr/12345678-1234-1234-1234-123456789ABC
        extracted_guid = scanned_data
        if not is_valid_guid_format and '/' in scanned_data:
            # Try to extract GUID from URL
            parts = scanned_data.split('/')
            for part in parts:
                if is_valid_guid(part):
                    extracted_guid = part
                    is_valid_guid_format = True
                    break
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        item_found = False
        item_guid = None
        item_name = None
        
        if is_valid_guid_format:
            # Check if this is an alias
            cursor.execute('SELECT item_guid FROM qr_aliases WHERE qr_code = %s', (extracted_guid,))
            alias_result = cursor.fetchone()
            base_guid = alias_result[0] if alias_result else extracted_guid
            
            # Check if item exists
            cursor.execute('''
                SELECT guid, item_name
                FROM items
                WHERE guid = %s
            ''', (base_guid,))
            
            item_result = cursor.fetchone()
            if item_result:
                item_found = True
                item_guid = item_result[0]
                item_name = item_result[1] or 'Unnamed Item'
        
        conn.close()
        
        # Create scan event for browser notifications
        scan_event = {
            'timestamp': datetime.utcnow().isoformat(),
            'device_id': device_id,
            'scanned_data': scanned_data,
            'extracted_guid': extracted_guid if is_valid_guid_format else None,
            'is_valid_guid': is_valid_guid_format,
            'item_found': item_found,
            'item_guid': item_guid,
            'item_name': item_name
        }
        
        # Add to recent scans cache
        _recent_scans.append(scan_event)
        
        # Return response (always 200 OK to scanner)
        response_data = {
            'success': True,
            'scanned_data': scanned_data,
            'device_id': device_id,
            'item_found': item_found,
            'is_valid_guid': is_valid_guid_format
        }
        
        if item_found:
            response_data['item_guid'] = item_guid
            response_data['item_name'] = item_name
            response_data['message'] = 'Scan received and processed'
        elif is_valid_guid_format:
            response_data['message'] = 'New QR code detected - browser will prompt for action'
        else:
            response_data['message'] = 'Scanned data is not a valid GUID format'
        
        # Log successful processing
        if item_found:
            logger.info(f"Scanner scan successful - Item found: {item_name} ({item_guid})")
        elif is_valid_guid_format:
            logger.info(f"Scanner scan - Valid GUID format but item not found: {extracted_guid}")
        else:
            logger.info(f"Scanner scan - Invalid GUID format: {scanned_data[:50]}")
        
        return jsonify(response_data)
        
    except Exception as e:
        # Still return 200 OK to scanner, but log the error
        logger.error(f"Scanner request error from {client_ip}: {str(e)}", exc_info=True)
        return jsonify({
            'success': False,
            'error': str(e),
            'message': 'Scan received but processing failed'
        }), 200


@scanner_bp.route('/api/scanner/recent-scans', methods=['GET'])
def get_recent_scans():
    """
    Get recent scans for browser polling (dumb scanner mode).
    Returns scans from the last N seconds or last N scans.
    """
    try:
        # Get query parameters
        since_seconds = request.args.get('since', type=int, default=30)  # Default: last 30 seconds
        max_results = request.args.get('max', type=int, default=50)  # Default: max 50 results
        
        # Filter scans by timestamp if requested
        if since_seconds > 0:
            cutoff_time = datetime.utcnow().timestamp() - since_seconds
            recent = []
            for scan in _recent_scans:
                try:
                    scan_time = datetime.fromisoformat(scan['timestamp'])
                    if scan_time.timestamp() > cutoff_time:
                        recent.append(scan)
                except (ValueError, AttributeError, KeyError):
                    # Skip invalid timestamps
                    continue
        else:
            # Return all recent scans
            recent = list(_recent_scans)
        
        # Limit results
        recent = recent[-max_results:] if len(recent) > max_results else recent
        
        return jsonify({
            'success': True,
            'scans': recent,
            'count': len(recent)
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

