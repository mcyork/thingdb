"""
Search routes for Flask Inventory Management System
Handles traditional text search and semantic search functionality
"""
import json
from flask import Blueprint, request, jsonify, render_template
from database import get_db_connection
from utils.helpers import clean_search_query, extract_tags_from_query, paginate_results
from services.embedding_service import generate_embedding, cosine_similarity, parse_embedding_from_db, is_embedding_model_available
from config import SEMANTIC_SEARCH

search_bp = Blueprint('search', __name__)

@search_bp.route('/search', methods=['GET', 'POST'])
def search():
    """Main search endpoint supporting both traditional and semantic search"""
    if request.method == 'POST':
        query = request.form.get('query', '').strip()
    else:
        query = request.args.get('q', '').strip()
    
    if not query:
        return render_template('search_results.html', 
                             results=[], 
                             query='', 
                             search_type='none',
                             total_results=0)
    
    # Extract tags and clean query
    tags, clean_query = extract_tags_from_query(query)
    
    # Determine search strategy - prioritize semantic search
    use_semantic = (
        is_embedding_model_available() and 
        len(clean_query) >= SEMANTIC_SEARCH.get('min_query_length', 2)
        # Always prefer semantic search when available
    )
    
    if use_semantic:
        results = _semantic_search(clean_query)
        search_type = 'semantic'
    else:
        results = _traditional_search(query, tags, clean_query)
        search_type = 'traditional'
    
    # Paginate results
    page = int(request.args.get('page', 1))
    paginated_results, total_results, current_page = paginate_results(results, page)
    
    return render_template('search_results.html',
                         results=paginated_results,
                         query=query,
                         search_type=search_type,
                         total_results=total_results,
                         current_page=current_page,
                         has_next=len(results) > current_page * 50,
                         has_prev=current_page > 1)

@search_bp.route('/api/search', methods=['GET'])
def api_search():
    """API endpoint for search (returns JSON)"""
    query = request.args.get('q', '').strip()
    if not query:
        return jsonify({"results": [], "total": 0, "search_type": "none"})
    
    # Extract tags and clean query
    tags, clean_query = extract_tags_from_query(query)
    
    # Determine search strategy
    use_semantic = (
        is_embedding_model_available() and 
        len(clean_query) >= SEMANTIC_SEARCH.get('min_query_length', 3) and
        not tags
    )
    
    if use_semantic:
        results = _semantic_search(clean_query)
        search_type = 'semantic'
    else:
        results = _traditional_search(query, tags, clean_query)
        search_type = 'traditional'
    
    # Format results for API
    formatted_results = []
    for result in results[:50]:  # Limit API results
        formatted_results.append({
            'guid': result[0],
            'item_name': result[1],
            'description': result[2] or '',
            'created_date': result[3].isoformat() if result[3] else None,
            'image_count': result[4],
            'similarity_score': result[5] if len(result) > 5 else None
        })
    
    return jsonify({
        "results": formatted_results,
        "total": len(results),
        "search_type": search_type,
        "query": query
    })

@search_bp.route('/search-suggestions', methods=['GET'])
def search_suggestions():
    """Get search suggestions based on partial query"""
    query = request.args.get('q', '').strip()
    if len(query) < 2:
        return jsonify({"suggestions": []})
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        suggestions = []
        
        # Get item name suggestions
        cursor.execute('''
            SELECT DISTINCT item_name 
            FROM items 
            WHERE LOWER(item_name) LIKE LOWER(%s) 
            ORDER BY item_name 
            LIMIT 5
        ''', (f'%{query}%',))
        
        for row in cursor.fetchall():
            suggestions.append({
                'text': row[0],
                'type': 'item_name'
            })
        
        # Get category suggestions if query starts with #
        if query.startswith('#'):
            tag_query = query[1:]  # Remove # prefix
            cursor.execute('''
                SELECT DISTINCT category_name, COUNT(*) as usage_count
                FROM categories 
                WHERE LOWER(category_name) LIKE LOWER(%s) 
                GROUP BY category_name
                ORDER BY usage_count DESC, category_name 
                LIMIT 5
            ''', (f'%{tag_query}%',))
            
            for row in cursor.fetchall():
                suggestions.append({
                    'text': f'#{row[0]}',
                    'type': 'tag',
                    'usage_count': row[1]
                })
        
        conn.close()
        return jsonify({"suggestions": suggestions})
    
    except Exception as e:
        return jsonify({"suggestions": [], "error": str(e)})

@search_bp.route('/popular-tags', methods=['GET'])
def popular_tags():
    """Get most popular tags/categories"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT category_name, COUNT(*) as usage_count
            FROM categories 
            GROUP BY category_name
            ORDER BY usage_count DESC, category_name
            LIMIT 20
        ''')
        
        tags = []
        for row in cursor.fetchall():
            tags.append({
                'name': row[0],
                'count': row[1]
            })
        
        conn.close()
        return jsonify({"tags": tags})
    
    except Exception as e:
        return jsonify({"tags": [], "error": str(e)})

def _semantic_search(query):
    """Perform semantic search using embeddings"""
    if not query or not is_embedding_model_available():
        return []
    
    try:
        # Generate embedding for search query
        query_embedding = generate_embedding(query)
        if not query_embedding:
            print("[DEBUG] Failed to generate query embedding")
            return []
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Get all items with embeddings
        cursor.execute('''
            SELECT items.guid, items.item_name, items.description, items.created_date,
                   (SELECT COUNT(*) FROM images WHERE item_guid = items.guid) as image_count,
                   items.embedding_vector
            FROM items 
            WHERE items.embedding_vector IS NOT NULL
        ''')
        
        results = []
        threshold = SEMANTIC_SEARCH.get('similarity_threshold', 0.15)
        
        for row in cursor.fetchall():
            item_embedding = parse_embedding_from_db(row[5])
            if not item_embedding:
                continue
            
            # Calculate similarity
            similarity = cosine_similarity(query_embedding, item_embedding)
            
            if similarity >= threshold:
                results.append((
                    row[0],  # guid
                    row[1],  # item_name
                    row[2],  # description
                    row[3],  # created_date
                    row[4],  # image_count
                    similarity  # similarity_score
                ))
        
        # Sort by similarity score (descending)
        results.sort(key=lambda x: x[5], reverse=True)
        
        conn.close()
        print(f"[DEBUG] Semantic search for '{query}' found {len(results)} results")
        return results
    
    except Exception as e:
        print(f"[ERROR] Semantic search failed: {e}")
        return []

def _traditional_search(original_query, tags, clean_query):
    """Perform traditional SQL-based text search with tag support"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Build search conditions
        conditions = []
        params = []
        
        # Text search in item names and descriptions
        if clean_query:
            conditions.append('''
                (LOWER(items.item_name) LIKE LOWER(%s) 
                 OR LOWER(items.description) LIKE LOWER(%s))
            ''')
            params.extend([f'%{clean_query}%', f'%{clean_query}%'])
        
        # Tag-based search
        if tags:
            tag_conditions = []
            for tag in tags:
                tag_conditions.append('LOWER(categories.category_name) = LOWER(%s)')
                params.append(tag)
            
            if tag_conditions:
                conditions.append(f"({' OR '.join(tag_conditions)})")
        
        # If no conditions, return empty results
        if not conditions:
            conn.close()
            return []
        
        # Build and execute query
        where_clause = ' AND '.join(conditions)
        
        if tags:
            # Join with categories for tag search
            query = f'''
                SELECT DISTINCT items.guid, items.item_name, items.description, items.created_date,
                       (SELECT COUNT(*) FROM images WHERE item_guid = items.guid) as image_count
                FROM items 
                LEFT JOIN categories ON items.guid = categories.item_guid
                WHERE {where_clause}
                ORDER BY items.created_date DESC
            '''
        else:
            # Simple search without category join
            query = f'''
                SELECT items.guid, items.item_name, items.description, items.created_date,
                       (SELECT COUNT(*) FROM images WHERE item_guid = items.guid) as image_count
                FROM items 
                WHERE {where_clause}
                ORDER BY items.created_date DESC
            '''
        
        cursor.execute(query, params)
        results = cursor.fetchall()
        
        conn.close()
        print(f"[DEBUG] Traditional search for '{original_query}' found {len(results)} results")
        return results
    
    except Exception as e:
        print(f"[ERROR] Traditional search failed: {e}")
        return []

@search_bp.route('/reindex-embeddings', methods=['POST'])
def reindex_embeddings():
    """Regenerate embeddings for all items (admin function)"""
    if not is_embedding_model_available():
        return jsonify({"success": False, "error": "Embedding model not available"}), 503
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Get all items
        cursor.execute('SELECT guid, item_name, description FROM items')
        items = cursor.fetchall()
        
        updated_count = 0
        for guid, item_name, description in items:
            try:
                # Combine name and description for embedding
                combined_text = f"{item_name} {description or ''}"
                embedding_vector = generate_embedding(combined_text)
                
                if embedding_vector:
                    embedding_json = json.dumps(embedding_vector)
                    cursor.execute('''
                        UPDATE items 
                        SET embedding_vector = %s 
                        WHERE guid = %s
                    ''', (embedding_json, guid))
                    updated_count += 1
            except Exception as e:
                print(f"Failed to update embedding for {guid}: {e}")
        
        conn.commit()
        conn.close()
        
        return jsonify({
            "success": True, 
            "message": f"Reindexed {updated_count} out of {len(items)} items"
        })
    
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

@search_bp.route('/api/semantic-search')
def semantic_search_api():
    """Semantic search using embeddings for comprehensive results (matches original app.py)"""
    query = request.args.get('q', '').strip()
    limit = min(int(request.args.get('limit', 20)), 50)  # Max 50 results
    exclude_guid = request.args.get('exclude', '')
    
    if not query or len(query) < 2:
        return jsonify([])
    
    try:
        # Generate embedding for the search query
        print(f"[DEBUG] Generating embedding for query: '{query}'")
        query_embedding = generate_embedding(query)
        if not query_embedding:
            # Fallback to traditional search if embeddings fail
            print("[DEBUG] Embeddings not available, falling back to traditional search")
            return search_items_api()
        print(f"[DEBUG] Query embedding generated successfully, length: {len(query_embedding)}")
        
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Get all items with embeddings for similarity calculation
        cursor.execute('''
            SELECT i.guid, i.item_name, i.description, i.embedding_vector,
                   (SELECT COUNT(*) FROM items WHERE parent_guid = i.guid) as contained_count,
                   (SELECT id FROM images WHERE item_guid = i.guid AND is_primary = TRUE LIMIT 1) as primary_image_id,
                   (SELECT string_agg(c.category_name, ', ') FROM categories c WHERE c.item_guid = i.guid) as all_tags,
                   i.label_number
            FROM items i
            WHERE i.embedding_vector IS NOT NULL
            AND i.guid != %s
        ''', (exclude_guid,))
        
        items_with_embeddings = cursor.fetchall()
        print(f"[DEBUG] Found {len(items_with_embeddings)} items with embeddings")
        
        results = []
        for row in items_with_embeddings:
            guid, name, description, embedding_json, contained_count, primary_image_id, all_tags, label_number = row
            
            if not embedding_json:
                continue
                
            try:
                # Parse the stored embedding
                item_embedding = parse_embedding_from_db(embedding_json)
                if not item_embedding:
                    continue
                
                # Calculate similarity
                similarity = cosine_similarity(query_embedding, item_embedding)
                print(f"[DEBUG] Item '{name[:30]}...' similarity: {similarity:.3f}")
                
                # Only include items with reasonable similarity (threshold: 0.15)
                if similarity >= 0.15:
                    results.append({
                        'guid': guid,
                        'name': name,
                        'description': description or '',
                        'similarity': similarity,
                        'match_type': 'semantic',
                        'contained_count': contained_count,
                        'has_image': primary_image_id is not None,
                        'image_id': primary_image_id,
                        'matched_tags': all_tags,
                        'label_number': label_number
                    })
                    
            except (json.JSONDecodeError, TypeError) as e:
                print(f"[ERROR] Failed to parse embedding for item {guid}: {e}")
                continue
        
        # Sort by similarity (highest first)
        results.sort(key=lambda x: x['similarity'], reverse=True)
        
        # Limit results
        results = results[:limit]
        
        conn.close()
        print(f"[DEBUG] Returning {len(results)} semantic search results")
        return jsonify(results)
    
    except Exception as e:
        print(f"[ERROR] Semantic search failed: {e}")
        return search_items_api()  # Fallback to traditional search

@search_bp.route('/search-items', methods=['GET'])
def search_items_api():
    """Search items by name and tags for autocomplete (matches original app.py)"""
    query = request.args.get('q', '').strip().lower()
    exclude_guid = request.args.get('exclude', '')  # Exclude current item from results
    
    if not query or len(query) < 2:
        return jsonify([])
    
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Search items by name AND tags - fixed ORDER BY for DISTINCT
        cursor.execute('''
            SELECT DISTINCT i.guid, i.item_name, 
                   (SELECT COUNT(*) FROM items WHERE parent_guid = i.guid) as contained_count,
                   (SELECT id FROM images WHERE item_guid = i.guid AND is_primary = TRUE LIMIT 1) as primary_image_id,
                   (SELECT string_agg(c.category_name, ', ') FROM categories c WHERE c.item_guid = i.guid) as all_tags,
                   CASE WHEN LOWER(i.item_name) LIKE %s THEN 1 ELSE 2 END as name_priority,
                   LENGTH(i.item_name) as name_length,
                   i.label_number
            FROM items i
            WHERE (
                LOWER(i.item_name) LIKE %s
                OR i.guid IN (
                    SELECT c.item_guid 
                    FROM categories c 
                    WHERE LOWER(c.category_name) LIKE %s
                )
            )
            AND i.guid != %s
            ORDER BY name_priority, name_length, i.item_name
            LIMIT 10
        ''', (f'{query}%', f'%{query}%', f'%{query}%', exclude_guid))
        
        results = []
        for row in cursor.fetchall():
            guid, name, contained_count, primary_image_id, all_tags, name_priority, name_length, label_number = row
            results.append({
                'guid': guid,
                'name': name,
                'contained_count': contained_count,
                'has_image': primary_image_id is not None,
                'image_id': primary_image_id,
                'matched_tags': all_tags,
                'match_priority': name_priority,
                'label_number': label_number,
                'match_type': 'traditional'
            })
        
        conn.close()
        return jsonify(results)
    
    except Exception as e:
        print(f"[ERROR] Traditional search failed: {e}")
        return jsonify([])

@search_bp.route('/api/reindex-all-embeddings', methods=['POST'])
def reindex_all_embeddings_api():
    """Re-index all items to generate missing embeddings (matches original app.py)"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Get all items that need embeddings
        cursor.execute('''
            SELECT guid, item_name, description
            FROM items
            WHERE embedding_vector IS NULL
        ''')
        
        items_to_update = cursor.fetchall() 
        updated_count = 0
        print(f"[DEBUG] Found {len(items_to_update)} items needing embeddings")
        
        for guid, name, description in items_to_update:
            try:
                # Combine name and description for comprehensive embedding
                combined_text = f"{name or ''} {description or ''}".strip()
                
                if combined_text:
                    # Generate embedding
                    embedding_vector = generate_embedding(combined_text)
                    embedding_json = json.dumps(embedding_vector) if embedding_vector else None
                    
                    # Update the item with the embedding
                    cursor.execute('''
                        UPDATE items 
                        SET embedding_vector = %s, updated_date = CURRENT_TIMESTAMP 
                        WHERE guid = %s
                    ''', (embedding_json, guid))
                    
                    updated_count += 1
                    print(f"[DEBUG] Generated embedding for: {name or guid[:8]}")
                else:
                    print(f"[WARNING] Skipping empty item: {guid[:8]}")
                    
            except Exception as e:
                print(f"[ERROR] Failed to generate embedding for {guid}: {e}")
                continue
        
        conn.commit()
        conn.close()
        
        return jsonify({
            'success': True,
            'total_processed': len(items_to_update),
            'updated_count': updated_count,
            'message': f'Updated {updated_count} out of {len(items_to_update)} items'
        })
        
    except Exception as e:
        print(f"[ERROR] Bulk reindex failed: {e}")
        return jsonify({'success': False, 'error': str(e)})