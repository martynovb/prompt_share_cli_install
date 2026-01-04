# Prompt Share CLI

Extract and export chats from Claude, Copilot, and Cursor.

## Installation

### Quick Install (Recommended)

Install the bundled CLI using the install script:

```bash
curl -fsSL https://raw.githubusercontent.com/martynovb/prompt_share_cli_install/main/install.sh | bash
```

Or download and run:

```bash
curl -fsSL https://raw.githubusercontent.com/martynovb/prompt_share_cli_install/main/install.sh -o install.sh
bash install.sh
```

The install script will:
- Detect your OS and architecture
- Download the appropriate binary from GitHub Releases
- Install to `/usr/local/bin` (or custom location via `INSTALL_DIR`)
- Set executable permissions

### Manual Installation

1. Download the binary for your platform from the [Releases page](https://github.com/martynovb/prompt_share_cli_install/releases)
2. Make it executable (Unix-like systems):
   ```bash
   chmod +x prompt-share-linux-x64
   ```
3. Move to a directory in your PATH:
   ```bash
   mv prompt-share-linux-x64 /usr/local/bin/prompt-share
   ```