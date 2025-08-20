"""
Database connection and initialization for Flask Inventory Management System
"""
import psycopg2
from config import DB_CONFIG, IMAGE_STORAGE_METHOD

# Connection pool for database connections
_connection_pool = []
_MAX_POOL_SIZE = 5

def get_db_connection():
    """Get database connection from pool or create new one"""
    global _connection_pool
    
    if _connection_pool:
        try:
            conn = _connection_pool.pop()
            # Test if connection is still alive
            conn.cursor().execute('SELECT 1')
            return conn
        except:
            pass
    
    return psycopg2.connect(**DB_CONFIG)

def return_db_connection(conn):
    """Return connection to pool"""
    global _connection_pool
    
    if len(_connection_pool) < _MAX_POOL_SIZE:
        _connection_pool.append(conn)
    else:
        conn.close()

def init_database():
    """Initialize database tables and columns"""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # Create items table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS items (
            guid VARCHAR(36) PRIMARY KEY,
            item_name VARCHAR(255),
            description TEXT,
            source_url TEXT,
            created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    # Add columns if they don't exist
    _add_column_if_not_exists(cursor, 'items', 'source_url', 'TEXT')
    _add_column_if_not_exists(cursor, 'items', 'item_name', 'VARCHAR(255)')
    _add_column_if_not_exists(cursor, 'items', 'description', 'TEXT')
    _add_column_if_not_exists(cursor, 'items', 'parent_guid', 'VARCHAR(36) REFERENCES items(guid) ON DELETE SET NULL')
    _add_column_if_not_exists(cursor, 'items', 'embedding_vector', 'TEXT')
    _add_column_if_not_exists(cursor, 'items', 'label_number', 'INTEGER')
    
    # Create sequence for label numbers if not exists
    cursor.execute('''
        CREATE SEQUENCE IF NOT EXISTS label_number_seq 
        START WITH 1 INCREMENT BY 1 NO CYCLE
    ''')
    
    # Determine the data type for image storage
    image_column_type = 'TEXT' if IMAGE_STORAGE_METHOD == 'filesystem' else 'BYTEA'

    # Create images table
    cursor.execute(f'''
        CREATE TABLE IF NOT EXISTS images (
            id SERIAL PRIMARY KEY,
            item_guid VARCHAR(36) REFERENCES items(guid) ON DELETE CASCADE,
            filename VARCHAR(255) NOT NULL,
            image_data {image_column_type} NOT NULL,
            thumbnail_data {image_column_type},
            preview_data {image_column_type},
            content_type VARCHAR(100) NOT NULL,
            rotation_degrees INTEGER DEFAULT 0,
            is_primary BOOLEAN DEFAULT FALSE,
            upload_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            description TEXT,
            ocr_text TEXT,
            ai_description TEXT
        )
    ''')
    
    # Add image columns if they don't exist
    # Add image columns if they don't exist
    _add_column_if_not_exists(cursor, 'images', 'preview_data', 'BYTEA')
    _add_column_if_not_exists(cursor, 'images', 'is_primary', 'BOOLEAN DEFAULT FALSE')
    _add_column_if_not_exists(cursor, 'images', 'description', 'TEXT')
    _add_column_if_not_exists(cursor, 'images', 'ocr_text', 'TEXT')
    _add_column_if_not_exists(cursor, 'images', 'ai_description', 'TEXT')
    _add_column_if_not_exists(cursor, 'images', 'image_path', 'TEXT')
    _add_column_if_not_exists(cursor, 'images', 'thumbnail_path', 'TEXT')
    _add_column_if_not_exists(cursor, 'images', 'preview_path', 'TEXT')
    
    # Create text_content table (legacy)
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS text_content (
            id SERIAL PRIMARY KEY,
            item_guid VARCHAR(36) REFERENCES items(guid) ON DELETE CASCADE,
            content TEXT NOT NULL,
            content_type VARCHAR(50) DEFAULT 'text',
            created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    # Create categories table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS categories (
            id SERIAL PRIMARY KEY,
            item_guid VARCHAR(36) REFERENCES items(guid) ON DELETE CASCADE,
            category_name VARCHAR(100) NOT NULL,
            created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    # Create qr_aliases table for QR code mappings
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS qr_aliases (
            id SERIAL PRIMARY KEY,
            qr_code VARCHAR(255) NOT NULL UNIQUE,
            item_guid VARCHAR(36) REFERENCES items(guid) ON DELETE CASCADE,
            created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    conn.commit()
    conn.close()

def _add_column_if_not_exists(cursor, table_name, column_name, column_type):
    """Helper function to add column if it doesn't exist"""
    cursor.execute("""
        SELECT column_name 
        FROM information_schema.columns 
        WHERE table_name = %s AND column_name = %s
    """, (table_name, column_name))
    
    if not cursor.fetchone():
        cursor.execute(f'ALTER TABLE {table_name} ADD COLUMN {column_name} {column_type}')

def get_pool_stats():
    """Get connection pool statistics"""
    return {
        'active_connections': len(_connection_pool),
        'max_pool_size': _MAX_POOL_SIZE
    }

def get_connection_pool_info():
    """Get connection pool information (alias for get_pool_stats)"""
    return get_pool_stats()