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
        Path('/var/lib/thingdb/app/.env'),  # System deployment (production)
        Path('.env'),  # Current directory (development)
        Path('../.env'),  # One level up from src/
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
from flask import Flask, render_template, request, jsonify
from thingdb import config
from thingdb.database import init_database
from thingdb.models import image_cache, thumbnail_cache
from thingdb.services.embedding_service import initialize_embedding_model

# Import all blueprints
from thingdb.routes.core_routes import core_bp
from thingdb.routes.image_routes import image_bp
from thingdb.routes.item_routes import item_bp
from thingdb.routes.search_routes import search_bp
from thingdb.routes.relationship_routes import relationship_bp
from thingdb.routes.admin_routes import admin_bp
# from thingdb.routes.printing_routes import printing_bp  # COMMENTED OUT - BROKE NETWORK
from thingdb.routes.backup_routes import backup_bp
from thingdb.routes.scanner_routes import scanner_bp


def create_app():
    """Create and configure the Flask application"""
    app = Flask(__name__)
    
    # Configure Flask
    app.config.update(config.FLASK_CONFIG)
    
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
    app.register_blueprint(scanner_bp)
    
    # Error handlers
    @app.errorhandler(404)
    def not_found(error):
        # Return JSON for API endpoints, HTML for web pages
        if request.path.startswith('/api/'):
            return jsonify({
                'success': False,
                'error': 'Endpoint not found'
            }), 404
        return render_template('error.html',
                             heading='❌ Page Not Found',
                             message='The requested page could not be found.'), 404
    
    @app.errorhandler(500)
    def internal_error(error):
        return render_template('error.html',
                             heading='❌ Internal Server Error',
                             message='An internal server error occurred. Please try again later.'), 500
    
    # Custom template filters
    @app.template_filter('urlize_safe')
    def urlize_safe(text):
        """Convert URLs to clickable links with security attributes"""
        if not text:
            return text
        
        import re
        from markupsafe import Markup
        
        # Pattern to match URLs
        url_pattern = r'(https?://[^\s<>"{}|\\^`\[\]]+)'
        
        def make_link(match):
            url = match.group(1)
            return f'<a href="{url}" target="_blank" rel="noopener noreferrer">{url}</a>'
        
        # Replace URLs with clickable links
        result = re.sub(url_pattern, make_link, text)
        return Markup(result)
    
    # Template context processors
    @app.context_processor
    def inject_version():
        return {
            'app_version': config.APP_VERSION,
            'app_rc': config.APP_RELEASE_CANDIDATE
        }
    
    @app.context_processor
    def inject_cache_stats():
        return {
            'cache_stats': {
                'images': len(image_cache.cache),
                'thumbnails': len(thumbnail_cache.cache)
            }
        }
    
    # Add security and cache control headers
    @app.after_request
    def add_security_headers(response):
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['X-Frame-Options'] = 'SAMEORIGIN'
        response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
        response.headers['Pragma'] = 'no-cache'
        response.headers['Expires'] = '0'
        return response
    
    return app


# Create the application instance
app = create_app()

if __name__ == '__main__':
    print(f"Starting Flask Inventory Management System v{config.APP_VERSION}")
    print("Available routes:")
    for rule in app.url_map.iter_rules():
        print(f"  {rule.endpoint:30} {rule.rule}")
    
    app.run(
        debug=config.FLASK_CONFIG.get('DEBUG', True),
        host='0.0.0.0',
        port=5000
    )
