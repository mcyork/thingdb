"""
Configuration settings for Flask Inventory Management System
"""
import os

# Application configuration
APP_VERSION = "1.4.17"
APP_RELEASE_CANDIDATE = os.environ.get('RELEASE_CANDIDATE')
MAX_CONTENT_LENGTH = 16 * 1024 * 1024  # 16MB max file size

# Database configuration - prioritize external PostgreSQL settings
def get_db_config():
    """Get database configuration with fallbacks"""
    # Check for external PostgreSQL settings first
    external_host = os.environ.get('EXTERNAL_POSTGRES_HOST')
    if external_host:
        return {
            'host': external_host,
            'database': os.environ.get('EXTERNAL_POSTGRES_DB', 
                                     'inventory_db'),
            'user': os.environ.get('EXTERNAL_POSTGRES_USER', 
                                 'inventory'),
            'password': os.environ.get('EXTERNAL_POSTGRES_PASSWORD', 
                                    'inventory_pass'),
            'port': int(os.environ.get('EXTERNAL_POSTGRES_PORT', '5432'))
        }
    
    # Fallback to internal PostgreSQL settings
    return {
        'host': os.environ.get('POSTGRES_HOST', 'localhost'),
        'database': os.environ.get('POSTGRES_DB', 'thingdb'),
        'user': os.environ.get('POSTGRES_USER', 'thingdb'),
        'password': os.environ.get('POSTGRES_PASSWORD', 'thingdb_default_pass'),
        'port': int(os.environ.get('POSTGRES_PORT', '5432'))
    }

# Initialize DB_CONFIG
DB_CONFIG = get_db_config()

# Cache configuration
CACHE_SETTINGS = {
    'thumbnail_cache': {
        'max_size': 200,
        'max_age': 1800  # 30 minutes
    },
    'image_cache': {
        'max_size': 50,
        'max_age': 900   # 15 minutes
    }
}

# Image processing settings
IMAGE_STORAGE_METHOD = os.environ.get('IMAGE_STORAGE_METHOD', 'filesystem') # Always use filesystem
IMAGE_DIR = os.environ.get('IMAGE_DIR', '/var/lib/thingdb/images')

IMAGE_SETTINGS = {
    'thumbnail_size': (200, 200),
    'preview_size': (800, 800),
    'max_file_size': MAX_CONTENT_LENGTH,
    'allowed_extensions': {'png', 'jpg', 'jpeg', 'gif', 'webp'}
}

# Semantic search settings
SEMANTIC_SEARCH = {
    'model_name': 'all-MiniLM-L6-v2',
    'similarity_threshold': 0.15,
    'max_results': 50
}

# Flask app configuration
class Config:
    MAX_CONTENT_LENGTH = MAX_CONTENT_LENGTH
    SECRET_KEY = os.environ.get('SECRET_KEY') or 'dev-key-change-in-production'
    
    # Development settings
    DEBUG = os.environ.get('FLASK_DEBUG', '1') == '1'
    TESTING = False

# Export Flask configuration as a dictionary
FLASK_CONFIG = {
    'MAX_CONTENT_LENGTH': MAX_CONTENT_LENGTH,
    'SECRET_KEY': os.environ.get('SECRET_KEY') or 'dev-key-change-in-production',
    'DEBUG': os.environ.get('FLASK_DEBUG', '1') == '1',
    'TESTING': False
}