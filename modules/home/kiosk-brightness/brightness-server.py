#!/usr/bin/env python3
"""
Minimal HTTP server for brightness control using brightnessctl
"""

import subprocess
import http.server
import socketserver
import json
import sys
import os
import hmac
from typing import override

AUTH_TOKEN = os.environ.get("BRIGHTNESS_SERVER_TOKEN", "")

if not AUTH_TOKEN:
    print("Error: BRIGHTNESS_SERVER_TOKEN environment variable is required")
    sys.exit(1)


class BrightnessHandler(http.server.BaseHTTPRequestHandler):
    def check_auth(self) -> bool:
        auth_header = self.headers.get("Authorization", "")
        expected = f"Bearer {AUTH_TOKEN}"
        if len(auth_header) != len(expected):
            return False
        return hmac.compare_digest(auth_header.encode(), expected.encode())

    def send_json_response(self, status_code: int, data: dict[str, object]) -> None:
        response_body = json.dumps(data).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-type", "application/json")
        self.send_header("Content-Length", str(len(response_body)))
        self.end_headers()
        _ = self.wfile.write(response_body)

    @override
    def log_message(self, format: str, *args: object) -> None:
        if any(keyword in str(format) for keyword in ["error", "Error", "ERROR"]) or (
            len(args) > 0 and isinstance(args[0], (int, str)) and int(args[0]) >= 400
        ):
            super().log_message(format, *args)

    def do_POST(self) -> None:
        if not self.check_auth():
            self.send_json_response(401, {"error": "Unauthorized"})
            return

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

                if result.returncode != 0:
                    self.send_json_response(500, {"error": "Failed to set brightness"})
                    return

                screen_result = subprocess.run(
                    ["kscreen-doctor", "--dpms", "on"],
                    capture_output=True,
                    text=True,
                )

                if screen_result.returncode == 0:
                    self.send_json_response(
                        200, {"success": True, "brightness": brightness}
                    )
                else:
                    self.send_json_response(
                        500, {"error": "Brightness set but failed to wake screen"}
                    )

            except ValueError:
                self.send_json_response(400, {"error": "Invalid brightness value"})
            except Exception:
                self.send_json_response(500, {"error": "Server error"})

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
                    self.send_json_response(200, {"success": True, "screen": post_data})
                else:
                    self.send_json_response(
                        500, {"error": f"Failed to set screen {post_data}"}
                    )

            except ValueError:
                self.send_json_response(
                    400, {"error": "Invalid screen state (must be 'on' or 'off')"}
                )
            except Exception:
                self.send_json_response(500, {"error": "Server error"})

        else:
            self.send_json_response(404, {"error": "Not found"})

    def do_GET(self) -> None:
        if not self.check_auth():
            self.send_json_response(401, {"error": "Unauthorized"})
            return
        self.send_json_response(404, {"error": "Not found"})


def main():
    PORT = 8080
    try:
        # Create server with socket reuse option to avoid "Address already in use" errors
        with socketserver.TCPServer(("", PORT), BrightnessHandler) as httpd:
            httpd.allow_reuse_address = True
            print(f"Brightness server running on port {PORT}")
            try:
                httpd.serve_forever()
            except KeyboardInterrupt:
                print("\nShutting down...")
                httpd.server_close()
    except OSError as e:
        if e.errno == 98:  # Address already in use
            print(
                f"Error: Port {PORT} is already in use. Is the server already running?"
            )
            sys.exit(1)
        else:
            raise


if __name__ == "__main__":
    main()


# Curl command examples:
# Set brightness to 50%:
# curl -X POST -d "50" -H "Authorization: Bearer EXAMPLE" http://localhost:8080/brightness
#
# Set brightness to 75%:
# curl -X POST -d "75" -H "Authorization: Bearer EXAMPLE" http://localhost:8080/brightness
#
# Set brightness to 25%:
# curl -X POST -d "25" -H "Authorization: Bearer EXAMPLE" http://localhost:8080/brightness
#
# Turn screen on:
# curl -X POST -d "on" -H "Authorization: Bearer EXAMPLE" http://localhost:8080/screen
#
# Turn screen off:
# curl -X POST -d "off" -H "Authorization: Bearer EXAMPLE" http://localhost:8080/screen
