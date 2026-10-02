#!/bin/bash
# A/B transcode + strace of the server process for nvidia library access
TOK30=$(sudo grep -oP 'PlexOnlineToken="\K[^"]+' "$HOME/docker/plex-crypt/plex/Library/Application Support/Plex Media Server/Preferences.xml")
TOK34=$(sudo grep -oP 'PlexOnlineToken="\K[^"]+' "$HOME/docker/plex-test2/plex/Library/Application Support/Plex Media Server/Preferences.xml")

run() { # name port pid token
  local NAME=$1 PORT=$2 PID=$3 TOK=$4
  echo "########## $NAME (port $PORT, host pid $PID)"
  local OUT=$HOME/.hermes/cache/scratch/strace-$NAME.log
  sudo strace -f -p $PID -e trace=openat,open,mmap -o "$OUT" -qq 2>/dev/null &
  local SPID=$!
  sleep 2
  local SID="abtest-$NAME-$(date +%s)"
  curl -s -G "http://127.0.0.1:$PORT/video/:/transcode/universal/start.m3u8" \
    -H "X-Plex-Token: $TOK" -H "X-Plex-Client-Identifier: $SID" \
    -H "X-Plex-Platform: Chrome" -H "X-Plex-Product: Plex Web" \
    --data-urlencode "path=/library/metadata/9524" \
    --data-urlencode "mediaIndex=0" --data-urlencode "partIndex=0" \
    --data-urlencode "protocol=hls" --data-urlencode "directPlay=0" \
    --data-urlencode "directStream=0" --data-urlencode "maxVideoBitrate=20000" \
    --data-urlencode "videoResolution=1920x1080" --data-urlencode "hasMDE=1" \
    --data-urlencode "session=$SID" -o /dev/null -w "  start http=%{http_code}\n"
  sleep 12
  sudo kill $SPID 2>/dev/null; wait $SPID 2>/dev/null
  echo "  strace lines: $(wc -l < $OUT 2>/dev/null || echo 0)"
  echo "  nvidia-related openat/mmap:"
  grep -iE "nvidia|cuda|nvenc|nvml|cuvid" "$OUT" 2>/dev/null | sort -u | head -30
  echo
}
PY=$(pgrep -f "usr/lib/plexmediaserver/Plex Media Server" | head -1)
# map pids by cgroup
for p in $(pgrep -f "Plex Media Server"); do
  cg=$(cat /proc/$p/cgroup 2>/dev/null | head -1)
  case "$cg" in
    *19c96179283ea0*) P30=$p;;
    *6a404ce315c5ff*) P34=$p;;
  esac
done
echo "plex(1.43.0) host pid=$P30   plex-test2(1.43.4) host pid=$P34"
run "prod-1430" 32400 "$P30" "$TOK30"
run "test-1434" 32403 "$P34" "$TOK34"
