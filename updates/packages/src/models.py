"""
Data models and cache classes for Flask Inventory Management System
"""
import time
from collections import OrderedDict
from config import CACHE_SETTINGS

class ImageCache:
    """In-memory LRU cache for images with TTL expiration"""
    
    def __init__(self, max_size=100, max_age=3600):
        self.cache = OrderedDict()
        self.max_size = max_size
        self.max_age = max_age
        self.hits = 0
        self.misses = 0
        self.requests = 0
    
    def get(self, key):
        """Get item from cache if it exists and hasn't expired"""
        self.requests += 1
        if key in self.cache:
            data, timestamp = self.cache[key]
            if time.time() - timestamp < self.max_age:
                # Move to end (most recently used)
                self.cache.move_to_end(key)
                self.hits += 1
                return data
            else:
                # Expired
                del self.cache[key]
        self.misses += 1
        return None
    
    def set(self, key, data):
        """Add item to cache, removing oldest if at capacity"""
        if key in self.cache:
            # Update existing
            del self.cache[key]
        elif len(self.cache) >= self.max_size:
            # Remove oldest
            self.cache.popitem(last=False)
        
        self.cache[key] = (data, time.time())
    
    def clear(self):
        """Clear all cached items and reset statistics"""
        self.cache.clear()
        self.hits = 0
        self.misses = 0
        self.requests = 0

# Global cache instances
thumbnail_cache = ImageCache(
    max_size=CACHE_SETTINGS['thumbnail_cache']['max_size'],
    max_age=CACHE_SETTINGS['thumbnail_cache']['max_age']
)

image_cache = ImageCache(
    max_size=CACHE_SETTINGS['image_cache']['max_size'], 
    max_age=CACHE_SETTINGS['image_cache']['max_age']
)

# Data structures for type hints and documentation
class ItemData:
    """Structure for item database records"""
    def __init__(self, guid, name, description=None, created_date=None, updated_date=None, label_number=None):
        self.guid = guid
        self.name = name
        self.description = description
        self.created_date = created_date
        self.updated_date = updated_date
        self.label_number = label_number

class ImageData:
    """Structure for image database records"""
    def __init__(self, id, item_guid, filename, image_data, thumbnail_data=None, 
                 preview_data=None, content_type=None, rotation_degrees=0, 
                 is_primary=False, upload_date=None, description=None, 
                 ocr_text=None, ai_description=None):
        self.id = id
        self.item_guid = item_guid
        self.filename = filename
        self.image_data = image_data
        self.thumbnail_data = thumbnail_data
        self.preview_data = preview_data
        self.content_type = content_type
        self.rotation_degrees = rotation_degrees
        self.is_primary = is_primary
        self.upload_date = upload_date
        self.description = description
        self.ocr_text = ocr_text
        self.ai_description = ai_description

class SearchResult:
    """Structure for search results"""
    def __init__(self, guid, name, similarity=None, match_type='traditional', 
                 matched_tags=None, description=None, has_image=False, 
                 image_id=None, label_number=None, contained_count=0):
        self.guid = guid
        self.name = name
        self.similarity = similarity
        self.match_type = match_type
        self.matched_tags = matched_tags
        self.description = description
        self.has_image = has_image
        self.image_id = image_id
        self.label_number = label_number
        self.contained_count = contained_count