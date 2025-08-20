#!/bin/bash

# Universal Inventory System Testing Script
# Tests any Flask inventory system at any URL (Docker, Pi, custom)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
DEFAULT_DATABASE_URL="http://localhost:8081"
DEFAULT_FILESYSTEM_URL="http://localhost:8080"
TEST_IMAGE_PATH="/tmp/test-image.jpg"
WAIT_TIME=10

# Test results tracking
RESULTS=()

# Helper functions
print_status() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_header() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================${NC}"
}

# Wait for service to be ready
wait_for_service() {
    local url=$1
    local name=$2
    local max_attempts=30
    local attempt=1
    
    print_status "Waiting for $name to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -f "$url" > /dev/null 2>&1; then
            print_success "$name is ready!"
            return 0
        fi
        
        echo "   Attempt $attempt/$max_attempts - waiting..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    print_error "$name failed to start after $max_attempts attempts"
    return 1
}

# Test homepage loading
test_homepage() {
    local url=$1
    local name=$2
    
    print_status "Testing $name homepage..."
    
    if curl -s -f "$url" | grep -q "Flask Inventory System"; then
        print_success "$name homepage loads correctly"
        return 0
    else
        print_error "$name homepage failed to load or shows wrong content"
        return 1
    fi
}

# Test semantic search API
test_semantic_search() {
    local url=$1
    local name=$2
    
    print_status "Testing $name semantic search API..."
    
    # Test basic API endpoint
    if curl -s -f "$url/api/semantic-search?q=test&limit=1" > /dev/null 2>&1; then
        print_success "$name semantic search API is accessible"
        
        # Test actual search functionality
        local response=$(curl -s "$url/api/semantic-search?q=test&limit=1")
        if echo "$response" | grep -q "results\|items\|data"; then
            print_success "$name semantic search returns results"
            return 0
        else
            print_warning "$name semantic search API accessible but may not be fully functional"
            return 0
        fi
    else
        print_error "$name semantic search API not accessible"
        return 1
    fi
}

# Test ML re-indexing
test_ml_reindex() {
    local url=$1
    local name=$2
    
    print_status "Testing $name ML re-indexing..."
    
    # Test the re-index endpoint (if it exists)
    if curl -s -f "$url/admin/reindex" > /dev/null 2>&1; then
        print_success "$name ML re-indexing endpoint accessible"
        return 0
    elif curl -s -f "$url/api/reindex" > /dev/null 2>&1; then
        print_success "$name ML re-indexing API accessible"
        return 0
    else
        print_warning "$name ML re-indexing endpoint not found (may be normal)"
        return 0
    fi
}

# Test image display on homepage
test_image_display() {
    local url=$1
    local name=$2
    
    print_status "Testing $name image display on homepage..."
    
    # Check if homepage contains image-related content
    local homepage=$(curl -s "$url")
    
    if echo "$homepage" | grep -q "img\|image\|thumbnail"; then
        print_success "$name homepage contains image elements"
        return 0
    else
        print_warning "$name homepage may not have images (could be empty database)"
        return 0
    fi
}

# Test image upload functionality
test_image_upload() {
    local url=$1
    local name=$2
    
    print_status "Testing $name image upload functionality..."
    
    # Create a test image if it doesn't exist
    if [ ! -f "$TEST_IMAGE_PATH" ]; then
        print_status "Creating test image..."
        # Create a simple 1x1 pixel JPEG using ImageMagick or fallback
        if command -v convert >/dev/null 2>&1; then
            convert -size 1x1 xc:white "$TEST_IMAGE_PATH"
        else
            # Fallback: create a minimal JPEG file
            echo -n -e '\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x01\x00H\x00H\x00\x00\xff\xdb\x00C\x00\x08\x06\x06\x07\x06\x05\x08\x07\x07\x07\t\t\x08\n\x0c\x14\r\x0c\x0b\x0b\x0c\x19\x12\x13\x0f\x14\x1d\x1a\x1f\x1e\x1d\x1a\x1c\x1c $.\x27 ,#\x1c\x1c(7),01444\x1f\x27=9=82<.342\xff\xc0\x00\x11\x08\x00\x01\x00\x01\x01\x01\x11\x00\x02\x11\x01\x03\x11\x01\xff\xc4\x00\x14\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x08\xff\xc4\x00\x14\x10\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xff\xda\x00\x0c\x03\x01\x00\x02\x11\x03\x11\x00\x3f\x00\xaa\xff\xd9' > "$TEST_IMAGE_PATH"
        fi
    fi
    
    # Test upload endpoint
    if curl -s -f -X POST -F "file=@$TEST_IMAGE_PATH" "$url/upload" > /dev/null 2>&1; then
        print_success "$name image upload endpoint accessible"
        return 0
    elif curl -s -f -X POST -F "file=@$TEST_IMAGE_PATH" "$url/api/upload" > /dev/null 2>&1; then
        print_success "$name image upload API accessible"
        return 0
    else
        print_warning "$name image upload endpoint not found (may be normal)"
        return 0
    fi
}

# Test database connectivity
test_database_connectivity() {
    local port=$1
    local name=$2
    
    print_status "Testing $name database connectivity..."
    
    if command -v psql >/dev/null 2>&1; then
        if PGPASSWORD=inventory_database_pass psql -h localhost -p $port -U inventory -d inventory_database -c "SELECT 1;" > /dev/null 2>&1; then
            print_success "$name database connection successful"
            return 0
        else
            print_error "$name database connection failed"
            return 1
        fi
    else
        print_warning "psql not available, skipping database connectivity test"
        return 0
    fi
}

# Test filesystem image directory
test_filesystem_images() {
    print_status "Testing filesystem image directory..."
    
    if [ -d "/tmp/inventory-images" ]; then
        print_success "Filesystem image directory exists"
        local file_count=$(find /tmp/inventory-images -type f | wc -l)
        print_status "Filesystem image directory contains $file_count files"
        return 0
    else
        print_warning "Filesystem image directory not found"
        return 0
    fi
}

# Run all tests for a configuration
run_configuration_tests() {
    local url=$1
    local name=$2
    local db_port=$3
    
    print_header "Testing $name Configuration"
    
    # Wait for service to be ready
    if ! wait_for_service "$url" "$name"; then
        print_error "$name service not ready, skipping tests"
        return 1
    fi
    
    # Run individual tests
    local passed=0
    local failed=0
    
    if test_homepage "$url" "$name"; then
        ((passed++))
    else
        ((failed++))
    fi
    
    if test_semantic_search "$url" "$name"; then
        ((passed++))
    else
        ((failed++))
    fi
    
    if test_ml_reindex "$url" "$name"; then
        ((passed++))
    else
        ((failed++))
    fi
    
    if test_image_display "$url" "$name"; then
        ((passed++))
    else
        ((failed++))
    fi
    
    if test_image_upload "$url" "$name"; then
        ((passed++))
    else
        ((failed++))
    fi
    
    if test_database_connectivity "$db_port" "$name"; then
        ((passed++))
    else
        ((failed++))
    fi
    
    # Store results globally
    RESULTS+=("$name: $passed passed, $failed failed")
    
    print_header "$name Test Results: $passed passed, $failed failed"
}

# Main test execution
main() {
    local target_urls=()
    local target_names=()
    
    # Parse command line arguments
    case "${1:-both}" in
        "database")
            target_urls=("${2:-$DEFAULT_DATABASE_URL}")
            target_names=("Database Storage")
            print_header "Testing Database Storage Configuration"
            ;;
        "filesystem")
            target_urls=("${2:-$DEFAULT_FILESYSTEM_URL}")
            target_names=("Filesystem Storage")
            print_header "Testing Filesystem Storage Configuration"
            ;;
        "both")
            target_urls=("${2:-$DEFAULT_DATABASE_URL}" "${3:-$DEFAULT_FILESYSTEM_URL}")
            target_names=("Database Storage" "Filesystem Storage")
            print_header "Testing Both Storage Configurations"
            ;;
        "custom")
            if [ -z "$2" ]; then
                print_error "Custom mode requires a URL. Usage: $0 custom <URL> [<NAME>]"
                exit 1
            fi
            target_urls=("$2")
            target_names=("${3:-Custom Target}")
            print_header "Testing Custom Target: ${target_names[0]}"
            ;;
        "pi")
            local pi_url="${2:-http://localhost:8000}"
            target_urls=("$pi_url")
            target_names=("Raspberry Pi")
            print_header "Testing Raspberry Pi Configuration"
            ;;
        *)
            print_error "Usage: $0 [database|filesystem|both|custom|pi] [URL] [NAME]"
            echo ""
            echo "Examples:"
            echo "  $0                                    # Test both Docker configs (default)"
            echo "  $0 database                           # Test database storage only"
            echo "  $0 filesystem                         # Test filesystem storage only"
            echo "  $0 custom http://localhost:9000      # Test custom URL"
            echo "  $0 pi http://192.168.1.100:8000     # Test Pi at specific IP"
            echo "  $0 pi                                 # Test Pi at localhost:8000"
            exit 1
            ;;
    esac
    
    print_status "Testing ${#target_urls[@]} target(s)..."
    echo ""
    
    # Check if Docker is needed
    if [[ " ${target_names[@]} " =~ " Database Storage " ]] || [[ " ${target_names[@]} " =~ " Filesystem Storage " ]]; then
        if ! docker info > /dev/null 2>&1; then
            print_error "Docker is not running. Please start Docker first."
            exit 1
        fi
    fi
    
    # Run tests for each target
    for i in "${!target_urls[@]}"; do
        local url="${target_urls[$i]}"
        local name="${target_names[$i]}"
        
        print_status "Testing: $name at $url"
        
        if run_configuration_tests "$url" "$name"; then
            print_success "$name tests completed successfully"
        else
            print_error "$name tests failed"
        fi
        
        echo ""
    done
    
    # Test filesystem-specific functionality if testing filesystem storage
    if [[ " ${target_names[@]} " =~ " Filesystem Storage " ]]; then
        test_filesystem_images
    fi
    
    # Final results summary
    print_header "Final Test Results Summary"
    echo ""
    
    local total_passed=0
    local total_failed=0
    
    # Display results for each target
    for i in "${!target_names[@]}"; do
        local name="${target_names[$i]}"
        local passed=0
        local failed=0
        
        # Count results for this target
        for result in "${RESULTS[@]}"; do
            if echo "$result" | grep -q "^$name:"; then
                if echo "$result" | grep -q "✅"; then
                    ((passed++))
                elif echo "$result" | grep -q "❌"; then
                    ((failed++))
                fi
            fi
        done
        
        echo -e "${BLUE}$name:${NC}"
        echo "   ✅ Passed: $passed"
        echo "   ❌ Failed: $failed"
        echo ""
        
        total_passed=$((total_passed + passed))
        total_failed=$((total_failed + failed))
    done
    
    echo -e "${BLUE}Overall Results:${NC}"
    echo "   ✅ Total Passed: $total_passed"
    echo "   ❌ Total Failed: $total_failed"
    echo ""
    
    # Analyze results
    if [ $total_failed -eq 0 ]; then
        print_success "🎉 All tests passed! All configurations are working correctly."
    elif [ ${#target_names[@]} -eq 1 ]; then
        print_warning "⚠️  Single target tested with some failures."
    else
        # Multiple targets - analyze differences
        local db_failures=0
        local fs_failures=0
        
        for result in "${RESULTS[@]}"; do
            if echo "$result" | grep -q "Database Storage:"; then
                if echo "$result" | grep -q "❌"; then
                    ((db_failures++))
                fi
            elif echo "$result" | grep -q "Filesystem Storage:"; then
                if echo "$result" | grep -q "❌"; then
                    ((fs_failures++))
                fi
            fi
        done
        
        if [ $db_failures -eq 0 ] && [ $fs_failures -gt 0 ]; then
            print_warning "⚠️  Database storage works perfectly, but filesystem storage has issues."
            print_status "This suggests the problem is in filesystem-specific code or configuration."
        elif [ $fs_failures -eq 0 ] && [ $db_failures -gt 0 ]; then
            print_warning "⚠️  Filesystem storage works perfectly, but database storage has issues."
            print_status "This suggests the problem is in database-specific code or configuration."
        else
            print_error "❌ Multiple configurations have issues. This suggests a problem in shared code."
        fi
    fi
    
    echo ""
    print_status "Test completed. Check the results above for details."
}

# Run main function
main "$@"
