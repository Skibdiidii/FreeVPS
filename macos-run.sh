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

echo "Configuring Remote Management..."

sudo defaults write /Library/Preferences/com.apple.RemoteManagement \
    ARD_AllLocalUsers -bool true

sudo defaults write /Library/Preferences/com.apple.RemoteManagement \
    ARD_AllLocalUsersPrivs -int 1073742079

# Screen Sharing access
if dscl . -read /Groups/com.apple.access_screensharing >/dev/null 2>&1; then
    sudo dscl . -append /Groups/com.apple.access_screensharing \
        GroupMembership koolisw 2>/dev/null || true
fi

if dscl . -read /Groups/com.apple.access_screensharing-disabled >/dev/null 2>&1; then
    sudo dscl . -delete /Groups/com.apple.access_screensharing-disabled \
        GroupMembership koolisw 2>/dev/null || true
fi

# Enable Screen Sharing launch service
SCREENSHARING_PLIST="/System/Library/LaunchDaemons/com.apple.screensharing.plist"

if [ -f "$SCREENSHARING_PLIST" ]; then
    sudo launchctl enable system/com.apple.screensharing 2>/dev/null || true
    sudo launchctl bootstrap system "$SCREENSHARING_PLIST" 2>/dev/null || true
    sudo launchctl kickstart -k system/com.apple.screensharing 2>/dev/null || true
fi

# Configure VNC password
echo "$2" | perl -we '
BEGIN {
    @k = unpack "C*", pack "H*", "1734516E8BA8C5E2FF1C39567390ADCA"
}
$_ = <>;
chomp;
s/^(.{8}).*/$1/;
@p = unpack "C*", $_;
foreach (@k) {
    printf "%02X", $_ ^ (shift @p || 0)
}
print "\n"
' | sudo tee /Library/Preferences/com.apple.VNCSettings.txt > /dev/null

# Restart Screen Sharing
sudo launchctl kickstart -k system/com.apple.screensharing 2>/dev/null || true

sleep 5

echo "Checking Screen Sharing..."

sudo launchctl print system/com.apple.screensharing 2>&1 | head -30 || true

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
except Exception:
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
    echo "ERROR: Port 5900 is open, but VNC did not"
    echo "return a valid RFB handshake."
    echo "=========================================="
    exit 1
fi

echo ""
echo "=========================================="
echo "ACTUAL VNC/RFB HANDSHAKE CONFIRMED"
echo "=========================================="
echo ""
echo "MacOS VNC is ready."
