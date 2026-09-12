#!/bin/bash
# macos-run.sh MAC_USER_PASSWORD VNC_PASSWORD MAC_REALNAME

# Disable Spotlight indexing
sudo mdutil -i off -a

# Create user
sudo dscl . -create /Users/koolisw
sudo dscl . -create /Users/koolisw UserShell /bin/bash
sudo dscl . -create /Users/koolisw RealName "$3"
sudo dscl . -create /Users/koolisw UniqueID 1001
sudo dscl . -create /Users/koolisw PrimaryGroupID 80
sudo dscl . -create /Users/koolisw NFSHomeDirectory /Users/koolisw
sudo dscl . -passwd /Users/koolisw "$1"
sudo createhomedir -c -u koolisw > /dev/null

# Add user to admin group
sudo dscl . -append /Groups/admin GroupMembership koolisw

# Enable VNC
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -configure -allowAccessFor -allUsers -privs -all

sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -configure -clientopts -setvnclegacy -vnclegacy yes

# Set VNC password
echo "$2" | perl -we 'BEGIN { @k = unpack "C*", pack "H*", "1734516E8BA8C5E2FF1C39567390ADCA"}; $_ = <>; chomp; s/^(.{8}).*/$1/; @p = unpack "C*", $_; foreach (@k) { printf "%02X", $_ ^ (shift @p || 0) }; print "\n"' \
  | sudo tee /Library/Preferences/com.apple.VNCSettings.txt > /dev/null

# Restart VNC
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -restart -agent -console

sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -activate

# Install Bore
brew install bore-cli

# Wait for VNC
echo "Waiting for VNC server..."

for i in {1..30}; do
    if nc -z 127.0.0.1 5900 2>/dev/null; then
        echo "VNC is listening on port 5900."
        break
    fi

    sleep 2
done

# Start Bore
echo "Starting Bore tunnel..."

bore local 5900 --to bore.pub > "$HOME/bore.log" 2>&1 &

BORE_PID=$!

# Wait for Bore endpoint
for i in {1..30}; do
    if grep -q "listening at" "$HOME/bore.log" 2>/dev/null; then
        echo ""
        echo "=============================="
        echo "BORE VNC CONNECTION:"
        grep "listening at" "$HOME/bore.log"
        echo "=============================="
        echo ""
        break
    fi

    if ! kill -0 "$BORE_PID" 2>/dev/null; then
        echo "Bore exited unexpectedly:"
        cat "$HOME/bore.log"
        exit 1
    fi

    sleep 2
done

echo "MacOS VNC is ready."
