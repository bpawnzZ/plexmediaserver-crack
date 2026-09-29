#!/bin/bash

echo "=== Plex Entrypoint Script ==="
echo "Current directory: $(pwd)"

# Expose NVIDIA driver libs to Plex's transcoder library dir.
# The `nvidia` runtime injects the driver libs into /lib, but Plex's transcoder
# (Plex Transcoder) looks for them via its own rpath at /usr/lib/plexmediaserver/lib.
# Without these, NVENC fails with "Cannot load libcuda.so.1" and Plex falls back
# to CPU (software) transcoding. Copy the live injected versions each boot so the
# driver-lib version always matches whatever runtime is active.
echo "=== Linking NVIDIA driver libs into Plex transcoder lib dir ==="
for L in libcuda.so.1 libnvidia-encode.so.1 libnvcuvid.so.1 libnvidia-ptxjitcompiler.so.1 libnvidia-ml.so.1; do
    if [ -e "/lib/$L" ] && [ ! -e "/usr/lib/plexmediaserver/lib/$L" ]; then
        cp -p "/lib/$L" "/usr/lib/plexmediaserver/lib/$L" 2>/dev/null && echo "Linked $L"
    fi
done

# Function to run crack script
run_crack_script() {
    echo "=== Running Plex Crack Script ==="
    
    # Check if crack script exists (mounted from current directory)
    if [ -f "/host-docker/crack_plex.sh" ]; then
        echo "Found crack_plex.sh at /host-docker/crack_plex.sh"
        echo "Executing crack script..."
        # Skip chmod since it's read-only mount
        cd "/host-docker" && ./crack_plex.sh
    else
        echo "ERROR: crack_plex.sh not found at /host-docker/crack_plex.sh"
        echo "Looking in current directory: $(pwd)"
        ls -la /host-docker/ 2>/dev/null || echo "Cannot list /host-docker"
    fi
}

# Main execution
run_crack_script

echo "Starting Plex Media Server..."
exec /init