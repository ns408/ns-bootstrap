#!/usr/bin/env bash
# Ubuntu-specific installations: AWS CLI v2, Docker Engine
# These use official sources (not apt defaults which are outdated)
set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# --- AWS CLI v2 (official installer, not apt) ---
log_info "Checking AWS CLI v2..."
if ! command -v aws &>/dev/null || [[ "$(aws --version 2>&1)" != *"aws-cli/2"* ]]; then
    log_info "Installing AWS CLI v2..."
    ARCH=$(dpkg --print-architecture)
    if [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
        AWS_URL="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
    else
        AWS_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
    fi
    curl -fsSL "$AWS_URL" -o /tmp/awscliv2.zip
    unzip -qo /tmp/awscliv2.zip -d /tmp/
    sudo /tmp/aws/install --update
    rm -rf /tmp/aws /tmp/awscliv2.zip
    log_info "AWS CLI v2 installed: $(aws --version)"
else
    log_info "AWS CLI v2 already installed: $(aws --version)"
fi

# --- Docker Engine (official Docker repo) ---
log_info "Checking Docker Engine..."
if ! command -v docker &>/dev/null; then
    log_info "Installing Docker Engine from official repository..."

    # Remove conflicting packages
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
        sudo apt-get remove -y "$pkg" 2>/dev/null || true
    done

    # Install prerequisites
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl unzip

    # Add Docker GPG key
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add Docker repository
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker Engine + Compose plugin
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin

    # Allow non-root usage
    sudo usermod -aG docker "$USER"
    log_info "Docker Engine installed. Log out and back in for group changes."
    log_info "Docker version: $(docker --version)"
    log_info "Docker Compose version: $(docker compose version)"
else
    log_info "Docker already installed: $(docker --version)"
    if docker compose version &>/dev/null 2>&1; then
        log_info "Docker Compose: $(docker compose version 2>/dev/null || echo 'not available')"
    fi
fi
