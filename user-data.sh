#!/bin/bash
set -xe

# Update + install required packages
dnf update -y
dnf install -y nginx python3 stress-ng

# -----------------------
# CPU burn script
# -----------------------
cat > /opt/burn.sh <<'EOF'
#!/bin/bash
nohup stress-ng --cpu 2 --timeout 20s >/tmp/stress.log 2>&1 &
echo "OK - CPU burn started"
EOF

chmod +x /opt/burn.sh

# -----------------------
# Python burner server
# -----------------------
cat > /opt/burner.py <<'EOF'
#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
import subprocess

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/burn":
            subprocess.Popen(["/opt/burn.sh"])
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"Burn started")
        else:
            self.send_response(404)
            self.end_headers()

server = HTTPServer(("0.0.0.0", 9000), Handler)
server.serve_forever()
EOF

chmod +x /opt/burner.py

# Systemd service for the python burner
cat > /etc/systemd/system/burner.service <<'EOF'
[Unit]
Description=CPU burn HTTP endpoint

[Service]
ExecStart=/usr/bin/python3 /opt/burner.py
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable burner
systemctl start burner

# -----------------------
# Nginx proxy setup
# -----------------------
cat > /etc/nginx/conf.d/default.conf <<'EOF'
server {
    listen 80;
    server_name _;

    location / {
        root /usr/share/nginx/html;
        index index.html;
    }

    location /burn {
        proxy_pass http://127.0.0.1:9000/burn;
    }
}
EOF

# Simple homepage
echo "<h1>Hello from Auto Scaling EC2</h1>" > /usr/share/nginx/html/index.html

systemctl enable nginx
systemctl restart nginx
