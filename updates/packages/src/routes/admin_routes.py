"""
Admin routes for Flask Inventory Management System
Handles health checks, system monitoring, and administration functions
"""
import psutil
from datetime import datetime
from flask import Blueprint, jsonify, render_template
from database import get_db_connection, get_connection_pool_info
from models import image_cache, thumbnail_cache
from services.embedding_service import is_embedding_model_available
from services.qr_pdf_service import qr_pdf_service
from services.package_verification_service import PackageVerificationService
from config import APP_VERSION

admin_bp = Blueprint('admin', __name__)

@admin_bp.route('/admin')
def admin_panel():
    """Main admin panel page with consolidated admin functions"""
    return render_template('admin.html')


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


@admin_bp.route('/api/validate-database', methods=['POST'])
def api_validate_database():
    """Validate database integrity and find issues"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        issues_found = 0
        issues_fixed = 0
        checks_performed = 0
        details = []
        
        # Check 1: Orphaned images
        checks_performed += 1
        cursor.execute("""
            SELECT COUNT(*) FROM images i 
            LEFT JOIN items it ON i.item_guid = it.guid 
            WHERE it.guid IS NULL
        """)
        orphaned_images = cursor.fetchone()[0]
        if orphaned_images > 0:
            issues_found += 1
            details.append(f"Found {orphaned_images} orphaned images")
        
        # Check 2: Orphaned categories
        checks_performed += 1
        cursor.execute("""
            SELECT COUNT(*) FROM categories c 
            LEFT JOIN items it ON c.item_guid = it.guid 
            WHERE it.guid IS NULL
        """)
        orphaned_categories = cursor.fetchone()[0]
        if orphaned_categories > 0:
            issues_found += 1
            details.append(f"Found {orphaned_categories} orphaned categories")
        
        # Check 3: Items without primary images but have images
        checks_performed += 1
        cursor.execute("""
            SELECT COUNT(*) FROM items i
            WHERE EXISTS (SELECT 1 FROM images img WHERE img.item_guid = i.guid)
            AND NOT EXISTS (SELECT 1 FROM images img WHERE img.item_guid = i.guid AND img.is_primary = true)
        """)
        no_primary = cursor.fetchone()[0]
        if no_primary > 0:
            issues_found += 1
            details.append(f"Found {no_primary} items with images but no primary image")
        
        # Check 4: Items with invalid parent references
        checks_performed += 1
        cursor.execute("""
            SELECT COUNT(*) FROM items i
            WHERE i.parent_guid IS NOT NULL 
            AND NOT EXISTS (SELECT 1 FROM items p WHERE p.guid = i.parent_guid)
        """)
        invalid_parents = cursor.fetchone()[0]
        if invalid_parents > 0:
            issues_found += 1
            details.append(f"Found {invalid_parents} items with invalid parent references")
        
        # Check 5: Duplicate label numbers
        checks_performed += 1
        cursor.execute("""
            SELECT label_number, COUNT(*) as count 
            FROM items 
            WHERE label_number IS NOT NULL 
            GROUP BY label_number 
            HAVING COUNT(*) > 1
        """)
        duplicate_labels = cursor.fetchall()
        if duplicate_labels:
            issues_found += 1
            details.append(f"Found {len(duplicate_labels)} duplicate label numbers")
        
        conn.close()
        
        return jsonify({
            'success': True,
            'checks_performed': checks_performed,
            'issues_found': issues_found,
            'issues_fixed': issues_fixed,
            'details': details
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@admin_bp.route('/api/optimize-database', methods=['POST'])
def api_optimize_database():
    """Optimize database performance"""
    try:
        import psycopg2.extensions
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Get database size before optimization
        cursor.execute("SELECT pg_size_pretty(pg_database_size(current_database()))")
        size_before = cursor.fetchone()[0]
        
        # Run VACUUM to reclaim space
        conn.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)
        cursor.execute("VACUUM")
        
        # Run ANALYZE to update statistics
        cursor.execute("ANALYZE")
        
        # Get database size after optimization
        cursor.execute("SELECT pg_size_pretty(pg_database_size(current_database()))")
        size_after = cursor.fetchone()[0]
        
        # Count tables analyzed
        cursor.execute("""
            SELECT COUNT(*) FROM information_schema.tables 
            WHERE table_schema = 'public'
        """)
        tables_analyzed = cursor.fetchone()[0]
        
        conn.close()
        
        return jsonify({
            'success': True,
            'space_reclaimed': f"Optimized from {size_before} to {size_after}",
            'tables_analyzed': tables_analyzed
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@admin_bp.route('/api/generate-qr-sheet', methods=['POST'])
def generate_qr_sheet():
    """Generate and download QR code PDF sheet"""
    try:
        from flask import send_file
        
        # Generate PDF
        pdf_buffer, guids = qr_pdf_service.generate_qr_sheet()
        filename = qr_pdf_service.get_pdf_filename()
        
        # Return PDF as download
        return send_file(
            pdf_buffer,
            as_attachment=True,
            download_name=filename,
            mimetype='application/pdf'
        )
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


# =============================================================================
# PACKAGE MANAGEMENT ROUTES
# =============================================================================

@admin_bp.route('/api/test-package-upload', methods=['GET'])
def api_test_package_upload():
    """Test route to verify package upload functionality is working"""
    try:
        from cryptography import x509
        cryptography_available = True
        message = 'Package upload API is working with cryptography support'
    except ImportError:
        cryptography_available = False
        message = 'Package upload API is working but cryptography is not available'
    
    return jsonify({
        'success': True,
        'message': message,
        'cryptography_available': cryptography_available
    })

@admin_bp.route('/api/simple-test', methods=['GET'])
def api_simple_test():
    """Simple test route that doesn't require any imports"""
    return jsonify({
        'success': True,
        'message': 'Simple test route is working',
        'timestamp': datetime.now().isoformat()
    })

@admin_bp.route('/api/upload-package', methods=['POST'])
def api_upload_package():
    """Upload and verify an update package"""
    try:
        from flask import request
        import os
        import tempfile
        from werkzeug.utils import secure_filename
        import logging
        
        logger = logging.getLogger(__name__)
        logger.info("Package upload request received")
        logger.info(f"Request files: {list(request.files.keys())}")
        logger.info(f"Request form: {list(request.form.keys())}")
        
        if 'package' not in request.files:
            logger.error("No package file in request")
            return jsonify({'success': False, 'error': 'No package file provided'}), 400
        
        file = request.files['package']
        logger.info(f"File received: {file.filename}, size: {file.content_length}")
        
        if file.filename == '':
            logger.error("Empty filename")
            return jsonify({'success': False, 'error': 'No file selected'}), 400
        
        if not file.filename.endswith('-bundle.tar.gz'):
            logger.error(f"Invalid file format: {file.filename}")
            return jsonify({
                'success': False, 
                'error': f'Invalid package format. Expected file ending with "-bundle.tar.gz", got: "{file.filename}"'
            }), 400
        
        # Save uploaded file to temporary location
        filename = secure_filename(file.filename)
        temp_dir = tempfile.mkdtemp(prefix="inventory_upload_")
        temp_path = os.path.join(temp_dir, filename)
        file.save(temp_path)
        
        # Verify the package
        verifier = PackageVerificationService(allow_unsigned=False)
        result = verifier.verify_complete_package(temp_path)
        
        if not result['valid']:
            # Clean up temp file
            os.unlink(temp_path)
            os.rmdir(temp_dir)
            return jsonify({
                'success': False, 
                'error': 'Package verification failed',
                'details': result['errors']
            }), 400
        
        # Package is valid, move it to a permanent location
        package_dir = os.path.join(os.path.dirname(__file__), '..', '..', 'packages')
        package_dir = os.path.abspath(package_dir)  # Convert to absolute path
        os.makedirs(package_dir, exist_ok=True)
        permanent_path = os.path.join(package_dir, filename)
        
        # Move the file
        os.rename(temp_path, permanent_path)
        os.rmdir(temp_dir)
        
        return jsonify({
            'success': True,
            'message': 'Package uploaded and verified successfully',
            'package_path': permanent_path,
            'manifest': result['manifest_data']
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': f'Upload failed: {str(e)}'
        }), 500


@admin_bp.route('/api/install-package', methods=['POST'])
def api_install_package():
    """Install an uploaded package (simplified version)"""
    try:
        from flask import request
        import os
        import shutil
        import subprocess
        import json
        import tarfile
        import time
        import logging
        from pathlib import Path
        
        logger = logging.getLogger(__name__)
        
        data = request.json
        package_path = data.get('package_path')
        
        if not package_path or not os.path.exists(package_path):
            return jsonify({'success': False, 'error': 'Package not found'}), 400
        
        # Simple install - just extract and restart
        logger.info(f"Starting package installation: {package_path}")
        
        # Create backup
        app_dir = os.path.dirname(__file__)
        backup_dir = os.path.join(app_dir, '..', '..', 'backup')
        os.makedirs(backup_dir, exist_ok=True)
        backup_path = os.path.join(backup_dir, f'backup-{int(time.time())}')
        
        logger.info(f"Creating backup at: {backup_path}")
        shutil.copytree(app_dir, backup_path)
        
        # Extract package
        logger.info("Extracting package...")
        with tarfile.open(package_path, 'r:gz') as tar:
            tar.extractall(path=os.path.dirname(app_dir))
        
        logger.info("Package installation completed successfully")
        
        return jsonify({
            'success': True,
            'message': 'Package installed successfully. Service restart required.',
            'backup_location': backup_path
        })
        
    except Exception as e:
        logger.error(f"Installation failed: {e}")
        return jsonify({
            'success': False,
            'error': f'Installation failed: {str(e)}'
        }), 500


@admin_bp.route('/api/restart-service', methods=['POST'])
def api_restart_service():
    """Restart the inventory service"""
    try:
        import subprocess
        import logging
        
        logger = logging.getLogger(__name__)
        logger.info("Restarting inventory service...")
        
        # Restart the service using full path to sudo (non-blocking)
        logger.info("Initiating service restart...")
        subprocess.Popen(['/usr/bin/sudo', 'systemctl', 'restart', 'inventory-app'], 
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        
        # Return immediately - the service will restart and this process will be killed
        logger.info("Service restart initiated")
        return jsonify({
            'success': True,
            'message': 'Service restart initiated successfully'
        })
            
    except subprocess.TimeoutExpired:
        logger.error("Service restart timed out")
        return jsonify({
            'success': False,
            'error': 'Service restart timed out'
        }), 500
    except Exception as e:
        logger.error(f"Service restart error: {e}")
        return jsonify({
            'success': False,
            'error': f'Service restart failed: {str(e)}'
        }), 500


@admin_bp.route('/api/rollback-package', methods=['POST'])
def api_rollback_package():
    """Rollback to the previous version"""
    try:
        import os
        import shutil
        import json
        
        upgrade_flag_path = os.path.join(os.path.dirname(__file__), '..', '..', '.upgrade-in-progress')
        
        if not os.path.exists(upgrade_flag_path):
            return jsonify({'success': False, 'error': 'No upgrade in progress'}), 400
        
        # Read upgrade flag
        with open(upgrade_flag_path, 'r') as f:
            upgrade_flag = json.load(f)
        
        backup_location = upgrade_flag.get('backup_location')
        if not backup_location or not os.path.exists(backup_location):
            return jsonify({'success': False, 'error': 'Backup not found'}), 400
        
        # Restore from backup
        current_src = os.path.join(os.path.dirname(__file__), '..')
        temp_src = os.path.join(os.path.dirname(current_src), 'src_rollback')
        
        shutil.rmtree(current_src)
        shutil.copytree(backup_location, temp_src)
        shutil.move(temp_src, current_src)
        
        # Remove upgrade flag
        os.unlink(upgrade_flag_path)
        
        return jsonify({
            'success': True,
            'message': 'Rollback completed successfully. Service restart required.'
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': f'Rollback failed: {str(e)}'
        }), 500


@admin_bp.route('/api/upgrade-status', methods=['GET'])
def api_upgrade_status():
    """Get current upgrade status"""
    try:
        import os
        import json
        
        upgrade_flag_path = os.path.join(os.path.dirname(__file__), '..', '..', '.upgrade-in-progress')
        
        if not os.path.exists(upgrade_flag_path):
            return jsonify({
                'upgrade_in_progress': False,
                'current_version': APP_VERSION
            })
        
        with open(upgrade_flag_path, 'r') as f:
            upgrade_flag = json.load(f)
        
        return jsonify({
            'upgrade_in_progress': True,
            'current_version': APP_VERSION,
            'upgrade_flag': upgrade_flag
        })
        
    except Exception as e:
        return jsonify({
            'success': False,
            'error': f'Failed to get upgrade status: {str(e)}'
        }), 500
