#!/usr/bin/env python3
import argparse
import functools
import http.server
import os
import socketserver


class GodotWebHandler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".pck": "application/octet-stream",
        ".wasm": "application/wasm",
    }

    def end_headers(self) -> None:
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        self.send_header("X-Content-Type-Options", "nosniff")
        super().end_headers()


def main() -> None:
    parser = argparse.ArgumentParser(description="Serve the Godot Web export with browser-compatible headers.")
    parser.add_argument("--dir", default="build/web")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=8062, type=int)
    args = parser.parse_args()

    directory = os.path.abspath(args.dir)
    handler = functools.partial(GodotWebHandler, directory=directory)
    with socketserver.TCPServer((args.host, args.port), handler) as httpd:
        print(f"Serving {directory} at http://{args.host}:{args.port}/")
        httpd.serve_forever()


if __name__ == "__main__":
    main()
