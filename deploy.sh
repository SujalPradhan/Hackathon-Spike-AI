#!/bin/bash

# =============================================================================
# Spike AI Multi-Agent Analytics System - Deployment Script
# =============================================================================
#
# This script deploys the production-ready AI backend for the Spike AI Hackathon.
#
# Requirements (per PRD):
# - Must complete startup within 7 minutes
# - Must bind to port 8080 only
# - Must use .venv at repository root
# - Must use credentials.json at project root
#
# Usage:
#   bash deploy.sh
#
# =============================================================================

set -e  # Exit on any error

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$PROJECT_ROOT/.venv"
PYTHON_CMD="python3"
PIP_CMD="pip"
PORT=8080
LOG_FILE="$PROJECT_ROOT/deploy.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[DEPLOY]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE"
    exit 1
}

# Header
echo "============================================================================="
echo "  Spike AI Multi-Agent Analytics System - Deployment"
echo "============================================================================="
echo ""

# Initialize log file
echo "=== Deployment started at $(date) ===" > "$LOG_FILE"

# Step 1: Install Python 3.10 if not available (Universal VM deployment)
log "Checking Python 3.10 installation..."

# Detect package manager
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v zypper &> /dev/null; then
        echo "zypper"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    elif command -v apk &> /dev/null; then
        echo "apk"
    elif command -v brew &> /dev/null; then
        echo "brew"
    else
        echo "unknown"
    fi
}

# Install build dependencies for source compilation
install_build_deps() {
    local pkg_mgr=$1
    log "Installing build dependencies..."
    
    case "$pkg_mgr" in
        apt)
            sudo apt-get update -y
            sudo apt-get install -y build-essential curl wget git \
                libssl-dev libffi-dev zlib1g-dev libbz2-dev \
                libreadline-dev libsqlite3-dev libncurses5-dev \
                libncursesw5-dev xz-utils tk-dev liblzma-dev
            ;;
        dnf|yum)
            sudo $pkg_mgr groupinstall -y "Development Tools" 2>/dev/null || true
            sudo $pkg_mgr install -y gcc curl wget git \
                openssl-devel bzip2-devel libffi-devel zlib-devel \
                readline-devel sqlite-devel ncurses-devel xz-devel tk-devel
            ;;
        zypper)
            sudo zypper install -y gcc make curl wget git \
                libopenssl-devel libffi-devel zlib-devel libbz2-devel \
                readline-devel sqlite3-devel ncurses-devel xz-devel
            ;;
        pacman)
            sudo pacman -Sy --noconfirm base-devel curl wget git \
                openssl libffi zlib bzip2 readline sqlite ncurses xz
            ;;
        apk)
            sudo apk add --no-cache gcc musl-dev curl wget git \
                openssl-dev libffi-dev zlib-dev bzip2-dev \
                readline-dev sqlite-dev ncurses-dev xz-dev
            ;;
    esac
}

# Install Python 3.10 from source (universal fallback)
install_python_from_source() {
    log "Installing Python 3.10 from source (this may take a few minutes)..."
    
    local pkg_mgr=$(detect_package_manager)
    install_build_deps "$pkg_mgr"
    
    cd /tmp
    curl -sLO https://www.python.org/ftp/python/3.10.13/Python-3.10.13.tgz
    tar -xzf Python-3.10.13.tgz
    cd Python-3.10.13
    ./configure --enable-optimizations --prefix=/usr/local --with-ensurepip=install
    sudo make altinstall -j$(nproc 2>/dev/null || echo 2)
    cd "$PROJECT_ROOT"
    rm -rf /tmp/Python-3.10.13*
    
    # Create symlink if needed
    if [ -f /usr/local/bin/python3.10 ] && [ ! -f /usr/bin/python3.10 ]; then
        sudo ln -sf /usr/local/bin/python3.10 /usr/bin/python3.10 2>/dev/null || true
    fi
}

install_python310() {
    log "Installing Python 3.10..."
    
    local pkg_mgr=$(detect_package_manager)
    local os_id=""
    local os_version=""
    
    # Detect OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        os_id="$ID"
        os_version="$VERSION_ID"
        log "Detected OS: $PRETTY_NAME"
    fi
    
    case "$pkg_mgr" in
        apt)
            # Debian/Ubuntu-based (AWS Ubuntu, Azure Ubuntu, GCP Ubuntu, etc.)
            sudo apt-get update -y
            
            # Try direct install first (Ubuntu 22.04+ has Python 3.10)
            if sudo apt-get install -y python3.10 python3.10-venv python3.10-dev 2>/dev/null; then
                log "✓ Installed Python 3.10 via apt"
                return 0
            fi
            
            # Try deadsnakes PPA (Ubuntu)
            if [ "$os_id" = "ubuntu" ]; then
                log "Adding deadsnakes PPA..."
                sudo apt-get install -y software-properties-common
                sudo add-apt-repository -y ppa:deadsnakes/ppa
                sudo apt-get update -y
                if sudo apt-get install -y python3.10 python3.10-venv python3.10-dev 2>/dev/null; then
                    log "✓ Installed Python 3.10 via deadsnakes PPA"
                    return 0
                fi
            fi
            
            # Fallback to source
            install_python_from_source
            ;;
            
        dnf)
            # Fedora, RHEL 8+, Amazon Linux 2023, Rocky, AlmaLinux
            
            # Enable CRB/PowerTools repo for RHEL-based
            sudo dnf config-manager --set-enabled crb 2>/dev/null || \
            sudo dnf config-manager --set-enabled powertools 2>/dev/null || \
            sudo dnf config-manager --set-enabled PowerTools 2>/dev/null || true
            
            # Try EPEL
            sudo dnf install -y epel-release 2>/dev/null || true
            
            if sudo dnf install -y python3.10 python3.10-pip python3.10-devel 2>/dev/null; then
                log "✓ Installed Python 3.10 via dnf"
                return 0
            fi
            
            # Try python3.10 package name variations
            if sudo dnf install -y python310 python310-pip 2>/dev/null; then
                log "✓ Installed Python 3.10 via dnf (python310)"
                return 0
            fi
            
            # Fallback to source
            install_python_from_source
            ;;
            
        yum)
            # Amazon Linux 2, CentOS 7, older RHEL
            
            # Amazon Linux 2 specific
            if [ "$os_id" = "amzn" ] && command -v amazon-linux-extras &> /dev/null; then
                log "Using amazon-linux-extras..."
                if sudo amazon-linux-extras install -y python3.10 2>/dev/null; then
                    log "✓ Installed Python 3.10 via amazon-linux-extras"
                    return 0
                fi
            fi
            
            # Try EPEL + IUS
            sudo yum install -y epel-release 2>/dev/null || true
            sudo yum install -y https://repo.ius.io/ius-release-el7.rpm 2>/dev/null || true
            
            if sudo yum install -y python310 python310-pip python310-devel 2>/dev/null; then
                log "✓ Installed Python 3.10 via yum"
                return 0
            fi
            
            # Fallback to source
            install_python_from_source
            ;;
            
        zypper)
            # SUSE/openSUSE (Azure SLES, etc.)
            if sudo zypper install -y python310 python310-pip python310-devel 2>/dev/null; then
                log "✓ Installed Python 3.10 via zypper"
                return 0
            fi
            
            # Fallback to source
            install_python_from_source
            ;;
            
        pacman)
            # Arch Linux
            if sudo pacman -Sy --noconfirm python 2>/dev/null; then
                # Arch typically has latest Python, check version
                if python3 --version 2>&1 | grep -q "3.10"; then
                    log "✓ Python 3.10 available via pacman"
                    return 0
                fi
            fi
            
            # Try AUR or source
            install_python_from_source
            ;;
            
        apk)
            # Alpine Linux (lightweight containers/VMs)
            if sudo apk add --no-cache python3~=3.10 py3-pip 2>/dev/null; then
                log "✓ Installed Python 3.10 via apk"
                return 0
            fi
            
            # Fallback to source
            install_python_from_source
            ;;
            
        brew)
            # macOS (for local development)
            if brew install python@3.10 2>/dev/null; then
                log "✓ Installed Python 3.10 via Homebrew"
                return 0
            fi
            ;;
            
        *)
            warn "Unknown package manager. Installing from source..."
            install_python_from_source
            ;;
    esac
}

# Find Python 3.10 executable
find_python310() {
    local candidates=(
        "python3.10"
        "/usr/bin/python3.10"
        "/usr/local/bin/python3.10"
        "/opt/python3.10/bin/python3.10"
        "/usr/local/opt/python@3.10/bin/python3.10"  # Homebrew
        "$HOME/.pyenv/versions/3.10.*/bin/python"    # pyenv
    )
    
    for cmd in "${candidates[@]}"; do
        if command -v $cmd &> /dev/null 2>&1; then
            echo "$cmd"
            return 0
        fi
        # Handle glob patterns
        for expanded in $cmd; do
            if [ -x "$expanded" ]; then
                echo "$expanded"
                return 0
            fi
        done
    done
    
    return 1
}

# Check if Python 3.10 is available, install if not
PYTHON_CMD=$(find_python310) || PYTHON_CMD=""

if [ -n "$PYTHON_CMD" ]; then
    log "✓ Python 3.10 already installed: $PYTHON_CMD"
else
    log "Python 3.10 not found - installing..."
    install_python310
    
    # Re-check after installation
    PYTHON_CMD=$(find_python310) || PYTHON_CMD=""
    
    if [ -z "$PYTHON_CMD" ]; then
        # Final fallback to any available python3
        if command -v python3 &> /dev/null; then
            PYTHON_CMD="python3"
            warn "Python 3.10 installation may have failed. Using $(python3 --version)"
        else
            error "Python 3.10 installation failed. Please install manually."
        fi
    fi
fi

PYTHON_VERSION=$($PYTHON_CMD --version 2>&1)
log "Using Python: $PYTHON_VERSION ($PYTHON_CMD)"

# Verify Python version is 3.10.x
PYTHON_MAJOR=$($PYTHON_CMD -c "import sys; print(sys.version_info.major)")
PYTHON_MINOR=$($PYTHON_CMD -c "import sys; print(sys.version_info.minor)")
if [ "$PYTHON_MAJOR" -ne 3 ] || [ "$PYTHON_MINOR" -ne 10 ]; then
    warn "Python 3.10 required. Found $PYTHON_VERSION. Some dependencies may have compatibility issues."
fi

# Step 2: Verify project structure
log "Verifying project structure..."

cd "$PROJECT_ROOT"

# Check for required files
if [ ! -f "main.py" ]; then
    error "main.py not found in project root"
fi

if [ ! -f "requirements.txt" ]; then
    error "requirements.txt not found in project root"
fi

if [ ! -f "credentials.json" ]; then
    error "credentials.json not found in project root. This file is required for GA4 and Google Sheets authentication."
fi

if [ ! -d "src" ]; then
    error "src/ directory not found"
fi

log "✓ Project structure verified"

# Step 3: Create/Update virtual environment
log "Setting up virtual environment at .venv..."

if [ -d "$VENV_DIR" ]; then
    log "Virtual environment exists, checking activation..."
else
    log "Creating new virtual environment..."
    $PYTHON_CMD -m venv "$VENV_DIR"
fi

# Activate virtual environment
if [ -f "$VENV_DIR/bin/activate" ]; then
    source "$VENV_DIR/bin/activate"
elif [ -f "$VENV_DIR/Scripts/activate" ]; then
    source "$VENV_DIR/Scripts/activate"
else
    error "Failed to locate virtual environment activation script"
fi

log "✓ Virtual environment activated"

# Step 4: Upgrade pip (using python -m pip for cross-platform compatibility)
log "Upgrading pip..."
$PYTHON_CMD -m pip install --upgrade pip -q

# Step 5: Install dependencies
log "Installing dependencies from requirements.txt..."
$PYTHON_CMD -m pip install -r requirements.txt -q

log "✓ Dependencies installed"

# Step 6: Verify critical environment variables
log "Checking environment configuration..."

# Load .env if exists
if [ -f ".env" ]; then
    log "Loading environment variables from .env"
    
    # Convert Windows line endings (CRLF) to Unix (LF) if needed
    if grep -q $'\r' .env 2>/dev/null; then
        log "Converting .env line endings from CRLF to LF..."
        if command -v sed &> /dev/null; then
            sed -i 's/\r$//' .env 2>/dev/null || sed -i '' 's/\r$//' .env 2>/dev/null || true
        elif command -v tr &> /dev/null; then
            tr -d '\r' < .env > .env.tmp && mv .env.tmp .env
        fi
    fi
    
    set -a
    source .env
    set +a
fi

# Check for LITELLM_API_KEY
if [ -z "$LITELLM_API_KEY" ]; then
    warn "LITELLM_API_KEY not set in environment. Make sure it's configured in .env"
fi

# Check for SHEET_ID (optional but recommended)
if [ -z "$SHEET_ID" ]; then
    warn "SHEET_ID not set. SEO Agent queries will require explicit sheet ID."
fi

log "✓ Environment configuration checked"

# Step 7: Stop any existing process on port 8080
log "Checking if port $PORT is available..."

if command -v lsof &> /dev/null; then
    PID=$(lsof -t -i:$PORT 2>/dev/null || true)
    if [ -n "$PID" ]; then
        warn "Port $PORT is in use by PID $PID. Attempting to stop..."
        kill -9 $PID 2>/dev/null || true
        sleep 2
    fi
elif command -v netstat &> /dev/null; then
    # Windows/alternative check
    if netstat -tuln | grep -q ":$PORT "; then
        warn "Port $PORT appears to be in use. Please ensure it's free."
    fi
fi

log "✓ Port $PORT ready"

# Step 8: Validate Python modules can be imported
log "Validating Python imports..."

$PYTHON_CMD -c "
import sys
sys.path.insert(0, 'src')

# Test critical imports
try:
    from fastapi import FastAPI
    print('  ✓ FastAPI')
except ImportError as e:
    print(f'  ✗ FastAPI: {e}')
    sys.exit(1)

try:
    from openai import OpenAI
    print('  ✓ OpenAI SDK (for LiteLLM)')
except ImportError as e:
    print(f'  ✗ OpenAI: {e}')
    sys.exit(1)

try:
    from google.analytics.data_v1beta import BetaAnalyticsDataClient
    print('  ✓ GA4 Data API')
except ImportError as e:
    print(f'  ✗ GA4 Data API: {e}')
    sys.exit(1)

try:
    import gspread
    print('  ✓ gspread (Google Sheets)')
except ImportError as e:
    print(f'  ✗ gspread: {e}')
    sys.exit(1)

try:
    import pandas
    print('  ✓ pandas')
except ImportError as e:
    print(f'  ✗ pandas: {e}')
    sys.exit(1)

print('All imports successful!')
"

if [ $? -ne 0 ]; then
    error "Import validation failed. Check dependencies."
fi

log "✓ All Python modules validated"

# Step 9: Start the server in background
log "Starting server on port $PORT..."

# Create a startup script for proper background execution
# Uses the specific Python from the venv for reliability
cat > "$PROJECT_ROOT/.start_server.sh" << STARTUP_EOF
#!/bin/bash
cd "$PROJECT_ROOT"

# Activate venv and use its python directly
if [ -f ".venv/bin/activate" ]; then
    source .venv/bin/activate
    exec .venv/bin/python main.py
elif [ -f ".venv/Scripts/activate" ]; then
    source .venv/Scripts/activate
    exec .venv/Scripts/python.exe main.py
else
    # Fallback
    exec $PYTHON_CMD main.py
fi
STARTUP_EOF

chmod +x "$PROJECT_ROOT/.start_server.sh"

# Start server in background with nohup
nohup "$PROJECT_ROOT/.start_server.sh" > "$PROJECT_ROOT/server.log" 2>&1 &
SERVER_PID=$!

# Give the process a moment to start or fail immediately
sleep 2

# Check if process is still running
if ! kill -0 $SERVER_PID 2>/dev/null; then
    log "Server process died immediately. Checking logs..."
    if [ -f "$PROJECT_ROOT/server.log" ]; then
        echo "--- Server Log Start ---"
        cat "$PROJECT_ROOT/server.log"
        echo "--- Server Log End ---"
    fi
    error "Server failed to start. See logs above."
fi

log "Server starting with PID: $SERVER_PID"

# Step 10: Wait for server to be ready
log "Waiting for server to become ready..."

MAX_WAIT=60
WAIT_COUNT=0
SERVER_READY=false

while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    if curl -s "http://localhost:$PORT/health" > /dev/null 2>&1; then
        SERVER_READY=true
        break
    fi
    sleep 1
    WAIT_COUNT=$((WAIT_COUNT + 1))
    
    # Show progress every 10 seconds
    if [ $((WAIT_COUNT % 10)) -eq 0 ]; then
        log "Still waiting... ($WAIT_COUNT seconds)"
    fi
done

if [ "$SERVER_READY" = true ]; then
    log "✓ Server is ready!"
else
    error "Server failed to start within $MAX_WAIT seconds. Check server.log for details."
fi

# Step 11: Verify endpoint
log "Verifying API endpoint..."

HEALTH_RESPONSE=$(curl -s "http://localhost:$PORT/health")
if echo "$HEALTH_RESPONSE" | grep -q "healthy"; then
    log "✓ Health check passed"
else
    warn "Health check response: $HEALTH_RESPONSE"
fi

# Done!
echo ""
echo "============================================================================="
echo "  DEPLOYMENT COMPLETE"
echo "============================================================================="
echo ""
echo "  Server is running on: http://localhost:$PORT"
echo "  PID: $SERVER_PID"
echo ""
echo "  Endpoints:"
echo "    - POST /query     : Process natural language queries"
echo "    - GET  /health    : Health check"
echo "    - GET  /docs      : API documentation (Swagger UI)"
echo ""
echo "  Test with:"
echo "    curl -X POST http://localhost:$PORT/query \\"
echo "      -H 'Content-Type: application/json' \\"
echo "      -d '{\"query\": \"What are my top pages?\", \"propertyId\": \"123456789\"}'"
echo ""
echo "  Logs:"
echo "    - Server log: $PROJECT_ROOT/server.log"
echo "    - Deploy log: $PROJECT_ROOT/deploy.log"
echo "    - API log: $PROJECT_ROOT/api.log"
echo ""
echo "============================================================================="

# Save PID for later reference
echo $SERVER_PID > "$PROJECT_ROOT/.server.pid"

log "Deployment completed successfully at $(date)"
