"""
Admin routes for Flask Inventory Management System
Handles health checks, system monitoring, and administration functions
"""
import json
import psutil
from datetime import datetime, timedelta
from flask import Blueprint, jsonify, render_template
from database import get_db_connection, get_connection_pool_info
from models import image_cache, thumbnail_cache
from services.embedding_service import is_embedding_model_available
from config import APP_VERSION

admin_bp = Blueprint('admin', __name__)

@admin_bp.route('/health')
def health_check():
    """JSON health check endpoint for HAProxy monitoring"""
    try:
        # Test database connection
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute('SELECT 1')
        cursor.fetchone()
        conn.close()
        
        return jsonify({
            "status": "healthy",
            "timestamp": datetime.utcnow().isoformat(),
            "version": APP_VERSION,
            "database": "ok"
        })
    except Exception as e:
        return jsonify({
            "status": "unhealthy",
            "timestamp": datetime.utcnow().isoformat(),
            "version": APP_VERSION,
            "error": str(e)
        }), 503

@admin_bp.route('/system-status')
def system_status():
    """Human-friendly system status page"""
    import time
    
    try:
        start_time = time.time()
        
        # Test database connection and get some stats
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Database connection test
        db_start = time.time()
        cursor.execute('SELECT 1')
        db_response_time = (time.time() - db_start) * 1000  # Convert to ms
        
        # Get cache stats
        cache_stats = {
            'image_cache_size': len(image_cache.cache),
            'thumbnail_cache_size': len(thumbnail_cache.cache),
            'image_cache_max': image_cache.max_size,
            'thumbnail_cache_max': thumbnail_cache.max_size
        }
        
        # Get connection pool info
        pool_stats = get_connection_pool_info()
        
        # Get database size info
        cursor.execute("""
            SELECT 
                pg_size_pretty(pg_database_size(current_database())) as db_size,
                pg_size_pretty(pg_total_relation_size('images')) as images_table_size
        """)
        db_size_info = cursor.fetchone()
        
        # Get system info
        system_info = {
            'cpu_percent': psutil.cpu_percent(interval=0.1),
            'memory_percent': psutil.virtual_memory().percent,
            'disk_percent': psutil.disk_usage('/').percent
        }
        
        conn.close()
        
        total_time = (time.time() - start_time) * 1000
        
        status_data = {
            'overall_status': 'healthy',
            'response_time': round(total_time, 2),
            'database': {
                'status': 'connected',
                'response_time': round(db_response_time, 2),
                'size': db_size_info[0] if db_size_info else 'unknown',
                'images_size': db_size_info[1] if db_size_info else 'unknown'
            },
            'cache': cache_stats,
            'connection_pool': pool_stats,
            'system': system_info,
            'app_version': APP_VERSION
        }
        
        return render_template('system_status.html', status=status_data)
        
    except Exception as e:
        # If anything fails, show error page
        error_data = {
            'overall_status': 'unhealthy',
            'error': str(e),
            'app_version': APP_VERSION
        }
        return render_template('system_status.html', status=error_data, error=True)

@admin_bp.route('/db-stats')
def db_statistics():
    """Inventory statistics and fun facts"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Get fun database statistics
        stats = {}
        
        # Total items
        cursor.execute("SELECT COUNT(*) FROM items")
        stats['total_items'] = cursor.fetchone()[0]
        
        # Total images
        cursor.execute("SELECT COUNT(*) FROM images")
        stats['total_images'] = cursor.fetchone()[0]
        
        # Total categories/tags
        cursor.execute("SELECT COUNT(*) FROM categories")
        stats['total_tags'] = cursor.fetchone()[0]
        
        # Current highest label number in use
        cursor.execute("SELECT MAX(label_number) FROM items WHERE label_number IS NOT NULL")
        max_label = cursor.fetchone()[0]
        stats['highest_label_in_use'] = max_label or 0
        
        # Count unlabeled items
        cursor.execute("SELECT COUNT(*) FROM items WHERE label_number IS NULL")
        stats['unlabeled_count'] = cursor.fetchone()[0]
        
        # Calculate what the next label number should be
        stats['next_label_number'] = (max_label or 0) + 1
        
        # Update the sequence to match reality (so auto-assignment works correctly)
        if max_label:
            cursor.execute("SELECT setval('label_number_seq', %s)", (max_label,))
        
        # Check sequence current value for debugging
        cursor.execute("SELECT last_value FROM label_number_seq")
        current_seq = cursor.fetchone()[0]
        stats['sequence_value'] = current_seq
        
        # Most recent item
        cursor.execute("SELECT item_name, created_date FROM items ORDER BY created_date DESC LIMIT 1")
        recent_item = cursor.fetchone()
        stats['recent_item'] = recent_item
        
        # Oldest item
        cursor.execute("SELECT item_name, created_date FROM items ORDER BY created_date ASC LIMIT 1")
        oldest_item = cursor.fetchone()
        stats['oldest_item'] = oldest_item
        
        # Items with most images
        cursor.execute("""
            SELECT i.item_name, COUNT(img.id) as image_count 
            FROM items i 
            LEFT JOIN images img ON i.guid = img.item_guid 
            GROUP BY i.guid, i.item_name 
            ORDER BY image_count DESC 
            LIMIT 1
        """)
        most_images = cursor.fetchone()
        stats['most_images'] = most_images
        
        # Most popular tag
        cursor.execute("""
            SELECT category_name, COUNT(*) as usage_count 
            FROM categories 
            GROUP BY category_name 
            ORDER BY usage_count DESC 
            LIMIT 1
        """)
        popular_tag = cursor.fetchone()
        stats['popular_tag'] = popular_tag
        
        # Database version
        cursor.execute("SELECT version();")
        stats['db_version'] = cursor.fetchone()[0]
        
        # HIERARCHY & NESTING STATS - with error handling
        try:
            # Top-level items (no parent)
            cursor.execute("SELECT COUNT(*) FROM items WHERE parent_guid IS NULL")
            stats['top_level_items'] = cursor.fetchone()[0]
            
            # Container items (have children)
            cursor.execute("""
                SELECT COUNT(DISTINCT parent_guid) 
                FROM items 
                WHERE parent_guid IS NOT NULL
            """)
            stats['container_items'] = cursor.fetchone()[0]
            
            # Leaf items (no children)
            cursor.execute("""
                SELECT COUNT(*) FROM items i
                WHERE NOT EXISTS (
                    SELECT 1 FROM items child WHERE child.parent_guid = i.guid
                )
            """)
            stats['leaf_items'] = cursor.fetchone()[0]
            
            # Simplified nesting depth calculation
            stats['max_nesting_depth'] = 0
            stats['longest_chain_path'] = "No nested items"
            stats['longest_chain_depth'] = 0
            
            # Try to calculate max depth, but don't break if it fails
            try:
                cursor.execute("""
                    WITH RECURSIVE item_depth AS (
                        SELECT guid, item_name, 0 as depth
                        FROM items 
                        WHERE parent_guid IS NULL
                        
                        UNION ALL
                        
                        SELECT i.guid, i.item_name, id.depth + 1
                        FROM items i
                        JOIN item_depth id ON i.parent_guid = id.guid
                        WHERE id.depth < 10
                    )
                    SELECT MAX(depth) FROM item_depth
                """)
                max_depth_result = cursor.fetchone()
                if max_depth_result and max_depth_result[0] is not None:
                    stats['max_nesting_depth'] = max_depth_result[0]
            except Exception:
                pass  # Keep default value
            
            # Most populous container (item with most direct children)
            cursor.execute("""
                SELECT parent.item_name, COUNT(child.guid) as child_count
                FROM items parent
                JOIN items child ON parent.guid = child.parent_guid
                GROUP BY parent.guid, parent.item_name
                ORDER BY child_count DESC
                LIMIT 1
            """)
            biggest_container = cursor.fetchone()
            stats['biggest_container'] = biggest_container
            
            # Average items per container
            cursor.execute("""
                SELECT AVG(child_count) as avg_children
                FROM (
                    SELECT COUNT(child.guid) as child_count
                    FROM items parent
                    JOIN items child ON parent.guid = child.parent_guid
                    GROUP BY parent.guid
                ) container_stats
            """)
            avg_children_result = cursor.fetchone()
            stats['avg_items_per_container'] = round(avg_children_result[0], 1) if avg_children_result[0] is not None else 0
            
        except Exception as e:
            # Fallback values if hierarchy queries fail
            print(f"Hierarchy stats error: {e}")
            stats['top_level_items'] = stats['total_items']
            stats['container_items'] = 0
            stats['leaf_items'] = stats['total_items']
            stats['max_nesting_depth'] = 0
            stats['longest_chain_path'] = "Stats unavailable"
            stats['longest_chain_depth'] = 0
            stats['biggest_container'] = None
            stats['avg_items_per_container'] = 0
        
        # Add embedding statistics
        try:
            cursor.execute("SELECT COUNT(*) FROM items WHERE embedding_vector IS NOT NULL")
            with_embeddings = cursor.fetchone()[0]
            cursor.execute("SELECT COUNT(*) FROM items WHERE embedding_vector IS NULL")  
            missing_embeddings = cursor.fetchone()[0]
            
            stats['embedding_stats'] = {
                'with_embeddings': with_embeddings,
                'missing_embeddings': missing_embeddings,
                'total_items': stats['total_items'],
                'percentage_indexed': round((with_embeddings / stats['total_items'] * 100) if stats['total_items'] > 0 else 0, 1)
            }
        except Exception as e:
            print(f"Embedding stats error: {e}")
            stats['embedding_stats'] = {
                'with_embeddings': 0,
                'missing_embeddings': stats['total_items'],
                'total_items': stats['total_items'], 
                'percentage_indexed': 0
            }
        
        conn.close()
        
        return render_template('db_stats.html', stats=stats)
        
    except Exception as e:
        return render_template('error.html',
            title='Database Error',
            heading='❌ Database Error',
            message=str(e),
            details=f'Error details: {repr(e)}')

@admin_bp.route('/api/cache-stats')
def cache_statistics():
    """Get cache performance statistics"""
    try:
        stats = {
            'image_cache': {
                'size': len(image_cache.cache),
                'max_size': image_cache.max_size,
                'max_age': image_cache.max_age,
                'hit_ratio': getattr(image_cache, 'hits', 0) / max(getattr(image_cache, 'requests', 1), 1),
                'hits': getattr(image_cache, 'hits', 0),
                'misses': getattr(image_cache, 'misses', 0)
            },
            'thumbnail_cache': {
                'size': len(thumbnail_cache.cache),
                'max_size': thumbnail_cache.max_size,
                'max_age': thumbnail_cache.max_age,
                'hit_ratio': getattr(thumbnail_cache, 'hits', 0) / max(getattr(thumbnail_cache, 'requests', 1), 1),
                'hits': getattr(thumbnail_cache, 'hits', 0),
                'misses': getattr(thumbnail_cache, 'misses', 0)
            }
        }
        
        return jsonify(stats)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@admin_bp.route('/api/clear-cache', methods=['POST'])
def clear_cache():
    """Clear image caches"""
    try:
        image_cache.clear()
        thumbnail_cache.clear()
        
        return jsonify({
            "success": True,
            "message": "All caches cleared successfully"
        })
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@admin_bp.route('/api/system-metrics')
def system_metrics():
    """Get current system metrics for monitoring"""
    try:
        # Get system metrics
        memory = psutil.virtual_memory()
        disk = psutil.disk_usage('/')
        cpu_percent = psutil.cpu_percent()
        
        # Get database connection count
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute('''
            SELECT count(*) 
            FROM pg_stat_activity 
            WHERE state = 'active'
        ''')
        active_connections = cursor.fetchone()[0]
        conn.close()
        
        metrics = {
            'timestamp': datetime.utcnow().isoformat(),
            'cpu_percent': cpu_percent,
            'memory_percent': memory.percent,
            'memory_available_gb': memory.available / (1024**3),
            'disk_percent': (disk.used / disk.total) * 100,
            'disk_free_gb': disk.free / (1024**3),
            'active_db_connections': active_connections,
            'cache_sizes': {
                'image_cache': len(image_cache.cache),
                'thumbnail_cache': len(thumbnail_cache.cache)
            },
            'embedding_model_available': is_embedding_model_available()
        }
        
        return jsonify(metrics)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@admin_bp.route('/api/reindex-embeddings', methods=['POST'])
def api_reindex_embeddings():
    """Reindex all embeddings for semantic search (called from DB stats page)"""
    try:
        from services.embedding_service import generate_embedding
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Clear all existing embeddings first
        print("[DEBUG] Clearing all existing embeddings...")
        cursor.execute('UPDATE items SET embedding_vector = NULL')
        conn.commit()
        print("[DEBUG] All embeddings cleared")
        
        # Get all items that need embeddings  
        cursor.execute('SELECT guid, item_name, description FROM items')
        items_to_update = cursor.fetchall()
        print(f"[DEBUG] Found {len(items_to_update)} items to process")
        
        updated_count = 0
        for guid, name, description in items_to_update:
            try:
                # Get all categories for this item
                cursor.execute('SELECT category_name FROM categories WHERE item_guid = %s', (guid,))
                categories = cursor.fetchall()
                category_text = " ".join([cat[0] for cat in categories])
                
                # Combine name, description, and categories
                combined_text = f"{name or ''} {description or ''} {category_text}".strip()
                print(f"[DEBUG] Processing item {guid[:8]}...")
                print(f"[DEBUG]   Name: '{name}'")
                print(f"[DEBUG]   Description: '{description}'")
                print(f"[DEBUG]   Categories: '{category_text}'")
                print(f"[DEBUG]   Combined: '{combined_text}'")
                
                if combined_text:
                    # Generate embedding
                    print(f"[DEBUG]   Generating embedding for: '{combined_text[:50]}...'")
                    embedding = generate_embedding(combined_text)
                    print(f"[DEBUG]   Embedding generated: {embedding is not None}")
                    
                    if embedding is not None:
                        # Convert to JSON format
                        if hasattr(embedding, 'tolist'):
                            embedding_list = embedding.tolist()
                        else:
                            embedding_list = list(embedding)
                        
                        import json
                        embedding_json = json.dumps(embedding_list)
                        
                        # Update the item
                        print(f"[DEBUG]   Updating database for {guid[:8]}...")
                        cursor.execute(
                            'UPDATE items SET embedding_vector = %s, updated_date = CURRENT_TIMESTAMP WHERE guid = %s',
                            (embedding_json, guid)
                        )
                        updated_count += 1
                        print(f"[DEBUG]   ✅ Updated! ({updated_count} total)")
                        
            except Exception as e:
                print(f"[DEBUG] ❌ Error processing {name}: {e}")
                continue
        
        conn.commit()
        conn.close()
        
        print(f"[DEBUG] 🎉 Reindex complete: {updated_count}/{len(items_to_update)} items updated")
        
        return jsonify({
            'success': True,
            'total_processed': len(items_to_update),
            'updated_count': updated_count
        })
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)})

@admin_bp.route('/cleanup-orphaned-images', methods=['POST'])
def cleanup_orphaned_images():
    """Clean up orphaned image files from filesystem"""
    try:
        from config import IMAGE_STORAGE_METHOD, IMAGE_DIR
        import os
        
        if IMAGE_STORAGE_METHOD != 'filesystem':
            return jsonify({
                'success': False,
                'error': 'Cleanup only available for filesystem storage'
            }), 400
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Get all image file paths from database
        cursor.execute('SELECT image_path, thumbnail_path, preview_path FROM images')
        db_files = cursor.fetchall()
        conn.close()
        
        # Create set of all files that should exist
        expected_files = set()
        for image_path, thumbnail_path, preview_path in db_files:
            if image_path:
                expected_files.add(image_path)
            if thumbnail_path:
                expected_files.add(thumbnail_path)
            if preview_path:
                expected_files.add(preview_path)
        
        # Get all files in the images directory
        if not os.path.exists(IMAGE_DIR):
            return jsonify({
                'success': True,
                'message': 'No images directory found',
                'cleaned_files': 0
            })
        
        actual_files = set()
        for filename in os.listdir(IMAGE_DIR):
            if os.path.isfile(os.path.join(IMAGE_DIR, filename)):
                actual_files.add(filename)
        
        # Find orphaned files
        orphaned_files = actual_files - expected_files
        
        # Delete orphaned files
        cleaned_count = 0
        total_size_freed = 0
        
        for filename in orphaned_files:
            try:
                file_path = os.path.join(IMAGE_DIR, filename)
                file_size = os.path.getsize(file_path)
                os.remove(file_path)
                cleaned_count += 1
                total_size_freed += file_size
            except Exception as e:
                print(f"Failed to delete orphaned file {filename}: {e}")
        
        # Format size for display
        if total_size_freed > 1024 * 1024:
            size_str = f"{total_size_freed / (1024 * 1024):.1f}MB"
        elif total_size_freed > 1024:
            size_str = f"{total_size_freed / 1024:.1f}KB"
        else:
            size_str = f"{total_size_freed}B"
        
        return jsonify({
            'success': True,
            'message': f'Cleaned up {cleaned_count} orphaned files ({size_str} freed)',
            'cleaned_files': cleaned_count,
            'size_freed': size_str
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@admin_bp.route('/model-cache-status', methods=['GET'])
def model_cache_status():
    """Check the status of the embedding model cache"""
    try:
        from services.embedding_service import get_cache_info, is_embedding_model_available
        
        cache_info = get_cache_info()
        model_available = is_embedding_model_available()
        
        return jsonify({
            'success': True,
            'cache_info': cache_info,
            'model_available': model_available
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

