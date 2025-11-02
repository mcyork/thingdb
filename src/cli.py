#!/usr/bin/env python3
"""
ThingDB Command Line Interface
Provides easy commands to initialize, run, and manage the inventory system.
"""
import os
import sys
import argparse
from pathlib import Path


def main():
    """Main CLI entry point"""
    parser = argparse.ArgumentParser(
        description='ThingDB - Smart Inventory Management System',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  thingdb serve              Start the web server
  thingdb serve --port 8080  Start on custom port
  thingdb init               Initialize database
  thingdb version            Show version information
        """
    )
    
    parser.add_argument(
        'command',
        choices=['serve', 'init', 'version'],
        help='Command to execute'
    )
    
    parser.add_argument(
        '--host',
        default='0.0.0.0',
        help='Host to bind to (default: 0.0.0.0)'
    )
    
    parser.add_argument(
        '--port',
        type=int,
        default=5000,
        help='Port to bind to (default: 5000)'
    )
    
    parser.add_argument(
        '--debug',
        action='store_true',
        help='Enable debug mode'
    )
    
    args = parser.parse_args()
    
    if args.command == 'version':
        show_version()
    elif args.command == 'init':
        init_database()
    elif args.command == 'serve':
        serve(host=args.host, port=args.port, debug=args.debug)


def show_version():
    """Display version information"""
    try:
        from thingdb.config import APP_VERSION
        print(f"ThingDB version {APP_VERSION}")
    except ImportError:
        print("ThingDB (version unknown)")
    sys.exit(0)


def init_database():
    """Initialize the database schema"""
    print("🔧 Initializing database...")
    try:
        from thingdb.database import init_database as db_init
        db_init()
        print("✅ Database initialized successfully!")
        print("\nNext steps:")
        print("  1. Run: thingdb serve")
        print("  2. Open: http://localhost:5000")
    except Exception as e:
        print(f"❌ Failed to initialize database: {e}")
        print("\nMake sure PostgreSQL is running and credentials are set in .env file")
        sys.exit(1)


def serve(host='0.0.0.0', port=5000, debug=False):
    """Start the Flask web server"""
    print(f"🚀 Starting ThingDB on http://{host}:{port}")
    
    if debug:
        print("⚠️  Debug mode enabled")
    
    try:
        from thingdb.main import app
        app.run(host=host, port=port, debug=debug)
    except ImportError as e:
        print(f"❌ Failed to import application: {e}")
        print("\nMake sure all dependencies are installed:")
        print("  pip install -e .")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Failed to start server: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()

