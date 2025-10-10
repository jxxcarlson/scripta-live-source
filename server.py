#!/usr/bin/env python3
"""
Custom HTTP server that serves index-sqlite.html as the default index file.
Usage: python server.py [port]
Default port: 8012
"""

import http.server
import socketserver
import sys
from functools import partial

class CustomHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    """HTTP handler that uses index-sqlite.html as the default index."""

    def __init__(self, *args, **kwargs):
        # Serve from current directory (expects to be run from assets/)
        super().__init__(*args, **kwargs)

    def translate_path(self, path):
        """Translate a /-separated PATH to the local filename syntax."""
        # If requesting root or a directory, try index-sqlite.html first
        import os
        translated_path = super().translate_path(path)

        # If the path is a directory, check for index-sqlite.html
        if os.path.isdir(translated_path):
            index_sqlite = os.path.join(translated_path, "index-sqlite.html")
            if os.path.exists(index_sqlite):
                return index_sqlite

        return translated_path

def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8012

    with socketserver.TCPServer(("", port), CustomHTTPRequestHandler) as httpd:
        print(f"Serving HTTP on 0.0.0.0 port {port} (http://0.0.0.0:{port}/)")
        print(f"Default index file: index-sqlite.html")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nServer stopped.")
            sys.exit(0)

if __name__ == "__main__":
    main()
