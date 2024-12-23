#!/bin/bash

# This script sets up the V2Ray GUI project and installs all necessary components

# Constants
REPO_URL="https://github.com/mrbtmn/v2ray-gui.git"
INSTALL_DIR="/opt/v2ray_gui"
PYTHON_BIN="python3"
PIP_BIN="pip3"
SERVICE_FILE="/etc/systemd/system/v2ray_gui.service"

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi

# Install prerequisites
install_prerequisites() {
    echo "Installing prerequisites..."
    apt update -y
    apt install -y git $PYTHON_BIN $PIP_BIN nginx
    $PIP_BIN install flask
}

# Clone the repository
clone_repo() {
    if [ ! -d "$INSTALL_DIR" ]; then
        echo "Cloning repository..."
        git clone "$REPO_URL" "$INSTALL_DIR"
    else
        echo "Repository already cloned."
    fi
}

# Create the systemd service
create_service() {
    echo "Creating systemd service..."
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=V2Ray GUI Backend
After=network.target

[Service]
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $INSTALL_DIR/app.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable v2ray_gui
    systemctl start v2ray_gui
    echo "Service created and started."
}

# Configure Nginx (optional, for reverse proxy)
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
    echo "Nginx configured. Access the GUI via http://<server-ip>."
}

# Main script execution
install_prerequisites
clone_repo
create_service
configure_nginx

# Finish
echo "Installation complete. Access the GUI at http://<your-server-ip>."
