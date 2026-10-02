#!/usr/bin/env bash
# Regression check for the container branch of scripts/crack_plex.sh.
#
# The container branch must NOT report success unless the patch is verified by
# reading DT_NEEDED back. patchelf can exit 0 while leaving the library list
# unchanged, and reporting success in that case is the failure this guards.
#
# Usage: scripts/tests/test-crack-verify.sh   (run from the repo root)
# Requires: docker. No host dependencies.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
IMG="${IMG:-debian:bookworm-slim}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A stand-in patchelf whose --add-needed behaviour is selected by $MODE.
cat > "$TMP/patchelf" <<'EOF'
#!/bin/sh
NEEDED=/tmp/needed.txt
case "$1" in
  --remove-needed) exit 0 ;;
  --add-needed)
    case "${MODE:-works}" in
      works)       echo "$2" >> "$NEEDED"; exit 0 ;;
      silent-noop) exit 0 ;;
      hard-fail)   exit 1 ;;
    esac ;;
  --print-needed) cat "$NEEDED" ;;
esac
EOF

run() { # $1 = MODE -> prints "VERDICT EXITCODE"
  docker run --rm -e MODE="$1" --user 0:0 \
    -v "$TMP/patchelf:/src-patchelf:ro" \
    -v "$REPO/scripts/crack_plex.sh:/src-crack:ro" \
    "$IMG" /bin/bash -c '
      mkdir -p /config "/usr/lib/plexmediaserver/lib"
      touch /config/plexmediaserver_crack.so
      cp /src-patchelf /config/patchelf && chmod +x /config/patchelf
      printf "libc.so.6\n" > /tmp/needed.txt
      out=$(bash /src-crack 2>&1); rc=$?
      if   echo "$out" | grep -q "Crack applied inside container"; then v=SUCCESS
      elif echo "$out" | grep -q "Failed to add crack library";     then v=VERIFY-FAIL
      else v=ABORTED; fi
      echo "$v $rc"
    ' 2>/dev/null
}

fail=0
check() { # $1 mode, $2 expected verdict, $3 expected exit
  read -r verdict rc <<<"$(run "$1")"
  if [ "$verdict" = "$2" ] && [ "$rc" = "$3" ]; then
    echo "  PASS  $1 -> $verdict (exit $rc)"
  else
    echo "  FAIL  $1 -> got '$verdict' exit '$rc', want '$2' exit '$3'"
    fail=1
  fi
}

# The distinction that matters: success only when the patch is read back.
#   works       -> success, our verify block confirms DT_NEEDED
#   silent-noop -> catches the case patchelf exits 0 leaving DT_NEEDED alone
#   hard-fail   -> `set -e` aborts on the patchelf call itself, before verify.
#                  Non-zero either way; ABORTED is correct here, not a defect.
echo "container-branch verification"
check works       SUCCESS     0
check silent-noop VERIFY-FAIL 1
check hard-fail   ABORTED     1

[ "$fail" -eq 0 ] && echo "ok" || echo "FAILED"
exit "$fail"
