"""
Embedding service for semantic search functionality
"""
import json
import numpy as np
from thingdb.config import SEMANTIC_SEARCH

# Global embedding model instance (pre-loaded)
_embedding_model = None

def initialize_embedding_model():
    """Initialize the embedding model at startup with proper caching"""
    global _embedding_model
    if _embedding_model is None:
        try:
            import os
            from sentence_transformers import SentenceTransformer
            
            # Set up proper cache directory for Hugging Face models
            cache_dir = "/var/lib/inventory/cache/models"
            os.environ['HF_HOME'] = cache_dir
            os.environ['TRANSFORMERS_CACHE'] = cache_dir
            
            # Ensure cache directory exists
            os.makedirs(cache_dir, exist_ok=True)
            
            print(f"[DEBUG] Loading embedding model at startup (cache: {cache_dir})...")
            _embedding_model = SentenceTransformer(
                SEMANTIC_SEARCH['model_name'],
                cache_folder=cache_dir
            )
            print("[DEBUG] Embedding model loaded successfully")
            
            # Verify model is cached
            model_path1 = os.path.join(cache_dir, "sentence-transformers", SEMANTIC_SEARCH['model_name'])
            model_path2 = os.path.join(cache_dir, f"models--sentence-transformers--{SEMANTIC_SEARCH['model_name']}")
            
            if os.path.exists(model_path1):
                print(f"[DEBUG] Model cached at: {model_path1}")
            elif os.path.exists(model_path2):
                print(f"[DEBUG] Model cached at: {model_path2}")
            else:
                print("[WARNING] Model may not be properly cached")
                
        except Exception as e:
            print(f"[ERROR] Failed to load embedding model: {e}")
            _embedding_model = False  # Mark as failed to avoid retries
    return _embedding_model if _embedding_model is not False else None

def get_embedding_model():
    """Get the pre-loaded embedding model"""
    global _embedding_model
    if _embedding_model is None:
        # Fallback to lazy loading if not pre-initialized
        return initialize_embedding_model()
    return _embedding_model if _embedding_model is not False else None

def generate_embedding(text):
    """Generate embedding vector for text"""
    model = get_embedding_model()
    if not model:
        return None
    
    try:
        # Combine and clean text
        clean_text = str(text).strip() if text else ""
        if not clean_text:
            return None
            
        # Generate embedding
        embedding = model.encode(clean_text)
        return embedding.tolist()  # Convert to list for JSON storage
    except Exception as e:
        print(f"[ERROR] Failed to generate embedding: {e}")
        return None

def cosine_similarity(vec1, vec2):
    """Calculate cosine similarity between two vectors"""
    try:
        # Ensure vectors are lists/arrays
        if isinstance(vec1, dict) or isinstance(vec2, dict):
            print(f"[ERROR] Invalid vector type: vec1={type(vec1)}, vec2={type(vec2)}")
            return 0
            
        # Convert to numpy arrays
        vec1 = np.array(vec1, dtype=float)
        vec2 = np.array(vec2, dtype=float)
        
        # Verify shapes
        if vec1.shape != vec2.shape:
            print(f"[ERROR] Vector shape mismatch: {vec1.shape} vs {vec2.shape}")
            return 0
        
        dot_product = np.dot(vec1, vec2)
        norm1 = np.linalg.norm(vec1)
        norm2 = np.linalg.norm(vec2)
        
        if norm1 == 0 or norm2 == 0:
            return 0
            
        return dot_product / (norm1 * norm2)
    except Exception as e:
        print(f"[ERROR] Cosine similarity calculation failed: {e}")
        return 0

def parse_embedding_from_db(embedding_json):
    """Parse embedding vector from database JSON format"""
    if not embedding_json:
        return None
    
    try:
        if isinstance(embedding_json, str):
            return json.loads(embedding_json)
        return embedding_json
    except Exception as e:
        print(f"[ERROR] Failed to parse embedding: {e}")
        return None

def is_embedding_model_available():
    """Check if embedding model is available"""
    return get_embedding_model() is not None

def clear_embedding_model():
    """Clear the cached embedding model (for testing/memory management)"""
    global _embedding_model
    _embedding_model = None


def is_model_cached():
    """Check if the embedding model is cached locally"""
    try:
        import os
        cache_dir = "/var/lib/inventory/cache/models"
        # Check both possible cache directory structures
        model_path1 = os.path.join(cache_dir, "sentence-transformers", SEMANTIC_SEARCH['model_name'])
        model_path2 = os.path.join(cache_dir, f"models--sentence-transformers--{SEMANTIC_SEARCH['model_name']}")
        return os.path.exists(model_path1) or os.path.exists(model_path2)
    except Exception:
        return False


def get_cache_info():
    """Get information about model caching"""
    try:
        import os
        cache_dir = "/var/lib/inventory/cache/models"
        # Check both possible cache directory structures
        model_path1 = os.path.join(cache_dir, "sentence-transformers", SEMANTIC_SEARCH['model_name'])
        model_path2 = os.path.join(cache_dir, f"models--sentence-transformers--{SEMANTIC_SEARCH['model_name']}")
        
        # Determine which path exists
        if os.path.exists(model_path1):
            model_path = model_path1
        elif os.path.exists(model_path2):
            model_path = model_path2
        else:
            return {
                'cached': False,
                'path': model_path1,
                'size_mb': 0
            }
        
        # Calculate size
        size = sum(os.path.getsize(os.path.join(dirpath, filename))
                  for dirpath, dirnames, filenames in os.walk(model_path)
                  for filename in filenames)
        
        return {
            'cached': True,
            'path': model_path,
            'size_mb': round(size / (1024 * 1024), 2)
        }
    except Exception as e:
        return {
            'cached': False,
            'error': str(e)
        }