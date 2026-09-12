#!/bin/bash
# macos-run.sh MAC_USER_PASSWORD VNC_PASSWORD MAC_REALNAME

set -e

echo "=== macOS VNC setup ==="
echo "macOS: $(sw_vers -productVersion)"
echo "Architecture: $(uname -m)"

# Disable Spotlight indexing
sudo mdutil -i off -a || true

# Create user
if ! id koolisw >/dev/null 2>&1; then
    sudo dscl . -create /Users/koolisw
    sudo dscl . -create /Users/koolisw UserShell /bin/bash
    sudo dscl . -create /Users/koolisw RealName "$3"
    sudo dscl . -create /Users/koolisw UniqueID 1001
    sudo dscl . -create /Users/koolisw PrimaryGroupID 80
    sudo dscl . -create /Users/koolisw NFSHomeDirectory /Users/koolisw
    sudo dscl . -passwd /Users/koolisw "$1"
    sudo createhomedir -c -u koolisw > /dev/null
else
    echo "User koolisw already exists."
    sudo dscl . -passwd /Users/koolisw "$1"
fi

# Add user to admin group
sudo dscl . -append /Groups/admin GroupMembership koolisw 2>/dev/null || true

echo "Configuring Remote Management privileges..."

# Allow local users and grant full ARD privileges
sudo defaults write /Library/Preferences/com.apple.RemoteManagement ARD_AllLocalUsers -bool true
sudo defaults write /Library/Preferences/com.apple.RemoteManagement ARD_AllLocalUsersPrivs -int 1073742079

# Give koolisw full ARD privileges
sudo dscl . -create /Users/koolisw dsAttrTypeNative:naprivs -1073741569 2>/dev/null || true

# Allow the user through Screen Sharing access group if it exists
if dscl . -read /Groups/com.apple.access_screensharing >/dev/null 2>&1; then
    sudo dscl . -append /Groups/com.apple.access_screensharing GroupMembership koolisw 2>/dev/null || true
fi

# Remove the user from the disabled Screen Sharing group if present
if dscl . -read /Groups/com.apple.access_screensharing-disabled >/dev/null 2>&1; then
    sudo dscl . -delete /Groups/com.apple.access_screensharing-disabled GroupMembership koolisw 2>/dev/null || true
fi

echo "Enabling Screen Sharing launch service..."

SCREENSHARING_PLIST="/System/Library/LaunchDaemons/com.apple.screensharing.plist"

if [ -f "$SCREENSHARING_PLIST" ]; then
    sudo launchctl enable system/com.apple.screensharing 2>/dev/null || true

    sudo launchctl bootstrap system "$SCREENSHARING_PLIST" 2>/dev/null || true

    sudo launchctl kickstart -k system/com.apple.screensharing 2>/dev/null || true
fi

# Configure VNC password
echo "$2" | perl -we 'BEGIN { @k = unpack "C*", pack "H*", "1734516E8BA8C5E2FF1C39567390ADCA"}; $_ = <>; chomp; s/^(.{8}).*/$1/; @p = unpack "C*", $_; foreach (@k) { printf "%02X", $_ ^ (shift @p || 0) }; print "\n"' \
  | sudo tee /Library/Preferences/com.apple.VNCSettings.txt > /dev/null

# Also configure the legacy RemoteManagement VNC password location
echo "$2" | perl -we 'BEGIN { @k = unpack "C*", pack "H*", "1734516E8BA8C5E2FF1C39567390ADCA"}; $_ = <>; chomp; s/^(.{8}).*/$1/; @p = unpack "C*", $_; foreach (@k) { printf "%02X", $_ ^ (shift @p || 0) }; print "\n"' \
  | sudo tee /Library/Preferences/com.apple.VNCSettings.txt > /dev/null

echo "Restarting Screen Sharing..."

sudo launchctl kickstart -k system/com.apple.screensharing 2>/dev/null || true

sleep 5

echo "Checking Screen Sharing service..."

sudo launchctl print system/com.apple.screensharing 2>&1 | head -40 || true

echo "Waiting for VNC server..."

VNC_READY=0

for i in {1..30}; do
    if nc -z 127.0.0.1 5900 2>/dev/null; then
        echo "Port 5900 is open."
        VNC_READY=1
        break
    fi

    sleep 2
done

if [ "$VNC_READY" -ne 1 ]; then
    echo "ERROR: VNC port 5900 never opened."
    exit 1
fi

echo "Testing actual VNC/RFB handshake..."

RFB_OK=0

for i in {1..15}; do
    RFB_REPLY="$(python3 - <<'PY'
import socket

try:
    s = socket.create_connection(("127.0.0.1", 5900), timeout=3)
    data = s.recv(12)
    s.close()
    print(data.decode("ascii", "replace"))
except Exception as e:
    print("")
PY
)"

    echo "RFB response: ${RFB_REPLY:-<none>}"

    if echo "$RFB_REPLY" | grep -q "^RFB "; then
        RFB_OK=1
        break
    fi

    sleep 2
done

if [ "$RFB_OK" -ne 1 ]; then
    echo ""
    echo "=========================================="
    echo "ERROR: Port 5900 is open, but it is NOT"
    echo "returning a valid VNC/RFB handshake."
    echo "=========================================="
    echo ""
    echo "Screen Sharing may still be blocked by macOS."
    exit 1
fi

echo "Actual VNC/RFB handshake confirmed."

# Install Bore
echo "Installing Bore..."

brew install bore-cli

# Start Bore
echo "Starting Bore tunnel..."

rm -f "$HOME/bore.log"

bore local 5900 --to bore.pub > "$HOME/bore.log" 2>&1 &

BORE_PID=$!

echo "Bore PID: $BORE_PID"

# Wait for Bore endpoint
BORE_READY=0

for i in {1..30}; do
    if grep -q "listening at" "$HOME/bore.log" 2>/dev/null; then
        BORE_READY=1
        break
    fi

    if ! kill -0 "$BORE_PID" 2>/dev/null; then
        echo "ERROR: Bore exited unexpectedly."
        cat "$HOME/bore.log"
        exit 1
    fi

    sleep 2
done

if [ "$BORE_READY" -ne 1 ]; then
    echo "ERROR: Bore did not provide an endpoint."
    cat "$HOME/bore.log"
    kill "$BORE_PID" 2>/dev/null || true
    exit 1
fi

echo ""
echo "=========================================="
echo "BORE VNC CONNECTION:"
grep "listening at" "$HOME/bore.log"
echo "=========================================="
echo ""
echo "MacOS VNC is ready."
