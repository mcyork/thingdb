#!/bin/bash
# increment-minor.sh
# Increments the MINOR version number (e.g., 1.3.0 -> 1.4.0)
"$(dirname "$0")/version-helper.sh" minor
