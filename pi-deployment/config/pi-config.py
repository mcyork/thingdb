"""
Raspberry Pi specific configuration for Flask Inventory System
"""
import os

def is_pi_deployment():
    """Check if running on Raspberry Pi deployment"""
    return os.environ.get('DEPLOYMENT_TYPE') == 'raspberry_pi'

def should_serve_images_from_files():
    """Check if images should be served from filesystem instead of database"""
    return os.environ.get('SERVE_IMAGES_FROM_FILES', 'false').lower() == 'true'

def get_image_file_path():
    """Get the path where image files are stored on Pi"""
    # Try new variable first, fall back to legacy for backward compatibility
    return (os.environ.get('IMAGE_DIR') or 
            os.environ.get('IMAGE_FILE_PATH', '/var/lib/inventory/images'))

def get_image_file_url(image_id, image_type='image'):
    """
    Get the URL for an image file on Pi deployment
    
    Args:
        image_id: Database image ID
        image_type: 'image', 'thumbnail', or 'original'
    
    Returns:
        URL path for nginx to serve the image file
    """
    if should_serve_images_from_files():
        return f"/{image_type}/{image_id}"
    else:
        # Fallback to database serving
        return f"/{image_type}/{image_id}"

def setup_pi_image_serving(app):
    """
    Configure Flask app for Pi-specific image serving
    """
    if is_pi_deployment():
        app.logger.info("🥧 Raspberry Pi deployment detected")
        app.logger.info(f"📁 Images served from: {get_image_file_path()}")
        
        # Add Pi-specific template globals
        @app.template_global()
        def image_url(image_id, image_type='image'):
            return get_image_file_url(image_id, image_type)
        
        @app.template_global()
        def is_pi_deployment_flag():
            return True
    else:
        app.logger.info("🐳 Standard deployment (Docker/development)")
        
        @app.template_global()
        def is_pi_deployment_flag():
            return False