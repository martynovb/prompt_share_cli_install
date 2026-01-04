#!/bin/bash
set -e

# Configuration
CLI_NAME="prompt-share"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
GITHUB_REPO="${GITHUB_REPO:-martynovb/prompt_share_cli_install}"  # Default to public install repo
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

# Get download URL for GitHub Releases
get_download_url() {
    local platform=$1
    local version=$2
    
    local filename="${CLI_NAME}-${platform}"
    if [ "$(echo $platform | cut -d'-' -f1)" = "windows" ]; then
        filename="${filename}.exe"
    fi
    
    # GITHUB_REPO now has a default value, so this check is no longer needed
    # But we keep it for backward compatibility if someone explicitly sets it to empty
    if [ -z "$GITHUB_REPO" ]; then
        echo "${RED}Error: GITHUB_REPO must be set${NC}" >&2
        echo "For GitHub: GITHUB_REPO=\"username/repo\" bash install.sh" >&2
        exit 1
    fi
    
    if [ "$version" = "latest" ]; then
        # Get latest release from GitHub API
        local latest_tag=$(curl -s "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null | grep -oP '"tag_name":\s*"\K[^"]+' | head -1 || echo "")
        if [ -n "$latest_tag" ]; then
            version="$latest_tag"
        fi
    fi
    
    # GitHub Releases download URL
    echo "https://github.com/${GITHUB_REPO}/releases/download/${version}/${filename}"
}

# Check if running as root (for system-wide install)
check_permissions() {
    if [ ! -w "$INSTALL_DIR" ] && [ "$EUID" -ne 0 ]; then
        echo "${YELLOW}Warning: ${INSTALL_DIR} is not writable. You may need to run with sudo.${NC}"
        echo "Alternatively, set INSTALL_DIR to a writable directory:"
        echo "  INSTALL_DIR=~/.local/bin bash install.sh"
        exit 1
    fi
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
    
    # Check permissions
    check_permissions
    
    # Create install directory if it doesn't exist
    mkdir -p "$INSTALL_DIR"
    
    # Get download URL
    local download_url=$(get_download_url "$platform" "$VERSION")
    echo "Downloading from: ${download_url}"
    
    # Create temporary directory
    local temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT
    
    # Download binary
    local output_file="${temp_dir}/${CLI_NAME}"
    if [ "$(echo $platform | cut -d'-' -f1)" = "windows" ]; then
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
    
    # Make executable
    chmod +x "$output_file"
    
    # Install to target directory
    local install_path="${INSTALL_DIR}/${CLI_NAME}"
    echo "Installing to: ${install_path}"
    mv "$output_file" "$install_path"
    
    # Verify installation
    if [ -f "$install_path" ] && [ -x "$install_path" ]; then
        echo "${GREEN}✓ Installation successful!${NC}"
        echo ""
        echo "You can now use '${CLI_NAME}' from anywhere."
        echo "Try running: ${CLI_NAME} --help"
        
        # Check if install directory is in PATH
        if echo "$PATH" | grep -q "$INSTALL_DIR"; then
            echo "${GREEN}✓ ${INSTALL_DIR} is in your PATH${NC}"
        else
            echo "${YELLOW}Warning: ${INSTALL_DIR} is not in your PATH${NC}"
            echo "Add it to your PATH by adding this line to your shell profile:"
            echo "  export PATH=\"${INSTALL_DIR}:\$PATH\""
        fi
    else
        echo "${RED}Error: Installation verification failed${NC}" >&2
        exit 1
    fi
}

# Run main function
main "$@"

