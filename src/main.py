"""
Main Flask application entry point
Coordinates all modules and blueprints for the Inventory Management System
"""
import os
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables BEFORE any other imports
def load_env_file():
    """Load environment variables from .env file using python-dotenv"""
    # Try multiple possible locations for .env file
    possible_paths = [
        Path('.env'),  # Current directory
        Path('/var/lib/inventory/app/.env'),  # Pi deployment (absolute)
        Path('/var/lib/inventory/config/.env'),  # Pi deployment
        Path('/var/lib/inventory/config/environment.env'),  # Pi deployment (fallback)
        Path('../config/.env'),  # Relative to src/
        Path('../config/environment.env'),  # Relative to src/ (fallback)
    ]
    
    for env_path in possible_paths:
        if env_path.exists():
            print(f"Loading environment from: {env_path}")
            load_dotenv(env_path, override=True)
            return True
    
    print("No .env file found, using system environment variables")
    return False


# Load environment variables early
load_env_file()


# Now import modules that depend on environment variables
from flask import Flask, render_template
from config import APP_VERSION, FLASK_CONFIG
from database import init_database
from models import image_cache, thumbnail_cache
from services.embedding_service import initialize_embedding_model

# Import all blueprints
from routes.core_routes import core_bp
from routes.image_routes import image_bp
from routes.item_routes import item_bp
from routes.search_routes import search_bp
from routes.relationship_routes import relationship_bp
from routes.admin_routes import admin_bp
# from routes.printing_routes import printing_bp  # COMMENTED OUT - BROKE NETWORK
from routes.backup_routes import backup_bp


def create_app():
    """Create and configure the Flask application"""
    app = Flask(__name__)
    
    # Configure Flask
    app.config.update(FLASK_CONFIG)
    
    # Initialize database
    init_database()
    
    # Pre-load embedding model to avoid cold start delays
    print("Pre-loading embedding model...")
    initialize_embedding_model()
    
    # Register blueprints
    app.register_blueprint(core_bp)
    app.register_blueprint(image_bp)
    app.register_blueprint(item_bp)
    app.register_blueprint(search_bp)
    app.register_blueprint(relationship_bp)
    app.register_blueprint(admin_bp)
    # app.register_blueprint(printing_bp)  # COMMENTED OUT - BROKE NETWORK
    app.register_blueprint(backup_bp)
    
    # Error handlers
    @app.errorhandler(404)
    def not_found(error):
        return render_template('error.html',
                             heading='❌ Page Not Found',
                             message='The requested page could not be found.'), 404
    
    @app.errorhandler(500)
    def internal_error(error):
        return render_template('error.html',
                             heading='❌ Internal Server Error',
                             message='An internal server error occurred. Please try again later.'), 500
    
    # Template context processors
    @app.context_processor
    def inject_version():
        return {'app_version': APP_VERSION}
    
    @app.context_processor
    def inject_cache_stats():
        return {
            'cache_stats': {
                'images': len(image_cache.cache),
                'thumbnails': len(thumbnail_cache.cache)
            }
        }
    
    return app


# Create the application instance
app = create_app()

if __name__ == '__main__':
    print(f"Starting Flask Inventory Management System v{APP_VERSION}")
    print("Available routes:")
    for rule in app.url_map.iter_rules():
        print(f"  {rule.endpoint:30} {rule.rule}")
    
    app.run(
        debug=FLASK_CONFIG.get('DEBUG', True),
        host='0.0.0.0',
        port=5000
    )