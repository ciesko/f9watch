#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if [ "$#" -ne 0 ]; then
    echo "Run ./prerequisites.sh without arguments." >&2
    exit 1
fi
if [ "$(uname -s)" != Darwin ]; then
    echo "This setup script is for macOS." >&2
    exit 1
fi
if ! command -v brew >/dev/null; then
    echo "Install Homebrew from https://brew.sh, then run this script again." >&2
    exit 1
fi
echo "Install Connect IQ SDK Manager, Java, and libmtp (USB transfer)?"
read -r -p "[y/N] " answer
case "$answer" in y|Y|yes|YES) ;; *) echo "Nothing installed."; exit 0 ;; esac

if ! xcode-select -p >/dev/null 2>&1; then
    xcode-select --install
    echo "Finish the Apple Command Line Tools installation, then rerun this script."
    exit 1
fi
brew install openjdk libmtp pkg-config
brew install --cask connectiq-sdk-manager
cat <<'EOF'

Open Connect IQ SDK Manager and sign in with your Garmin account.
Install the latest stable SDK and both device packages:
  fenix9pro51mm (AMOLED, NOT fenix9prosolar51mm)
  fenix5x      (NOT fenix5xplus)
Set that SDK as current in SDK Manager, then run ./run.sh.

No files have been sent to a watch. Artwork resources are already included;
Python and image libraries are not needed for building or deploying.
EOF
open -a "SdkManager"
