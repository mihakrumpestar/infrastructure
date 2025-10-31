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

                # First, set the brightness
                result = subprocess.run(
                    ["brightnessctl", "set", f"{brightness}%"],
                    capture_output=True,
                    text=True,
                )

                if result.returncode != 0:
                    response = {"error": "Failed to set brightness"}
                    self.send_response(500)
                    self.send_header("Content-type", "application/json")
                    self.end_headers()
                    _ = self.wfile.write(json.dumps(response).encode())
                    return

                # Then, ensure the screen is on
                screen_result = subprocess.run(
                    ["kscreen-doctor", "--dpms", "on"],
                    capture_output=True,
                    text=True,
                )

                if screen_result.returncode == 0:
                    response = {"success": True, "brightness": brightness}
                    self.send_response(200)
                else:
                    response = {"error": "Brightness set but failed to wake screen"}
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
        elif self.path == "/screen":
            try:
                content_length = int(self.headers.get("Content-Length", 0))
                post_data = (
                    self.rfile.read(content_length).decode("utf-8").strip().lower()
                )

                if post_data not in ["on", "off"]:
                    raise ValueError("Screen state must be 'on' or 'off'")

                result = subprocess.run(
                    ["kscreen-doctor", "--dpms", post_data],
                    capture_output=True,
                    text=True,
                )

                if result.returncode == 0:
                    response = {"success": True, "screen": post_data}
                    self.send_response(200)
                else:
                    response = {"error": f"Failed to set screen {post_data}"}
                    self.send_response(500)

            except ValueError:
                response = {"error": "Invalid screen state (must be 'on' or 'off')"}
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


# Curl command examples:
# Set brightness to 50%:
# curl -X POST -d "50" http://localhost:8080/brightness
#
# Set brightness to 75%:
# curl -X POST -d "75" http://localhost:8080/brightness
#
# Set brightness to 25%:
# curl -X POST -d "25" http://localhost:8080/brightness
#
# Turn screen on:
# curl -X POST -d "on" http://localhost:8080/screen
#
# Turn screen off:
# curl -X POST -d "off" http://localhost:8080/screen
