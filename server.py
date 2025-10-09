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

    def list_directory(self, path):
        """Override to serve index-sqlite.html if it exists in the directory."""
        import os
        index_path = os.path.join(path, "index-sqlite.html")
        if os.path.exists(index_path):
            # Serve index-sqlite.html instead of directory listing
            self.path = "/index-sqlite.html"
            return self.do_GET()
        return super().list_directory(path)

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
