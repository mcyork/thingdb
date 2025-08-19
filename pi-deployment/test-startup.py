#!/usr/bin/env python3
"""
Test script to debug Flask application startup issues
"""
import sys
import os

# Load environment variables from file
env_file = '/var/lib/inventory/config/environment.env'
if os.path.exists(env_file):
    print(f"Loading environment from {env_file}")
    with open(env_file) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                key, value = line.split('=', 1)
                os.environ[key] = value
                
# Add the current directory to Python path
sys.path.insert(0, '/var/lib/inventory/app/src')

try:
    print("Testing Flask application startup...")
    
    # Test importing config
    print("1. Testing config import...")
    from config import APP_VERSION, FLASK_CONFIG, DB_CONFIG
    print(f"   ✅ Config loaded. Version: {APP_VERSION}")
    print(f"   ✅ DB Config: {DB_CONFIG}")
    
    # Test database connection
    print("2. Testing database connection...")
    import psycopg2
    conn = psycopg2.connect(**DB_CONFIG)
    cursor = conn.cursor()
    cursor.execute("SELECT version();")
    version = cursor.fetchone()
    print(f"   ✅ Database connected: {version[0][:50]}...")
    cursor.close()
    conn.close()
    
    # Test imports
    print("3. Testing route imports...")
    from routes.core_routes import core_bp
    from routes.image_routes import image_bp
    from routes.item_routes import item_bp
    from routes.search_routes import search_bp
    from routes.relationship_routes import relationship_bp
    from routes.admin_routes import admin_bp
    print("   ✅ All route blueprints imported successfully")
    
    # Test app creation
    print("4. Testing app creation...")
    from main import create_app
    app = create_app()
    print(f"   ✅ Flask app created successfully")
    print(f"   ✅ App name: {app.name}")
    print(f"   ✅ Debug mode: {app.debug}")
    
    print("\n🎉 All tests passed! The application should start correctly.")
    
except Exception as e:
    print(f"\n❌ Error during startup test: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)