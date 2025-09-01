#!/bin/bash
# Fix ownership of video files

echo "Fixing video file ownership..."

# Change ownership of all video files to your user
chown abelur:abelur ./videos/*.mp4 2>/dev/null || true

# Set proper permissions
chmod 644 ./videos/*.mp4 2>/dev/null || true

echo "✅ Video file ownership fixed"
