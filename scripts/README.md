# Universal Inventory System Testing Script

The `test-inventory.sh` script is a flexible testing tool that can test any Flask inventory system at any URL.

## 🎯 **What It Tests**

The script runs 5 core tests based on your deployment script:

1. **Homepage loads** - Does the homepage load and show "Flask Inventory System"?
2. **Re-indexing works** - Can we access re-indexing endpoints?
3. **ML re-indexing works** - Is the semantic search API accessible?
4. **Images display on homepage** - Does the homepage contain image elements?
5. **Image upload works** - Can we access image upload endpoints?

## 🚀 **Usage**

### **Test Both Docker Configurations (Default)**
```bash
./scripts/test-inventory.sh
# or
./scripts/test-inventory.sh both
```

### **Test Database Storage Only**
```bash
./scripts/test-inventory.sh database
# or test at custom URL
./scripts/test-inventory.sh database http://localhost:9000
```

### **Test Filesystem Storage Only**
```bash
./scripts/test-inventory.sh filesystem
# or test at custom URL
./scripts/test-inventory.sh filesystem http://localhost:9000
```

### **Test Custom Target**
```bash
./scripts/test-inventory.sh custom http://localhost:9000 "My Custom App"
```

### **Test Raspberry Pi**
```bash
# Test Pi at default localhost:8000
./scripts/test-inventory.sh pi

# Test Pi at specific IP
./scripts/test-inventory.sh pi http://192.168.1.100:8000
```

## 🔍 **How It Helps Debugging**

The script helps identify whether issues are:

- **Configuration-specific** (one Docker config works, other doesn't)
- **Shared code issues** (both configs have the same problems)
- **Environment-specific** (Docker works, Pi doesn't)

## 📊 **Example Output**

```
============================================
Testing Both Storage Configurations
============================================
ℹ️  Testing 2 target(s)...

ℹ️  Testing: Database Storage at http://localhost:8081
============================================
Testing Database Storage Configuration
============================================
✅ Database Storage is ready!

ℹ️  Test 1: Does Database Storage homepage load?
✅ Database Storage homepage loads correctly

ℹ️  Test 2: Can we re-index? (ML re-indexing)
⚠️  Database Storage re-index endpoint not found (may be normal)

...

============================================
Final Test Results Summary
============================================

Database Storage:
   ✅ Passed: 4
   ❌ Failed: 1

Filesystem Storage:
   ✅ Passed: 3
   ❌ Failed: 2

Overall Results:
   ✅ Total Passed: 7
   ❌ Total Failed: 3

⚠️  Database storage works perfectly, but filesystem storage has issues.
ℹ️  This suggests the problem is in filesystem-specific code or configuration.
```

## 🛠️ **Requirements**

- `curl` for HTTP testing
- `docker` (only if testing Docker configurations)
- `psql` (optional, for database connectivity testing)

## 💡 **Tips**

- **Start with both Docker configs** to compare them side-by-side
- **Use custom mode** to test any URL (local development, staging, etc.)
- **Test Pi separately** to isolate environment-specific issues
- **Check the analysis** at the end to understand what the results mean
