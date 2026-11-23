#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"

fail() { echo "$*" >&2; exit 1; }
confirm() {
    local answer
    read -r -p "$1 [y/N] " answer
    case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

[ "$#" -eq 0 ] || fail "Run ./run.sh without arguments; choices are interactive."
[ "$(uname -s)" = Darwin ] || fail "This launcher supports macOS."
echo "Mars Watch"
echo "1) Run in simulator"
echo "2) Deploy over USB"
echo "3) Simulator, then USB deploy"
echo "4) Build only"
echo "5) Export package for Connect IQ Store"
echo "6) Quit"
read -r -p "Action [1]: " action
action="${action:-1}"
case "$action" in 1|2|3|4|5) ;; 6) exit 0 ;; *) fail "Choose 1-6." ;; esac
if [ "$action" != 5 ]; then
    echo "1) fenix 9 Pro 51mm AMOLED"
    echo "2) fenix 5X"
    read -r -p "Watch [1]: " choice
    case "${choice:-1}" in
        1) device=fenix9pro51mm ;;
        2) device=fenix5x ;;
        *) fail "Choose 1 or 2." ;;
    esac
fi

CIQ="$HOME/Library/Application Support/Garmin/ConnectIQ"
SDK="${CIQ_SDK_HOME:-}"
if [ -z "$SDK" ] && [ -f "$CIQ/current-sdk.cfg" ]; then
    SDK="$(tr -d '\r\n' < "$CIQ/current-sdk.cfg")"
fi
[ -n "$SDK" ] && [ -x "$SDK/bin/monkeyc" ] ||
    fail "No current Connect IQ SDK. Inspect/run ./prerequisites.sh, install an SDK and devices in SDK Manager. Alternatively set CIQ_SDK_HOME to your SDK directory."

if command -v brew >/dev/null; then
    JAVA_PREFIX="$(brew --prefix openjdk 2>/dev/null || true)"
    if [ -n "$JAVA_PREFIX" ] && [ -x "$JAVA_PREFIX/bin/java" ]; then
        export PATH="$JAVA_PREFIX/bin:$PATH"
    fi
fi
java -version >/dev/null 2>&1 || fail "Java is missing. Inspect/run ./prerequisites.sh."
for target in ${device:-fenix9pro51mm fenix5x}; do
    [ -f "$CIQ/Devices/$target/compiler.json" ] ||
        fail "Missing Garmin device package: $target. Download it with SDK Manager."
done
mkdir -p bin .local
KEY="${CIQ_DEVELOPER_KEY:-$ROOT/.local/developer_key.der}"
if [ ! -f "$KEY" ]; then
    [ -z "${CIQ_DEVELOPER_KEY:-}" ] || fail "CIQ_DEVELOPER_KEY does not exist: $KEY"
    echo "Creating a private signing key in .local/ (ignored by Git). Keep it for future store updates."
    if ! (umask 077; openssl genrsa 4096 2>/dev/null |
        openssl pkcs8 -topk8 -inform PEM -outform DER -nocrypt -out "$KEY.tmp"); then
        rm -f "$KEY.tmp"
        fail "Could not create signing key."
    fi
    mv "$KEY.tmp" "$KEY"
fi
if [ "$action" = 5 ]; then
    "$SDK/bin/monkeyc" -f monkey.jungle -e -r -w -l 3 -y "$KEY" -o bin/MarsWatch.iq
    echo "Store package: $ROOT/bin/MarsWatch.iq"
    exit 0
fi

PRG="$ROOT/bin/MarsWatch-$device.prg"
"$SDK/bin/monkeyc" -f monkey.jungle -d "$device" -w -l 3 -y "$KEY" -o "$PRG"
echo "Built: $PRG"
if [ "$action" = 1 ] || [ "$action" = 3 ]; then
    "$SDK/bin/connectiq"
    # The simulator's local MonkeyDo service takes a moment to start.
    ready=false
    for ((attempt=0; attempt<30; attempt++)); do
        if nc -z 127.0.0.1 1234 >/dev/null 2>&1; then ready=true; break; fi
        sleep 1
    done
    [ "$ready" = true ] || fail "Simulator did not become ready on port 1234."
    "$SDK/bin/monkeydo" "$PRG" "$device"
    echo "Simulator loaded. Use its time/settings controls to inspect each scene and low-power mode."
fi
if [ "$action" = 2 ] || [ "$action" = 3 ]; then
    if [ "$action" = 3 ]; then
        confirm "Ready to deploy to the connected $device?" || exit 0
    fi
    echo "Connect only the target Garmin watch with a data cable; select USB/MTP mode."
    echo "Close Garmin Express, Android File Transfer, and OpenMTP."
    if [ "$device" = fenix5x ]; then
        mounts=()
        for volume in /Volumes/*; do
            if [ -f "$volume/GARMIN/GarminDevice.xml" ] && [ -d "$volume/GARMIN/APPS" ]; then
                mounts+=("$volume")
            fi
        done
        [ "${#mounts[@]}" -eq 1 ] || fail "Expected exactly one mounted Garmin volume; found ${#mounts[@]}."
        volume="${mounts[0]}"
        if ! grep -Eiq '<Description>[^<]*(f.nix 5X|fenix 5X)(</Description>|[^<]*</Description>)' "$volume/GARMIN/GarminDevice.xml" ||
           grep -Eiq '<Description>[^<]*5X[^<]*Plus' "$volume/GARMIN/GarminDevice.xml"; then
            fail "The mounted watch is not a fenix 5X. Refusing to send a different device's binary."
        fi
        confirm "Copy Mars Watch to $volume/GARMIN/APPS?" || exit 0
        destination="$volume/GARMIN/APPS/MARSWATCH.PRG"
        cp "$PRG" "$destination.tmp"
        cmp -s "$PRG" "$destination.tmp" || fail "USB copy verification failed; the old build is unchanged."
        mv -f "$destination.tmp" "$destination"
        sync
        echo "Copied and verified. Eject $volume in Finder, disconnect, then select Mars Watch on the watch."
    else
        command -v pkg-config >/dev/null && pkg-config --exists libmtp ||
            fail "libmtp/pkg-config is missing. Inspect/run ./prerequisites.sh."
        # pkg-config deliberately emits compiler/linker argument lists.
        clang -std=c11 -Wall -Wextra -Werror tools/mtp-install.c \
            $(pkg-config --cflags --libs libmtp) -o bin/mtp-install
        if bin/mtp-install "$PRG"; then
            :
        else
            status=$?
            [ "$status" -eq 2 ] && exit 0
            fail "MTP deployment did not complete. See the installer message above."
        fi
        echo "Transferred and verified. Disconnect, then select Mars Watch on the watch."
    fi
fi
