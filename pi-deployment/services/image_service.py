"""
Image processing service for thumbnail and preview generation
"""
import io
from PIL import Image
from config import IMAGE_SETTINGS

def generate_thumbnail(image_data, max_size=None, rotation=0):
    """Generate optimized thumbnail from image data with rotation"""
    if max_size is None:
        max_size = IMAGE_SETTINGS['thumbnail_size']
    
    try:
        # Open image from bytes
        image = Image.open(io.BytesIO(image_data))
        
        # Convert to RGB if necessary
        if image.mode != 'RGB':
            image = image.convert('RGB')
        
        # Apply rotation
        if rotation != 0:
            image = image.rotate(-rotation, expand=True)  # Negative for clockwise
        
        # Create thumbnail with better resampling
        image.thumbnail(max_size, Image.Resampling.LANCZOS)
        
        # Save to bytes with optimized settings for small size
        output = io.BytesIO()
        try:
            # Use WebP for much smaller thumbnails
            image.save(output, 
                      format='WebP', 
                      quality=70,           # Lower quality for smaller file
                      optimize=True,        # Optimize for size
                      lossless=False)       # Use lossy compression
        except Exception:
            # Fallback to JPEG if WebP fails
            image.save(output, 
                      format='JPEG', 
                      quality=75,           # Lower quality for smaller file
                      optimize=True)
        
        output.seek(0)
        return output.getvalue()
    except Exception as e:
        print(f"Thumbnail generation failed: {e}")
        return None

def generate_preview(image_data, max_size=None, rotation=0):
    """Generate low-resolution preview from image data"""
    if max_size is None:
        max_size = IMAGE_SETTINGS['preview_size']
    
    try:
        # Open image from bytes
        image = Image.open(io.BytesIO(image_data))
        
        # Convert to RGB if necessary
        if image.mode != 'RGB':
            image = image.convert('RGB')
        
        # Apply rotation
        if rotation != 0:
            image = image.rotate(-rotation, expand=True)
        
        # Resize to preview size
        image.thumbnail(max_size, Image.Resampling.LANCZOS)
        
        # Save to bytes with optimal compression for fast loading
        output = io.BytesIO()
        try:
            # Use WebP for much smaller previews
            image.save(output, format='WebP', quality=75, optimize=True, lossless=False)
        except Exception:
            # Fallback to JPEG if WebP fails
            image.save(output, format='JPEG', quality=60, optimize=True)
        output.seek(0)
        
        return output.getvalue()
    except Exception as e:
        print(f"Preview generation failed: {e}")
        return None

def apply_rotation_to_image(image_data, rotation_degrees):
    """Apply rotation to image data and return modified image"""
    if rotation_degrees == 0:
        return image_data
    
    try:
        image = Image.open(io.BytesIO(image_data))
        
        # Apply rotation
        rotated_image = image.rotate(-rotation_degrees, expand=True)
        
        # Save back to bytes
        output = io.BytesIO()
        format = image.format or 'JPEG'
        rotated_image.save(output, format=format, quality=95)
        output.seek(0)
        
        return output.getvalue()
    except Exception as e:
        print(f"Image rotation failed: {e}")
        return image_data  # Return original if rotation fails

def get_image_info(image_data):
    """Get basic information about an image"""
    try:
        image = Image.open(io.BytesIO(image_data))
        return {
            'size': image.size,
            'mode': image.mode,
            'format': image.format,
            'file_size': len(image_data)
        }
    except Exception as e:
        print(f"Failed to get image info: {e}")
        return None

def is_valid_image(image_data):
    """Check if image data is a valid image"""
    try:
        image = Image.open(io.BytesIO(image_data))
        image.verify()  # Verify the image
        return True
    except Exception:
        return False

def optimize_image_for_storage(image_data, max_quality=85):
    """Optimize image for database storage while maintaining quality"""
    try:
        image = Image.open(io.BytesIO(image_data))
        
        # Convert to RGB if necessary
        if image.mode not in ('RGB', 'L'):
            image = image.convert('RGB')
        
        # Save with optimization
        output = io.BytesIO()
        if image.format == 'PNG' and image.mode == 'RGBA':
            # Keep PNG format for transparency
            image.save(output, format='PNG', optimize=True)
        else:
            # Use JPEG for better compression
            image.save(output, format='JPEG', quality=max_quality, optimize=True)
        
        output.seek(0)
        return output.getvalue()
    except Exception as e:
        print(f"Image optimization failed: {e}")
        return image_data  # Return original if optimization fails