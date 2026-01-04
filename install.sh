#!/bin/bash
# We don't need return codes for "$(command)", only stdout is needed.
# Allow `[[ -n "$(command)" ]]`, `func "$(command)"`, pipes, etc.
# shellcheck disable=SC2312

set -e
set -u

# Configuration
CLI_NAME="prompt-share"
GITHUB_REPO="${GITHUB_REPO:-martynovb/prompt_share_cli_install}"
VERSION="${VERSION:-latest}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

abort() {
  printf "%s\n" "$@" >&2
  exit 1
}

chomp() {
  printf "%s" "${1/"$'\n'"/}"
}

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
            if [ "$os" != "windows" ] && [ "$EUID" -ne 0 ]; then
                abort "$(
                    cat <<EOABORT
Cannot create directory: ${dir}

Try one of the following:
  1. Use a user-writable directory:
     INSTALL_DIR=~/.local/bin bash install.sh
  2. Run with sudo (for system-wide install):
     sudo bash install.sh
EOABORT
                )"
            else
                abort "Cannot create directory: ${dir}"
            fi
        fi
    fi
    
    # Check if directory is writable
    if [ ! -w "$dir" ]; then
        if [ "$os" != "windows" ] && [ "$EUID" -ne 0 ]; then
            abort "$(
                cat <<EOABORT
Directory is not writable: ${dir}

Try one of the following:
  1. Use a user-writable directory:
     INSTALL_DIR=~/.local/bin bash install.sh
  2. Run with sudo (for system-wide install):
     sudo bash install.sh
EOABORT
            )"
        else
            abort "Directory is not writable: ${dir}"
        fi
    fi
}

# Helper to join command arguments for display
shell_join() {
  local arg
  printf "%s" "$1"
  shift
  for arg in "$@"
  do
    printf " %s" "${arg// /\ }"
  done
}

# Retry function
retry() {
  local tries="$1" n="$1" pause=2
  shift
  if ! "$@"
  then
    while [[ $((--n)) -gt 0 ]]
    do
      printf "${YELLOW}Trying again in %d seconds: %s${NC}\n" "${pause}" "$(shell_join "$@")" >&2
      sleep "${pause}"
      ((pause *= 2))
      if "$@"
      then
        return
      fi
    done
    abort "$(printf "Failed %d times doing: %s" "${tries}" "$(shell_join "$@")")"
  fi
}

# Fetch API response with retry logic
fetch_api_response() {
    local api_url="$1"
    local response=""
    
    if command -v curl >/dev/null 2>&1; then
        response=$(retry 3 curl -sL "${api_url}" 2>/dev/null)
    elif command -v wget >/dev/null 2>&1; then
        response=$(retry 3 wget -qO- "${api_url}" 2>/dev/null)
    else
        abort "Neither curl nor wget is available. Please install one of them."
    fi
    
    echo "$response"
}

# Get latest release tag from GitHub
# This function tries multiple methods to get the latest tag
get_latest_tag() {
    local repo=$1
    
    # Method 1: Try GitHub Releases API (most reliable for releases)
    local latest_tag=""
    local api_url=""
    local response=""
    
    # Try releases/latest endpoint first (this is the most reliable)
    api_url="https://api.github.com/repos/${repo}/releases/latest"
    response=$(fetch_api_response "${api_url}")
    latest_tag=$(echo "$response" | \
        grep '"tag_name"' | \
        sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' | \
        head -1)
    
    # If that fails, try getting the latest from all releases
    if [ -z "$latest_tag" ]; then
        api_url="https://api.github.com/repos/${repo}/releases"
        response=$(fetch_api_response "${api_url}")
        latest_tag=$(echo "$response" | \
            grep '"tag_name"' | \
            sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' | \
            head -1)
    fi
    
    # Method 2: If releases API fails, try Git tags API (fallback)
    # Note: This doesn't guarantee "latest" by version, just the first tag returned
    if [ -z "$latest_tag" ]; then
        api_url="https://api.github.com/repos/${repo}/tags"
        response=$(fetch_api_response "${api_url}")
        latest_tag=$(echo "$response" | \
            grep '"name"' | \
            sed 's/.*"name": *"\([^"]*\)".*/\1/' | \
            head -1)
    fi
    
    # Clean up the tag (remove any whitespace)
    if [ -n "$latest_tag" ]; then
        latest_tag=$(chomp "$latest_tag")
    fi
    
    echo "$latest_tag"
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
        abort "GITHUB_REPO must be set. For GitHub: GITHUB_REPO=\"username/repo\" bash install.sh"
    fi
    
    # Resolve "latest" to actual tag name (GitHub doesn't support "latest" in download URLs)
    if [ "$version" = "latest" ]; then
        echo "${YELLOW}Fetching latest release version...${NC}" >&2
        local latest_tag=$(get_latest_tag "$GITHUB_REPO")
        
        if [ -z "$latest_tag" ]; then
            abort "$(
                cat <<EOABORT
Failed to fetch latest release version from GitHub.

Possible issues:
  - Network connectivity problems
  - GitHub API rate limiting
  - Repository may not have any releases
  - Check: https://github.com/${GITHUB_REPO}/releases

You can specify a version explicitly:
  VERSION=v1.0.0 bash install.sh
EOABORT
            )"
        fi
        
        version="$latest_tag"
        echo "${GREEN}Latest version: ${version}${NC}" >&2
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
        abort "Unsupported platform: $(uname -s) $(uname -m)"
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
        abort "Neither curl nor wget is installed. Please install one of them."
    fi
    
    if [ "$download_success" = false ]; then
        abort "$(
            cat <<EOABORT
Failed to download binary from:
  ${download_url}

Possible issues:
  - Release version '${VERSION}' does not exist
  - GitHub Releases may not be publicly accessible
  - Check: https://github.com/${GITHUB_REPO}/releases
  - Network connectivity issues
EOABORT
        )"
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
        abort "Installation verification failed: ${install_path} was not created."
    fi
}

# Run main function
main "$@"