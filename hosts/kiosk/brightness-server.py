#!/usr/bin/env python3
"""
Minimal HTTP server for brightness control using brightnessctl
"""

import subprocess
import http.server
import socketserver
import json


class BrightnessHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == "/brightness":
            try:
                content_length = int(self.headers.get("Content-Length", 0))
                post_data = self.rfile.read(content_length).decode("utf-8").strip()
                brightness = int(post_data)

                if not (0 <= brightness <= 100):
                    raise ValueError("Brightness must be 0-100")

                result = subprocess.run(
                    ["brightnessctl", "set", f"{brightness}%"],
                    capture_output=True,
                    text=True,
                )

                if result.returncode == 0:
                    response = {"success": True, "brightness": brightness}
                    self.send_response(200)
                else:
                    response = {"error": "Failed to set brightness"}
                    self.send_response(500)

            except ValueError:
                response = {"error": "Invalid brightness value"}
                self.send_response(400)
            except Exception:
                response = {"error": "Server error"}
                self.send_response(500)

            self.send_header("Content-type", "application/json")
            self.end_headers()
            _ = self.wfile.write(json.dumps(response).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def do_GET(self):
        self.send_response(404)
        self.end_headers()


def main():
    PORT = 8080
    with socketserver.TCPServer(("", PORT), BrightnessHandler) as httpd:
        print(f"Brightness server running on port {PORT}")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down...")


if __name__ == "__main__":
    main()
