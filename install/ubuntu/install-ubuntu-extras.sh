#!/usr/bin/env bash
# Ubuntu-specific installations from official sources (not apt defaults which are outdated):
# AWS CLI v2, GitHub CLI, Docker Engine, gitleaks, Terraform, kubectl, Helm, Azure CLI
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

# --- GitHub CLI (official GitHub repository) ---
log_info "Checking GitHub CLI..."
if ! command -v gh &>/dev/null; then
    log_info "Installing GitHub CLI from official repository..."
    
    # Install wget if not present
    (type -p wget >/dev/null || (sudo apt update && sudo apt install wget -y))
    
    # Add GitHub GPG key
    sudo mkdir -p -m 755 /etc/apt/keyrings
    out=$(mktemp)
    wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg
    cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
    sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    rm -f $out
    
    # Add GitHub repository
    sudo mkdir -p -m 755 /etc/apt/sources.list.d
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    
    # Install GitHub CLI
    sudo apt update
    sudo apt install gh -y
    
    log_info "GitHub CLI installed: $(gh --version)"
else
    log_info "GitHub CLI already installed: $(gh --version)"
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

# --- gitleaks (secret scanner for pre-commit hook) ---
log_info "Checking gitleaks..."
# Remove apt-installed version (outdated — Ubuntu universe has 8.16.0, latest is 8.30.0+)
if dpkg -l gitleaks 2>/dev/null | grep -q '^ii'; then
    log_warn "Removing outdated apt-installed gitleaks in favour of latest GitHub release..."
    sudo apt-get remove -y gitleaks
fi
if [[ ! -x /usr/local/bin/gitleaks ]]; then
    log_info "Installing gitleaks from GitHub releases..."
    CURL_AUTH=()
    [[ -n "${GITHUB_TOKEN:-}" ]] && CURL_AUTH=(-H "Authorization: token $GITHUB_TOKEN")
    GITLEAKS_VERSION=$(curl -fsSL "${CURL_AUTH[@]}" \
        https://api.github.com/repos/gitleaks/gitleaks/releases/latest \
        | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
    ARCH=$(dpkg --print-architecture)
    [[ "$ARCH" == "amd64" ]] && GITLEAKS_ARCH="x64" || GITLEAKS_ARCH="arm64"
    curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${GITLEAKS_ARCH}.tar.gz" \
        -o /tmp/gitleaks.tar.gz
    tar -xzf /tmp/gitleaks.tar.gz -C /tmp/ gitleaks
    sudo mv /tmp/gitleaks /usr/local/bin/gitleaks
    rm /tmp/gitleaks.tar.gz
    log_info "gitleaks installed: $(gitleaks version)"
else
    log_info "gitleaks already installed: $(gitleaks version)"
fi

# --- Terraform (official HashiCorp binary from GitHub releases) ---
log_info "Checking Terraform..."
if ! command -v terraform &>/dev/null; then
    log_info "Installing Terraform from GitHub releases..."
    CURL_AUTH=()
    [[ -n "${GITHUB_TOKEN:-}" ]] && CURL_AUTH=(-H "Authorization: token $GITHUB_TOKEN")
    TF_VERSION=$(curl -fsSL "${CURL_AUTH[@]}" \
        https://api.github.com/repos/hashicorp/terraform/releases/latest \
        | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
    ARCH=$(dpkg --print-architecture)
    curl -fsSL "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_${ARCH}.zip" \
        -o /tmp/terraform.zip
    unzip -qo /tmp/terraform.zip -d /tmp/ terraform
    sudo mv /tmp/terraform /usr/local/bin/terraform
    rm /tmp/terraform.zip
    log_info "Terraform installed: $(terraform --version | head -1)"
else
    log_info "Terraform already installed: $(terraform --version | head -1)"
fi

# --- kubectl (official Kubernetes binary) ---
log_info "Checking kubectl..."
if ! command -v kubectl &>/dev/null; then
    log_info "Installing kubectl..."
    ARCH=$(dpkg --print-architecture)
    KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
    curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" \
        -o /tmp/kubectl
    sudo install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl
    rm /tmp/kubectl
    log_info "kubectl installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
else
    log_info "kubectl already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
fi

# --- Helm (official install script) ---
log_info "Checking Helm..."
if ! command -v helm &>/dev/null; then
    log_info "Installing Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    log_info "Helm installed: $(helm version --short)"
else
    log_info "Helm already installed: $(helm version --short)"
fi

# --- Azure CLI (official Microsoft repository) ---
log_info "Checking Azure CLI..."
if ! command -v az &>/dev/null; then
    log_info "Installing Azure CLI from Microsoft repository..."
    sudo mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg
    sudo chmod go+r /etc/apt/keyrings/microsoft.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $(. /etc/os-release && echo "$VERSION_CODENAME") main" | \
        sudo tee /etc/apt/sources.list.d/azure-cli.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y azure-cli
    log_info "Azure CLI installed: $(az version --output tsv 2>/dev/null | head -1)"
else
    log_info "Azure CLI already installed: $(az version --output tsv 2>/dev/null | head -1)"
fi

# --- Disable unnecessary services ---
log_info "Disabling unnecessary services..."
for svc in cups cups-browsed; do
    if systemctl is-enabled "$svc" &>/dev/null 2>&1; then
        sudo systemctl disable --now "$svc"
        log_info "Disabled ${svc}"
    fi
done
