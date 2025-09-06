#!/bin/bash
# increment-major.sh
# Increments the MAJOR version number (e.g., 1.3.0 -> 2.0.0)
"$(dirname "$0")/version-helper.sh" major
