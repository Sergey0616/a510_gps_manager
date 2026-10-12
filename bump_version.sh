#!/data/data/com.termux/files/usr/bin/bash
set -e
FILE="pubspec.yaml"
CURRENT=$(grep '^version:' "$FILE" | awk '{print $2}')
NAME=$(echo "$CURRENT" | cut -d+ -f1)
CODE=$(echo "$CURRENT" | cut -d+ -f2)
NEW="${NAME}+$((CODE + 1))"
sed -i "s/^version: .*/version: ${NEW}/" "$FILE"
echo "Version: $CURRENT → $NEW"
