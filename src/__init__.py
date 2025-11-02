"""
ThingDB - Smart Inventory Management System
"""

__version__ = "1.4.17"
__author__ = "Your Name"
__license__ = "MIT"

# Make key components available at package level
try:
    from .main import app, create_app
    from .config import APP_VERSION
except ImportError:
    # Allow imports to fail gracefully during installation
    pass

