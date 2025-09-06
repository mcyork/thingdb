#!/bin/bash
# increment-patch.sh
# Increments the PATCH version number (e.g., 1.3.0 -> 1.3.1)
"$(dirname "$0")/version-helper.sh" patch
