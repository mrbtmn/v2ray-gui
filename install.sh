#!/bin/bash

# Enhanced V2Ray GUI Setup Script
# This script installs, configures, and deploys a V2Ray GUI management system.

# Variables
INSTALL_DIR="/opt/v2ray_gui"
REPO_URL="https://github.com/mrbtmn/v2ray-gui.git"
SERVICE_FILE="/etc/systemd/system/v2ray_gui.service"
USERS_FILE="$INSTALL_DIR/users.json"
PYTHON_BIN=$(command -v python3)
PIP_BIN=$(command -v pip3)

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root."
    exit 1
fi

# Function to install prerequisites
install_prerequisites() {
    echo "Installing prerequisites..."
    apt update -y && apt install -y git $PYTHON_BIN $PIP_BIN nginx
    $PIP_BIN install flask || { echo "Failed to install Flask!"; exit 1; }
    echo "Prerequisites installed."
}

# Function to set up the application directory
setup_application() {
    echo "Setting up application directory..."
    mkdir -p "$INSTALL_DIR"
    if [ -d "$INSTALL_DIR" ]; then
        echo "Application directory created."
    else
        echo "Failed to create application directory!"
        exit 1
    fi
}

# Function to generate the backend Flask app
generate_backend() {
    echo "Generating backend Flask application..."
    cat > "$INSTALL_DIR/app.py" <<EOF
from flask import Flask, jsonify, request
import uuid
import json

app = Flask(__name__)
USERS_FILE = "users.json"

# Helper functions
def load_users():
    try:
        with open(USERS_FILE, "r") as file:
            return json.load(file)
    except FileNotFoundError:
        return []

def save_users(users):
    with open(USERS_FILE, "w") as file:
        json.dump(users, file, indent=4)

@app.route("/api/users", methods=["GET"])
def list_users():
    return jsonify(load_users())

@app.route("/api/add-user", methods=["POST"])
def add_user():
    data = request.json
    name = data.get("name")
    domain = data.get("domain")
    if not name or not domain:
        return jsonify({"error": "Name and domain are required"}), 400

    user_uuid = str(uuid.uuid4())
    unique_path = f"/{uuid.uuid4().hex[:8]}"
    vless_link = (
        f"vless://{user_uuid}@{domain}:2053?"
        f"encryption=none&security=tls&sni={domain}&type=ws&host={domain}"
        f"&path={unique_path}%3Fed%3D2560#{name}"
    )

    users = load_users()
    user = {"name": name, "uuid": user_uuid, "path": unique_path, "vless_link": vless_link}
    users.append(user)
    save_users(users)

    return jsonify(user)

@app.route("/api/delete-user/<identifier>", methods=["DELETE"])
def delete_user(identifier):
    users = load_users()
    users = [user for user in users if user["uuid"] != identifier and user["name"] != identifier]
    save_users(users)
    return "", 204

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
EOF

    echo "Backend Flask application generated."
}

# Function to generate the frontend
generate_frontend() {
    echo "Generating frontend..."
    mkdir -p "$INSTALL_DIR/static"
    cat > "$INSTALL_DIR/static/index.html" <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>V2Ray GUI</title>
    <script>
        async function loadUsers() {
            const response = await fetch('/api/users');
            const users = await response.json();
            const userList = document.getElementById('user-list');
            userList.innerHTML = '';
            users.forEach(user => {
                const listItem = document.createElement('li');
                listItem.innerHTML = \`
                    <strong>\${user.name}</strong><br>
                    UUID: \${user.uuid}<br>
                    Path: \${user.path}<br>
                    VLESS Link: <a href="\${user.vless_link}" target="_blank">\${user.vless_link}</a><br>
                    <button onclick="deleteUser('\${user.uuid}')">Delete</button>
                \`;
                userList.appendChild(listItem);
            });
        }

        async function deleteUser(uuid) {
            await fetch(\`/api/delete-user/\${uuid}\`, { method: 'DELETE' });
            loadUsers();
        }

        async function addUser() {
            const name = prompt('Enter user name:');
            const domain = prompt('Enter domain:');
            if (name && domain) {
                await fetch('/api/add-user', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ name, domain })
                });
                loadUsers();
            }
        }

        window.onload = loadUsers;
    </script>
</head>
<body>
    <h1>V2Ray GUI</h1>
    <button onclick="addUser()">Add User</button>
    <ul id="user-list"></ul>
</body>
</html>
EOF
    echo "Frontend generated."
}

# Function to set up the systemd service
setup_service() {
    echo "Setting up systemd service..."
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=V2Ray GUI Backend
After=network.target

[Service]
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$PYTHON_BIN $INSTALL_DIR/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable v2ray_gui
    systemctl start v2ray_gui
    echo "Systemd service set up and started."
}

# Function to configure Nginx
configure_nginx() {
    echo "Configuring Nginx..."
    cat > /etc/nginx/sites-available/v2ray_gui <<EOF
server {
    listen 80;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/v2ray_gui /etc/nginx/sites-enabled/v2ray_gui
    systemctl restart nginx
    echo "Nginx configured."
}

# Execution flow
install_prerequisites
setup_application
generate_backend
generate_frontend
setup_service
configure_nginx

# Completion message
echo "Installation complete. Access the GUI at http://<your-server-ip>/"
