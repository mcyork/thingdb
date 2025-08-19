"""
Embedding service for semantic search functionality
"""
import json
import numpy as np
from config import SEMANTIC_SEARCH

# Global embedding model instance (lazy loaded)
_embedding_model = None

def get_embedding_model():
    """Lazy load the embedding model to avoid startup delays"""
    global _embedding_model
    if _embedding_model is None:
        try:
            from sentence_transformers import SentenceTransformer
            print("[DEBUG] Loading embedding model (first use only)...")
            _embedding_model = SentenceTransformer(SEMANTIC_SEARCH['model_name'])
            print("[DEBUG] Embedding model loaded successfully")
        except Exception as e:
            print(f"[ERROR] Failed to load embedding model: {e}")
            _embedding_model = False  # Mark as failed to avoid retries
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