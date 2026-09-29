#!/bin/bash
# Plex Media Server Crack Automation Script
# Automatically applies plexmediaserver_crack for hardware transcoding without Plex Pass
# Run this script after docker-compose up or container updates

set -e

echo "🔧 Plex Media Server Crack Automation Script"
echo "=========================================="

# Check if running as root (inside container)
if [ "$EUID" -eq 0 ]; then
    echo "⚠️  Running inside container as root"
    CONTAINER_MODE=true
else
    echo "ℹ️  Running on host system"
    CONTAINER_MODE=false
fi

if [ "$CONTAINER_MODE" = false ]; then
    # Host mode - check if container is running
    echo "📦 Checking Plex container status..."
    
    if ! docker ps --format '{{.Names}}' | grep -q '^plex$'; then
        echo "❌ Plex container is not running. Start it first with: docker-compose up -d"
        exit 1
    fi
    
    echo "✅ Plex container is running"
    
    # Step 1: Create symbolic link to crack library
    echo "🔗 Creating symbolic link to crack library..."
    docker exec plex ln -sf /config/plexmediaserver_crack.so /usr/lib/plexmediaserver/lib/plexmediaserver_crack.so
    
    # Step 2: Remove any existing reference (if any)
    echo "🧹 Removing existing crack reference (if any)..."
    docker exec plex /config/patchelf --remove-needed plexmediaserver_crack.so "/usr/lib/plexmediaserver/lib/libsoci_core.so" 2>/dev/null || true
    
    # Step 3: Add crack library reference
    echo "🔧 Patching libsoci_core.so..."
    docker exec plex /config/patchelf --add-needed plexmediaserver_crack.so "/usr/lib/plexmediaserver/lib/libsoci_core.so"
    
    # Step 4: Verify the patch
    echo "✅ Verifying patch..."
    if docker exec plex /config/patchelf --print-needed "/usr/lib/plexmediaserver/lib/libsoci_core.so" | grep -q "plexmediaserver_crack.so"; then
        echo "✅ Crack library successfully added to needed libraries"
    else
        echo "❌ Failed to add crack library"
        exit 1
    fi
    
    # Step 5: Set hardware acceleration preferences
    echo "⚙️  Configuring hardware acceleration preferences..."
    
    # Backup preferences
    docker exec plex cp "/config/Library/Application Support/Plex Media Server/Preferences.xml" "/config/Library/Application Support/Plex Media Server/Preferences.xml.backup.$(date +%s)"
    
    # Update preferences
    docker exec plex sed -i 's|TranscoderHardwareAccelerated="[^"]*"|TranscoderHardwareAccelerated="1"|' "/config/Library/Application Support/Plex Media Server/Preferences.xml"
    docker exec plex sed -i 's|EnableHardwareEncoding="[^"]*"|EnableHardwareEncoding="1"|' "/config/Library/Application Support/Plex Media Server/Preferences.xml"
    
    # Add preferences if they don't exist
    if ! docker exec plex grep -q 'TranscoderHardwareAccelerated=' "/config/Library/Application Support/Plex Media Server/Preferences.xml"; then
        docker exec plex sed -i 's|/>| TranscoderHardwareAccelerated="1"/>|' "/config/Library/Application Support/Plex Media Server/Preferences.xml"
    fi
    
    if ! docker exec plex grep -q 'EnableHardwareEncoding=' "/config/Library/Application Support/Plex Media Server/Preferences.xml"; then
        docker exec plex sed -i 's|/>| EnableHardwareEncoding="1"/>|' "/config/Library/Application Support/Plex Media Server/Preferences.xml"
    fi
    
    echo "✅ Preferences updated"
    
    # Step 6: Restart Plex
    echo "🔄 Restarting Plex container..."
    cd "$(dirname "$0")" && docker-compose restart plex
    
    echo ""
    echo "🎉 Plex crack applied successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Open Plex Web UI: http://localhost:32400/web"
    echo "2. Go to Settings → Server → Transcoder"
    echo "3. Enable 'Show Advanced' (top-right corner)"
    echo "4. Verify 'Use hardware acceleration when available' is checked"
    echo "5. Save changes"
    echo ""
    echo "To verify hardware acceleration is working:"
    echo "1. Play a video that requires transcoding"
    echo "2. Go to Activity → Dashboard"
    echo "3. Expand playback details"
    echo "4. Look for '(hw)' next to video transcode"
    
else
    # Container mode - run inside container
    echo "📦 Running inside Plex container..."
    
    # Check if required files exist
    if [ ! -f "/config/plexmediaserver_crack.so" ]; then
        echo "❌ Crack library not found at /config/plexmediaserver_crack.so"
        exit 1
    fi
    
    if [ ! -f "/config/patchelf" ]; then
        echo "❌ patchelf not found at /config/patchelf"
        exit 1
    fi
    
    # Apply crack
    echo "🔧 Applying crack..."
    ln -sf /config/plexmediaserver_crack.so /usr/lib/plexmediaserver/lib/plexmediaserver_crack.so
    /config/patchelf --remove-needed plexmediaserver_crack.so "/usr/lib/plexmediaserver/lib/libsoci_core.so" 2>/dev/null || true
    /config/patchelf --add-needed plexmediaserver_crack.so "/usr/lib/plexmediaserver/lib/libsoci_core.so"
    
    echo "✅ Crack applied inside container"
fi

echo ""
echo "📝 For detailed documentation, see: PLEX_CRACK_SETUP.md"