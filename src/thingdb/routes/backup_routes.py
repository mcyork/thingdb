"""
Backup and Restore routes for Flask Inventory Management System
Handles database and filesystem backup/restore operations
"""
import os
import json
import shutil
import subprocess
import tempfile
import zipfile
import signal
import threading
import time
from datetime import datetime
from flask import Blueprint, jsonify, request, send_file, render_template
from thingdb.database import get_db_connection, DB_CONFIG
from thingdb.config import IMAGE_DIR, IMAGE_STORAGE_METHOD

backup_bp = Blueprint('backup', __name__)

# Backup configuration
BACKUP_DIR = '/var/lib/thingdb/backups'


@backup_bp.route('/backup')
def backup_page():
    """Backup management page"""
    return render_template('backup.html')
ALLOWED_EXTENSIONS = {'zip', 'sql', 'tar', 'gz'}

def allowed_file(filename):
    """Check if file extension is allowed"""
    return ('.' in filename and 
            filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS)


def ensure_backup_dir():
    """Ensure backup directory exists"""
    os.makedirs(BACKUP_DIR, exist_ok=True)
    return BACKUP_DIR


def get_backup_filename(prefix="backup"):
    """Generate backup filename with timestamp"""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    return f"{prefix}_{timestamp}"

@backup_bp.route('/api/backup/status')
def backup_status():
    """Get backup status and available backups"""
    try:
        ensure_backup_dir()
        
        # Get list of existing backups
        backups = []
        for filename in os.listdir(BACKUP_DIR):
            if filename.endswith('.zip'):
                filepath = os.path.join(BACKUP_DIR, filename)
                stat = os.stat(filepath)
                backups.append({
                    'filename': filename,
                    'size': stat.st_size,
                    'created': datetime.fromtimestamp(stat.st_mtime).isoformat(),
                    'size_human': format_file_size(stat.st_size)
                })
        
        # Sort by creation time (newest first)
        backups.sort(key=lambda x: x['created'], reverse=True)
        
        # Get database info
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT pg_size_pretty(pg_database_size(current_database()))")
        db_size = cursor.fetchone()[0]
        cursor.execute("SELECT COUNT(*) FROM items")
        item_count = cursor.fetchone()[0]
        cursor.execute("SELECT COUNT(*) FROM images")
        image_count = cursor.fetchone()[0]
        conn.close()
        
        # Get current upload limit from Flask config
        from flask import current_app
        max_upload = current_app.config.get('MAX_CONTENT_LENGTH', 0)
        max_upload_human = format_file_size(max_upload) if max_upload else 'Unlimited'
        
        return jsonify({
            'success': True,
            'backups': backups,
            'database_info': {
                'size': db_size,
                'item_count': item_count,
                'image_count': image_count
            },
            'backup_dir': BACKUP_DIR,
            'max_upload_size': max_upload,
            'max_upload_size_human': max_upload_human
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@backup_bp.route('/api/backup/create', methods=['POST'])
def create_backup():
    """Create a complete backup of database and files"""
    try:
        ensure_backup_dir()
        
        # Generate backup filename
        backup_name = get_backup_filename()
        backup_path = os.path.join(BACKUP_DIR, f"{backup_name}.zip")
        
        # Create temporary directory for backup files
        with tempfile.TemporaryDirectory() as temp_dir:
            db_file = os.path.join(temp_dir, "database.sql")
            images_dir = os.path.join(temp_dir, "images")
            
            # 1. Backup PostgreSQL database
            print(f"Creating database backup...")
            db_backup_success = create_database_backup(db_file)
            if not db_backup_success:
                return jsonify({
                    'success': False,
                    'error': 'Failed to create database backup'
                }), 500
            
            # 2. Backup image files (if using filesystem storage)
            if IMAGE_STORAGE_METHOD == 'filesystem':
                print(f"Creating filesystem backup...")
                if os.path.exists(IMAGE_DIR):
                    shutil.copytree(IMAGE_DIR, images_dir)
                else:
                    os.makedirs(images_dir)
            
            # 3. Create metadata file
            metadata = {
                'backup_date': datetime.now().isoformat(),
                'app_version': '1.3.0',
                'database_config': {
                    'host': DB_CONFIG.get('host'),
                    'database': DB_CONFIG.get('database'),
                    'port': DB_CONFIG.get('port')
                },
                'storage_method': IMAGE_STORAGE_METHOD,
                'image_dir': IMAGE_DIR if IMAGE_STORAGE_METHOD == 'filesystem' else None
            }
            
            with open(os.path.join(temp_dir, "metadata.json"), 'w') as f:
                json.dump(metadata, f, indent=2)
            
            # 4. Create ZIP archive
            print(f"Creating ZIP archive...")
            with zipfile.ZipFile(backup_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
                for root, dirs, files in os.walk(temp_dir):
                    for file in files:
                        file_path = os.path.join(root, file)
                        arc_name = os.path.relpath(file_path, temp_dir)
                        zipf.write(file_path, arc_name)
            
            # Get backup size
            backup_size = os.path.getsize(backup_path)
            
            return jsonify({
                'success': True,
                'message': 'Backup created successfully',
                'backup_file': f"{backup_name}.zip",
                'backup_size': format_file_size(backup_size),
                'backup_path': backup_path
            })
            
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

def create_database_backup(db_file):
    """Create PostgreSQL database backup"""
    try:
        # Get database config from environment variables (same as config.py)
        db_host = os.environ.get('POSTGRES_HOST', 'localhost')
        db_port = os.environ.get('POSTGRES_PORT', '5432')
        db_user = os.environ.get('POSTGRES_USER', 'thingdb')
        db_password = os.environ.get('POSTGRES_PASSWORD', 'thingdb_default_pass')
        db_name = os.environ.get('POSTGRES_DB', 'thingdb')
        
        # Build pg_dump command
        # NOTE: We don't use --create to avoid database-level commands
        # This makes backups portable across different database names
        cmd = [
            '/usr/bin/pg_dump',
            '--host', db_host,
            '--port', db_port,
            '--username', db_user,
            '--dbname', db_name,
            '--no-password',  # Use .pgpass or environment
            '--no-owner',     # Don't set ownership
            '--no-privileges', # Don't set privileges
            '--clean',        # Add DROP TABLE statements
            '--if-exists',    # Use IF EXISTS with DROP
            '--verbose',      # Verbose output
            '--file', db_file
        ]
        
        # Set environment variables for password
        env = os.environ.copy()
        env['PGPASSWORD'] = db_password
        
        # Run pg_dump
        result = subprocess.run(cmd, env=env, capture_output=True, text=True)
        
        if result.returncode != 0:
            print(f"pg_dump error: {result.stderr}")
            return False
        
        return True
        
    except Exception as e:
        print(f"Database backup error: {e}")
        return False

@backup_bp.route('/api/backup/download/<filename>')
def download_backup(filename):
    """Download a backup file"""
    try:
        # Security check - ensure filename is safe
        if not allowed_file(filename) or '..' in filename:
            return jsonify({'success': False, 'error': 'Invalid filename'}), 400
        
        backup_path = os.path.join(BACKUP_DIR, filename)
        if not os.path.exists(backup_path):
            return jsonify({'success': False, 'error': 'Backup not found'}), 404
        
        return send_file(backup_path, as_attachment=True, download_name=filename)
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@backup_bp.route('/api/backup/delete/<filename>', methods=['DELETE'])
def delete_backup(filename):
    """Delete a backup file"""
    try:
        # Security check
        if not allowed_file(filename) or '..' in filename:
            return jsonify({'success': False, 'error': 'Invalid filename'}), 400
        
        backup_path = os.path.join(BACKUP_DIR, filename)
        if not os.path.exists(backup_path):
            return jsonify({'success': False, 'error': 'Backup not found'}), 404
        
        os.remove(backup_path)
        
        return jsonify({
            'success': True,
            'message': f'Backup {filename} deleted successfully'
        })
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@backup_bp.route('/api/backup/restore', methods=['POST'])
def restore_backup():
    """Restore from an uploaded backup file"""
    try:
        if 'backup_file' not in request.files:
            return jsonify({'success': False, 'error': 'No backup file provided'}), 400
        
        file = request.files['backup_file']
        if file.filename == '':
            return jsonify({'success': False, 'error': 'No file selected'}), 400
        
        if not allowed_file(file.filename):
            return jsonify({'success': False, 'error': 'Invalid file type'}), 400
        
        # Save uploaded file temporarily
        with tempfile.NamedTemporaryFile(delete=False, suffix='.zip') as temp_file:
            file.save(temp_file.name)
            temp_path = temp_file.name
        
        try:
            # Extract and restore
            restore_success = restore_from_zip(temp_path)
            
            if restore_success:
                # Start application restart
                restart_application()
                return jsonify({
                    'success': True,
                    'message': 'Backup restored successfully. The application will restart automatically in a few seconds.'
                })
            else:
                return jsonify({
                    'success': False,
                    'error': 'Failed to restore backup'
                }), 500
                
        finally:
            # Clean up temporary file
            os.unlink(temp_path)
            
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@backup_bp.route('/api/backup/restore-existing/<filename>', methods=['POST'])
def restore_existing_backup(filename):
    """Restore from an existing backup file"""
    try:
        # Security check
        if not allowed_file(filename) or '..' in filename:
            return jsonify({'success': False, 'error': 'Invalid filename'}), 400
        
        backup_path = os.path.join(BACKUP_DIR, filename)
        if not os.path.exists(backup_path):
            return jsonify({'success': False, 'error': 'Backup not found'}), 404
        
        # Restore from the existing backup file
        restore_success = restore_from_zip(backup_path)
        
        if restore_success:
            # Start application restart
            restart_application()
            return jsonify({
                'success': True,
                'message': f'Backup {filename} restored successfully. The application will restart automatically in a few seconds.'
            })
        else:
            return jsonify({
                'success': False,
                'error': 'Failed to restore backup'
            }), 500
            
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

def restore_from_zip(zip_path):
    """Restore database and files from ZIP backup"""
    try:
        with tempfile.TemporaryDirectory() as temp_dir:
            # Extract ZIP file
            with zipfile.ZipFile(zip_path, 'r') as zipf:
                zipf.extractall(temp_dir)
            
            # Read metadata
            metadata_file = os.path.join(temp_dir, "metadata.json")
            if os.path.exists(metadata_file):
                with open(metadata_file, 'r') as f:
                    metadata = json.load(f)
            
            # 1. Restore database
            db_file = os.path.join(temp_dir, "database.sql")
            if os.path.exists(db_file):
                print("Restoring database...")
                if not restore_database(db_file):
                    return False
            
            # 2. Restore image files (if using filesystem storage)
            if IMAGE_STORAGE_METHOD == 'filesystem':
                print("Cleaning up existing image files...")
                # Always remove existing images directory to ensure clean restore
                if os.path.exists(IMAGE_DIR):
                    shutil.rmtree(IMAGE_DIR)
                
                images_dir = os.path.join(temp_dir, "images")
                if os.path.exists(images_dir):
                    print("Restoring image files...")
                    # Copy restored images
                    shutil.copytree(images_dir, IMAGE_DIR)
                else:
                    print("No image files in backup, creating empty images directory...")
                    os.makedirs(IMAGE_DIR, exist_ok=True)
            
            return True
            
    except Exception as e:
        print(f"Restore error: {e}")
        return False

def restore_database(db_file):
    """Restore PostgreSQL database from SQL file"""
    try:
        # Get database config from environment variables (same as config.py)
        db_host = os.environ.get('POSTGRES_HOST', 'localhost')
        db_port = os.environ.get('POSTGRES_PORT', '5432')
        db_user = os.environ.get('POSTGRES_USER', 'thingdb')
        db_password = os.environ.get('POSTGRES_PASSWORD', 'thingdb_default_pass')
        db_name = os.environ.get('POSTGRES_DB', 'thingdb')
        
        # Set environment variables for password
        env = os.environ.copy()
        env['PGPASSWORD'] = db_password
        
        # Clean the SQL file to work with current database
        # Remove database-level commands that would cause issues
        cleaned_sql_file = db_file + '.cleaned'
        with open(db_file, 'r') as infile:
            with open(cleaned_sql_file, 'w') as outfile:
                skip_until_connect = False
                for line in infile:
                    # Skip problematic commands
                    if any(cmd in line for cmd in [
                        'DROP DATABASE',
                        'CREATE DATABASE',
                        '\\connect'
                    ]):
                        skip_until_connect = True
                        continue
                    
                    # After \connect, we can continue
                    if skip_until_connect and 'SET ' in line:
                        skip_until_connect = False
                    
                    if not skip_until_connect:
                        outfile.write(line)
        
        # First, drop existing tables to ensure clean restore
        print("Dropping existing tables...")
        drop_cmd = [
            '/usr/bin/psql',
            '--host', db_host,
            '--port', db_port,
            '--username', db_user,
            '--dbname', db_name,
            '--no-password',
            '--command', 'DROP TABLE IF EXISTS items CASCADE; DROP TABLE IF EXISTS images CASCADE; DROP TABLE IF EXISTS categories CASCADE; DROP TABLE IF EXISTS text_content CASCADE; DROP TABLE IF EXISTS qr_aliases CASCADE;'
        ]
        
        drop_result = subprocess.run(drop_cmd, env=env, capture_output=True, text=True)
        if drop_result.returncode != 0:
            print(f"Drop tables warning: {drop_result.stderr}")
            # Continue anyway
        
        # Restore using the cleaned SQL file
        print(f"Restoring to database: {db_name}")
        cmd = [
            '/usr/bin/psql',
            '--host', db_host,
            '--port', db_port,
            '--username', db_user,
            '--dbname', db_name,
            '--no-password',
            '--file', cleaned_sql_file
        ]
        
        # Run psql restore
        result = subprocess.run(cmd, env=env, capture_output=True, text=True)
        
        # Clean up temp file
        os.unlink(cleaned_sql_file)
        
        if result.returncode != 0:
            print(f"psql restore error: {result.stderr}")
            return False
        
        print("Database restore completed successfully")
        return True
        
    except Exception as e:
        print(f"Database restore error: {e}")
        return False

@backup_bp.route('/api/backup/reset-database', methods=['POST'])
def reset_database():
    """Reset database to empty state - DELETES ALL DATA"""
    try:
        # Require confirmation text
        data = request.get_json()
        confirmation = data.get('confirmation', '').strip()
        
        if confirmation != 'DELETE EVERYTHING':
            return jsonify({
                'success': False, 
                'error': 'Confirmation text does not match. Type exactly: DELETE EVERYTHING'
            }), 400
        
        # Start reset in background thread to avoid timeout
        def do_reset():
            time.sleep(1)  # Let response be sent
            reset_database_to_empty()
        
        reset_thread = threading.Thread(target=do_reset)
        reset_thread.daemon = True
        reset_thread.start()
        
        return jsonify({
            'success': True,
            'message': 'Database reset started. Reloading in a moment...'
        })
            
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@backup_bp.route('/api/backup/demos')
def get_demo_backups():
    """Get list of available demo backup files"""
    try:
        # Demo directory in the application root
        demo_dir = '/var/lib/thingdb/demos'
        
        if not os.path.exists(demo_dir):
            return jsonify({
                'success': True,
                'demos': []
            })
        
        demos = []
        for filename in os.listdir(demo_dir):
            if filename.endswith('.zip'):
                filepath = os.path.join(demo_dir, filename)
                file_size = os.path.getsize(filepath)
                file_mtime = os.path.getmtime(filepath)
                
                # Extract demo name from filename (remove .zip and underscores)
                demo_name = filename.replace('.zip', '').replace('_', ' ').title()
                
                demos.append({
                    'filename': filename,
                    'name': demo_name,
                    'size': format_file_size(file_size),
                    'date': datetime.fromtimestamp(file_mtime).strftime('%Y-%m-%d %H:%M:%S')
                })
        
        # Sort by name
        demos.sort(key=lambda x: x['name'])
        
        return jsonify({
            'success': True,
            'demos': demos
        })
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@backup_bp.route('/api/backup/restore-demo/<filename>', methods=['POST'])
def restore_demo_backup(filename):
    """Restore from a demo backup file"""
    try:
        # Security check
        if not allowed_file(filename) or '..' in filename:
            return jsonify({'success': False, 'error': 'Invalid filename'}), 400
        
        demo_path = os.path.join('/var/lib/thingdb/demos', filename)
        if not os.path.exists(demo_path):
            return jsonify({'success': False, 'error': 'Demo backup not found'}), 404
        
        # Restore from the demo backup file
        restore_success = restore_from_zip(demo_path)
        
        if restore_success:
            # Start application restart
            restart_application()
            return jsonify({
                'success': True,
                'message': f'Demo "{filename}" loaded successfully. The application will restart automatically in a few seconds.'
            })
        else:
            return jsonify({
                'success': False,
                'error': 'Failed to restore demo backup'
            }), 500
            
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

def reset_database_to_empty():
    """Drop all tables and reinitialize empty database"""
    try:
        # Get database config
        db_host = os.environ.get('POSTGRES_HOST', 'localhost')
        db_port = os.environ.get('POSTGRES_PORT', '5432')
        db_user = os.environ.get('POSTGRES_USER', 'thingdb')
        db_password = os.environ.get('POSTGRES_PASSWORD', 'thingdb_default_pass')
        db_name = os.environ.get('POSTGRES_DB', 'thingdb')
        
        # Set environment variables for password
        env = os.environ.copy()
        env['PGPASSWORD'] = db_password
        
        print("Resetting database to empty state...")
        
        # Drop all tables - use psql without timeout
        drop_cmd = [
            '/usr/bin/psql',
            '--host', db_host,
            '--port', db_port,
            '--username', db_user,
            '--dbname', db_name,
            '--no-password',
            '--command', 'DROP TABLE IF EXISTS items CASCADE; DROP TABLE IF EXISTS images CASCADE; DROP TABLE IF EXISTS categories CASCADE; DROP TABLE IF EXISTS text_content CASCADE; DROP TABLE IF EXISTS qr_aliases CASCADE; DROP TABLE IF EXISTS _schema_version CASCADE;'
        ]
        
        drop_result = subprocess.run(drop_cmd, env=env, capture_output=True, text=True, timeout=30)
        if drop_result.returncode != 0:
            print(f"Drop tables error: {drop_result.stderr}")
            return False
        
        print(f"Drop tables output: {drop_result.stdout}")
        
        # Clean up image directory
        if IMAGE_STORAGE_METHOD == 'filesystem' and os.path.exists(IMAGE_DIR):
            print("Cleaning up image files...")
            shutil.rmtree(IMAGE_DIR)
            os.makedirs(IMAGE_DIR, exist_ok=True)
        
        # Reinitialize database schema with timeout protection
        print("Reinitializing database schema...")
        try:
            from thingdb.database import init_database
            init_database()
            print("Database reset completed successfully")
        except Exception as init_error:
            print(f"Schema init error (will auto-init on next access): {init_error}")
            # Not fatal - schema will be created on next DB access
        
        return True
        
    except subprocess.TimeoutExpired:
        print("Database reset timeout - operation took too long")
        return False
    except Exception as e:
        print(f"Database reset error: {e}")
        return False

def restart_application():
    """Restart the application by stopping the current process"""
    def delayed_restart():
        # Wait a moment to allow the response to be sent
        time.sleep(2)
        # Send SIGTERM to the current process
        os.kill(os.getpid(), signal.SIGTERM)
    
    # Start restart in a separate thread
    restart_thread = threading.Thread(target=delayed_restart)
    restart_thread.daemon = True
    restart_thread.start()


def format_file_size(size_bytes):
    """Format file size in human readable format"""
    if size_bytes == 0:
        return "0B"
    
    size_names = ["B", "KB", "MB", "GB", "TB"]
    i = 0
    while size_bytes >= 1024 and i < len(size_names) - 1:
        size_bytes /= 1024.0
        i += 1
    
    return f"{size_bytes:.1f}{size_names[i]}"
