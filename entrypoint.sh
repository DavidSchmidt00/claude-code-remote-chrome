#!/bin/bash
set -e

if [ -n "$CLAUDE_CREDENTIALS" ]; then
    mkdir -p ~/.claude
    echo "$CLAUDE_CREDENTIALS" > ~/.claude/.credentials.json
fi

# Install fake chrome-native-host that bridges to host via TCP
mkdir -p ~/.claude/chrome
cat > ~/.claude/chrome/chrome-native-host << 'EOF'
#!/bin/bash
exec node /home/claude/chrome-native-host.js
EOF
chmod +x ~/.claude/chrome/chrome-native-host

exec "$@"
