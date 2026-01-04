#!/bin/bash
set -e

# Configuration
CLI_NAME="prompt-share"
GITHUB_REPO="${GITHUB_REPO:-martynovb/prompt_share_cli_install}"
VERSION="${VERSION:-latest}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Detect OS and architecture
detect_platform() {
    local os=""
    local arch=""
    
    case "$(uname -s)" in
        Linux*)     os="linux" ;;
        Darwin*)    os="macos" ;;
        CYGWIN*)    os="windows" ;;
        MINGW*)     os="windows" ;;
        MSYS*)      os="windows" ;;
        *)          os="unknown" ;;
    esac
    
    case "$(uname -m)" in
        x86_64)     arch="x64" ;;
        amd64)      arch="x64" ;;
        arm64)      arch="arm64" ;;
        aarch64)    arch="arm64" ;;
        *)          arch="unknown" ;;
    esac
    
    echo "${os}-${arch}"
}

# Get default install directory based on platform and permissions
get_default_install_dir() {
    local platform=$1
    local os=$(echo $platform | cut -d'-' -f1)
    
    # If user explicitly set INSTALL_DIR, use it
    if [ -n "$INSTALL_DIR" ]; then
        echo "$INSTALL_DIR"
        return
    fi
    
    # For Windows (Git Bash), use ~/bin
    if [ "$os" = "windows" ]; then
        if [ -n "$HOME" ]; then
            echo "$HOME/bin"
        else
            echo "/c/Users/$USER/bin"
        fi
        return
    fi
    
    # For Linux/macOS, prefer user-local directory (no sudo needed)
    # This follows XDG Base Directory Specification and common practice
    if [ -n "$HOME" ]; then
        local user_bin="$HOME/.local/bin"
        # Try to create it to check if it's writable
        if mkdir -p "$user_bin" 2>/dev/null && [ -w "$user_bin" ] 2>/dev/null; then
            echo "$user_bin"
            return
        fi
    fi
    
    # Fallback to /usr/local/bin (requires sudo)
    echo "/usr/local/bin"
}

# Check and prepare install directory
prepare_install_dir() {
    local dir=$1
    local platform=$2
    local os=$(echo $platform | cut -d'-' -f1)
    
    # Try to create directory if it doesn't exist
    if [ ! -d "$dir" ]; then
        if mkdir -p "$dir" 2>/dev/null; then
            echo "Created directory: $dir"
        else
            echo "${RED}Error: Cannot create directory: $dir${NC}" >&2
            if [ "$os" != "windows" ] && [ "$EUID" -ne 0 ]; then
                echo "" >&2
                echo "Try one of the following:" >&2
                echo "  1. Use a user-writable directory:" >&2
                echo "     INSTALL_DIR=~/.local/bin bash install.sh" >&2
                echo "  2. Run with sudo (for system-wide install):" >&2
                echo "     sudo bash install.sh" >&2
            fi
            exit 1
        fi
    fi
    
    # Check if directory is writable
    if [ ! -w "$dir" ]; then
        echo "${RED}Error: Directory is not writable: $dir${NC}" >&2
        if [ "$os" != "windows" ] && [ "$EUID" -ne 0 ]; then
            echo "" >&2
            echo "Try one of the following:" >&2
            echo "  1. Use a user-writable directory:" >&2
            echo "     INSTALL_DIR=~/.local/bin bash install.sh" >&2
            echo "  2. Run with sudo (for system-wide install):" >&2
            echo "     sudo bash install.sh" >&2
        fi
        exit 1
    fi
}

# Get download URL for GitHub Releases
get_download_url() {
    local platform=$1
    local version=$2
    
    local filename="${CLI_NAME}-${platform}"
    if [ "$(echo $platform | cut -d'-' -f1)" = "windows" ]; then
        filename="${filename}.exe"
    fi
    
    if [ -z "$GITHUB_REPO" ]; then
        echo "${RED}Error: GITHUB_REPO must be set${NC}" >&2
        echo "For GitHub: GITHUB_REPO=\"username/repo\" bash install.sh" >&2
        exit 1
    fi
    
    if [ "$version" = "latest" ]; then
        local latest_tag=$(curl -s "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null | grep -oP '"tag_name":\s*"\K[^"]+' | head -1 || echo "")
        if [ -n "$latest_tag" ]; then
            version="$latest_tag"
        fi
    fi
    
    echo "https://github.com/${GITHUB_REPO}/releases/download/${version}/${filename}"
}

# Main installation function
main() {
    echo "${GREEN}Installing ${CLI_NAME}...${NC}"
    
    # Detect platform
    local platform=$(detect_platform)
    echo "Detected platform: ${platform}"
    
    if [ "$platform" = "unknown-unknown" ] || [ "$(echo $platform | cut -d'-' -f1)" = "unknown" ]; then
        echo "${RED}Error: Unsupported platform${NC}" >&2
        exit 1
    fi
    
    # Determine install directory
    INSTALL_DIR=$(get_default_install_dir "$platform")
    echo "Install directory: ${INSTALL_DIR}"
    
    # Prepare install directory (create if needed, check permissions)
    prepare_install_dir "$INSTALL_DIR" "$platform"
    
    # Get download URL
    local download_url=$(get_download_url "$platform" "$VERSION")
    echo "Downloading from: ${download_url}"
    
    # Create temporary directory
    local temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT
    
    # Download binary
    local output_file="${temp_dir}/${CLI_NAME}"
    local os=$(echo $platform | cut -d'-' -f1)
    if [ "$os" = "windows" ]; then
        output_file="${output_file}.exe"
    fi
    
    echo "Downloading binary..."
    
    local download_success=false
    
    if command -v curl >/dev/null 2>&1; then
        if curl -L -f -o "$output_file" "$download_url" 2>/dev/null; then
            download_success=true
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -O "$output_file" "$download_url" 2>/dev/null; then
            download_success=true
        fi
    else
        echo "${RED}Error: Neither curl nor wget is installed${NC}" >&2
        exit 1
    fi
    
    if [ "$download_success" = false ]; then
        echo "${RED}Error: Failed to download binary${NC}" >&2
        echo "Tried URL: $download_url" >&2
        echo "" >&2
        echo "Possible issues:" >&2
        echo "  - Release version '${VERSION}' does not exist" >&2
        echo "  - GitHub Releases may not be publicly accessible" >&2
        echo "  - Check: https://github.com/${GITHUB_REPO}/releases" >&2
        echo "  - Network connectivity issues" >&2
        exit 1
    fi
    
    # Make executable (skip on Windows)
    if [ "$os" != "windows" ]; then
        chmod +x "$output_file"
    fi
    
    # Install to target directory
    local install_path="${INSTALL_DIR}/${CLI_NAME}"
    if [ "$os" = "windows" ]; then
        install_path="${install_path}.exe"
    fi
    echo "Installing to: ${install_path}"
    mv "$output_file" "$install_path"
    
    # Verify installation
    if [ -f "$install_path" ]; then
        if [ "$os" != "windows" ]; then
            [ -x "$install_path" ] || chmod +x "$install_path"
        fi
        
        echo "${GREEN}✓ Installation successful!${NC}"
        echo ""
        echo "You can now use '${CLI_NAME}' from anywhere."
        echo "Try running: ${CLI_NAME} --help"
        
        # Check if install directory is in PATH
        if echo "$PATH" | grep -q "$INSTALL_DIR"; then
            echo "${GREEN}✓ ${INSTALL_DIR} is in your PATH${NC}"
        else
            echo "${YELLOW}Warning: ${INSTALL_DIR} is not in your PATH${NC}"
            echo ""
            if [ "$os" = "windows" ]; then
                echo "Add it to your PATH by adding this line to your ~/.bashrc or ~/.bash_profile:"
                echo "  export PATH=\"${INSTALL_DIR}:\$PATH\""
            else
                local shell_profile=""
                if [ -f "$HOME/.zshrc" ]; then
                    shell_profile="$HOME/.zshrc"
                elif [ -f "$HOME/.bashrc" ]; then
                    shell_profile="$HOME/.bashrc"
                elif [ -f "$HOME/.bash_profile" ]; then
                    shell_profile="$HOME/.bash_profile"
                fi
                
                if [ -n "$shell_profile" ]; then
                    echo "Add it to your PATH by running:"
                    echo "  echo 'export PATH=\"${INSTALL_DIR}:\$PATH\"' >> $shell_profile"
                    echo "  source $shell_profile"
                else
                    echo "Add it to your PATH by adding this line to your shell profile:"
                    echo "  export PATH=\"${INSTALL_DIR}:\$PATH\""
                fi
            fi
        fi
    else
        echo "${RED}Error: Installation verification failed${NC}" >&2
        exit 1
    fi
}

# Run main function
main "$@"