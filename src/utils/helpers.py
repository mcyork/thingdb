"""
Utility functions and helpers for Flask Inventory Management System
"""
import uuid
import hashlib
from datetime import datetime
from config import IMAGE_SETTINGS

def generate_guid():
    """Generate a new GUID for items"""
    return str(uuid.uuid4())

def is_valid_guid(guid_string):
    """Check if a string is a valid GUID"""
    try:
        uuid.UUID(guid_string)
        return True
    except ValueError:
        return False

def generate_etag(data):
    """Generate ETag for HTTP caching"""
    if isinstance(data, str):
        data = data.encode('utf-8')
    return hashlib.md5(data).hexdigest()

def format_file_size(size_bytes):
    """Format file size in human readable format"""
    if size_bytes == 0:
        return "0 B"
    
    size_names = ["B", "KB", "MB", "GB"]
    i = 0
    while size_bytes >= 1024.0 and i < len(size_names) - 1:
        size_bytes /= 1024.0
        i += 1
    
    return f"{size_bytes:.1f} {size_names[i]}"

def format_timestamp(timestamp):
    """Format timestamp for display"""
    if not timestamp:
        return "N/A"
    
    if isinstance(timestamp, str):
        try:
            timestamp = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
        except:
            return timestamp
    
    return timestamp.strftime("%Y-%m-%d %H:%M")

def sanitize_filename(filename):
    """Sanitize filename for safe storage"""
    import re
    # Remove or replace unsafe characters
    filename = re.sub(r'[<>:"/\\|?*]', '_', filename)
    # Limit length
    if len(filename) > 255:
        name, ext = filename.rsplit('.', 1) if '.' in filename else (filename, '')
        max_name_len = 255 - len(ext) - 1
        filename = name[:max_name_len] + ('.' + ext if ext else '')
    
    return filename

def is_allowed_file_type(filename):
    """Check if file type is allowed for upload"""
    if not filename:
        return False
    
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in IMAGE_SETTINGS['allowed_extensions']

def get_file_extension(filename):
    """Get file extension from filename"""
    if not filename or '.' not in filename:
        return ''
    return filename.rsplit('.', 1)[1].lower()

def get_content_type(filename):
    """Get content type from filename"""
    ext = get_file_extension(filename)
    content_types = {
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'gif': 'image/gif',
        'webp': 'image/webp'
    }
    return content_types.get(ext, 'application/octet-stream')

def clean_search_query(query):
    """Clean and normalize search query"""
    if not query:
        return ''
    
    return str(query).strip().lower()

def extract_tags_from_query(query):
    """Extract hashtag-style tags from search query"""
    import re
    if not query:
        return [], query
    
    # Find all #tag patterns
    tags = re.findall(r'#(\w+)', query)
    # Remove tags from query
    clean_query = re.sub(r'#\w+', '', query).strip()
    
    return tags, clean_query

def paginate_results(results, page=1, per_page=50):
    """Simple pagination for results"""
    if not results:
        return [], 0, 0
    
    total = len(results)
    start = (page - 1) * per_page
    end = start + per_page
    
    return results[start:end], total, page

def validate_item_data(data):
    """Validate item data for creation/update"""
    errors = []
    
    if not data.get('item_name', '').strip():
        errors.append("Item name is required")
    
    if len(data.get('item_name', '')) > 255:
        errors.append("Item name must be less than 255 characters")
    
    if data.get('description') and len(data['description']) > 10000:
        errors.append("Description must be less than 10,000 characters")
    
    return errors