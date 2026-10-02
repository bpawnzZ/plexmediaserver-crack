# 🎬 plexmediaserver_crack (updated fork)

> *Plex Pass features without the Plex Pass bill.*

![target: Plex 1.43.0](https://img.shields.io/badge/Plex-1.43.0_✅-brightgreen)
![broken: 1.43.4](https://img.shields.io/badge/Plex-1.43.4_❌-red)
![build: musl](https://img.shields.io/badge/build-musl_(Alpine)-blue)
![license: MIT](https://img.shields.io/badge/license-MIT-lightgrey)

A maintained fork of [`yuv420p10le/plexmediaserver_crack`](https://gitgud.io/yuv420p10le/plexmediaserver_crack),
with setup instructions, build tooling, and notes from trying to crack the newer
Plex builds.

**This fork depends on upstream.** It does not vendor the crack and it is not a
replacement for it: the working library is built and published *there*, and the
whole of [step 1](#-1-put-two-files-in-the-plex-config-directory) is fetching it.
What this repo adds is the part upstream does not cover — a pinned, boot-time
Docker deployment that survives container recreation, and the
[1.43.4 investigation](#-cracking-the-newer-builds). See
[Relationship to upstream](#-relationship-to-upstream).

The crack is a preload library (`plexmediaserver_crack.so`) patched into Plex
Media Server's `libsoci_core.so` so that Plex's feature-entitlement check always
returns `true` — enabling Plex Pass features (hardware transcoding, etc.) on a
server whose account does not have a Plex Pass.

[**📊 Compatibility matrix**](COMPATIBILITY.md) · [**🤝 Contributing**](CONTRIBUTING.md) · [**💬 Discussions**](https://github.com/bpawnzZ/plexmediaserver-crack/discussions) · [**🐛 Report a setup**](https://github.com/bpawnzZ/plexmediaserver-crack/issues/new?template=hardware-report.yml)

> [!WARNING]
> **Read the pin below before you start.** This crack works on **Plex 1.43.0**.
> It does **not** work on 1.43.4 — see
> [Cracking the newer builds](#-cracking-the-newer-builds) for what was tried and
> where it stands. If you are on 1.43.4 and hardware transcoding matters to you,
> **pin to 1.43.0**.

**Contents:** [Agent prompt](#-hand-this-to-your-agent) · [The pin](#-the-pin-read-first) · [Quick start](#-quick-start) · [Remote access](#-remote-access-without-a-plex-pass) · [Building](#-building-the-library) · [How it works](#-how-the-crack-works) · [Newer builds](#-cracking-the-newer-builds) · [Gotchas](#-gotchas) · [Upstream](#-relationship-to-upstream) · [Contributing](https://github.com/bpawnzZ/plexmediaserver-crack#-get-involved)

## 🤖 Hand this to your agent

Paste the block below into your coding agent (Claude Code, Codex, Cursor, …).
The prompt is self-contained: it carries the pinned version, the gotchas that
silently produce an unpatched server, and a definition of done. Fill in the three
paths first.

Working **on this repo** rather than setting it up? Point your agent at
[`AGENTS.md`](AGENTS.md) instead — it has the build and verify commands, the
constraints, and the list of dead ends not to re-investigate.

<details>
<summary><strong>Show the agent prompt</strong></summary>

````text
Set up plexmediaserver_crack for my Plex Media Server in Docker.

MY CONTEXT
- Compose file / deploy dir: <absolute path, e.g. /home/me/docker/plex-crypt>
- Media libraries: <absolute path(s) to bind-mount, e.g. /mnt/media>
- Crack source: this repo, at <absolute path to this repo>

If any of the above is unknown, ASK ME. Do not guess a path.

BEFORE YOU START — confirm these exist, and stop and tell me if one is missing
- Docker with `docker compose`
- An NVIDIA GPU with its driver, and the NVIDIA container runtime (`runtime: nvidia`)
- `patchelf` available on the host (you will copy it into the Plex config dir)

HARD CONSTRAINTS — do not deviate
- Pin Plex to 1.43.0.10492-121068a07-ls297. Do NOT use `latest` and do NOT bump
  the tag: 1.43.4 breaks NVIDIA hardware transcoding independently of the crack.
- `VERSION=` must equal the pinned version string. Never `VERSION=docker` — that
  self-updates Plex on boot and silently walks past the pinned tag.
- The crack library is built against musl. A glibc build will not load into
  Plex's musl process. Verify with `readelf -d` before shipping it.
- `runtime: nvidia` is required (not `deploy.resources`), so /dev/dri/renderD128
  is exposed. Without it NVENC fails.
- This repo does not contain the crack. It depends on upstream at
  gitgud.io/yuv420p10le/plexmediaserver_crack, which is the only place the
  prebuilt library is published. Fetch it with exactly this URL:
    curl -L -o plex/plexmediaserver_crack.so \
      https://gitgud.io/yuv420p10le/plexmediaserver_crack/-/raw/master/binaries/plexmediaserver_crack.so
  Its md5 must be 4d5dc96c8c7da383d84880b922935cd6 (9,972,072 bytes). If the hash
  differs, stop and tell me — do not proceed. Note the path is `master`, not `main`.
- Do NOT fetch the binary from GitHub. The gmh5225 mirror there is source-only with
  dead links, and github.com/yuv420p10le/... does not exist (404). gitgud only.
- Do NOT build this repo's source as a substitute. It produces a ~2 MB
  single-function variant that does NOT reproduce the working 9.9 MB Zydis-based
  deployment — different libraries (see the repo README, "There are two different
  cracks"). If the download fails, tell me rather than building something else.
- Upstream's web UI returns 403 to anonymous requests. That is a bot-wall, not a
  dead project — the GitLab API returns 200 and git works. Do not conclude the
  library is unobtainable, and do not go looking for a mirror.

If you hit a blocker, ASK. Do not improvise around a constraint above — bumping
the pinned version, disabling verification, or substituting a different library
are all worse than stopping.

WHAT TO DO
1. Read the README's Quick start (steps 1-5), and re-read "The pin (read first)".
   Consult docs/FINDINGS.md only if verification fails — it is the 1.43.4
   investigation log, and is not required to stand a working setup up.
2. Lay out the config dir: `plexmediaserver_crack.so` + `patchelf` inside it.
3. Copy `examples/plex-entrypoint.sh` and `scripts/crack_plex.sh` next to my
   compose file; chmod +x both.
4. Write/update my compose file with: the pinned image, `runtime: nvidia`,
   `entrypoint: /plex-entrypoint.sh`, `.:/host-docker:ro`, and `./plex:/config`.
   Preserve my existing volume mounts and PUID/PGID/TZ; only add what is missing.
5. `docker compose up -d` and read `docker compose logs plex`. Confirm the log
   shows the driver libs linked AND "✅ Crack applied inside container".
6. Verify for real: trigger a transcode, then read Plex's decision from its log.
   Do NOT test by running `Plex Transcoder` directly — it succeeds even on broken
   builds and gives a false positive.

DEFINITION OF DONE — all four, with the raw output pasted back to me
a. `docker exec plex /config/patchelf --print-needed \
      /usr/lib/plexmediaserver/lib/libsoci_core.so` lists plexmediaserver_crack.so
b. Plex reports the GPU as its transcoding device. This needs no media, so run it
   first. Expect `value="10de...` (NVIDIA vendor id; the colons appear as %3a):
     docker exec plex sh -c 'T=$(grep -oP "PlexOnlineToken=\"\K[^\"]+" \
       "/config/Library/Application Support/Plex Media Server/Preferences.xml"); \
       curl -s "http://127.0.0.1:32400/:/prefs?X-Plex-Token=$T"' \
       | grep -o '<Setting id="HardwareDevicePath"[^/]*/>'
   An empty value= means the crack is not working — stop and tell me before going
   further. Do not substitute a direct `Plex Transcoder` run; it always reports
   nvenc and is a known false positive.
c. Plex Media Server log shows `Used slots for 10de:<pci-id> ... is now 1`
   (GPU slot, not `Used slots for CPU`)
d. Plex Media Server log shows `encoder=h264_nvenc` (not `encoder=libx264`)

REPORTING
- A running container is NOT proof the crack applied. If any check in (a)-(d)
  fails, say so explicitly and paste the failing output — do not report success.
- Tell me every file you created or changed, and the exact commands you ran.
- If the crack silently no-ops, re-run with `PLEXCRACK_DEBUG=1` and report what
  `[crack] is_feature_available = ...` printed. If it is 0, the signature scan
  missed and the hook was not applied.
````

</details>

---

---

## 📌 The pin (read first)

Two settings must both hold, or the version you tested is **not** the version you
run. This is the single most common way to end up with a server that looks
patched but is not:

| Setting | Value | Why |
|---|---|---|
| `image:` | `linuxserver/plex:1.43.0.10492-121068a07-ls297` | 1.43.4 breaks NVIDIA hardware transcoding independently of the crack |
| `VERSION=` | `1.43.0.10492-121068a07` | `VERSION=docker` makes Plex **self-update on boot**, silently walking past your pinned tag |

Never use `latest`. Never set `VERSION=docker`.

**These hold for anything you deploy.** The compose block in
[step 3](#-3-add-it-to-docker-compose) already has both set correctly — if you
copy it, you are pinned.

---

## 🚀 Quick start

Five steps. Each one leads with the command; the reasoning follows.

```mermaid
flowchart LR
    A["1 · Drop .so<br/>+ patchelf"] --> B["2 · Entrypoint<br/>+ crack script"]
    B --> C["3 · Compose<br/>+ runtime: nvidia"]
    C --> D["4 · Boot<br/>+ read log"]
    D --> E["5 · Verify<br/>h264_nvenc"]
    E --> F(["🧠 GPU<br/>encoding"])
    style A fill:#1f6feb,color:#fff
    style B fill:#1f6feb,color:#fff
    style C fill:#1f6feb,color:#fff
    style D fill:#1f6feb,color:#fff
    style E fill:#1f6feb,color:#fff
    style F fill:#238636,color:#fff
```

### 📦 1. Put two files in the Plex config directory

You need `plexmediaserver_crack.so` (the crack library) and `patchelf` (which
links it in at boot), both in the directory you mount at `/config`. When you are
done it should look like this:

```
plex/                              # your Plex config dir, mounted at /config
├── plexmediaserver_crack.so
├── patchelf
└── Library/ ...                   # normal Plex config, untouched
```

**Get the crack library.** Pull the working build straight from upstream — this is
the Zydis-based library that actually works on 1.43.0, not the smaller variant this
repo's source builds:

```sh
curl -L -o plex/plexmediaserver_crack.so \
  https://gitgud.io/yuv420p10le/plexmediaserver_crack/-/raw/master/binaries/plexmediaserver_crack.so
md5sum plex/plexmediaserver_crack.so
# expect: 4d5dc96c8c7da383d84880b922935cd6  (9,972,072 bytes)
```

Check that hash. It is the difference between a working server and one that boots
fine and silently gives you nothing.

**Get `patchelf`** from your distro — it is a package, not something to build:

```sh
cp "$(command -v patchelf)" plex/
# Debian/Ubuntu: apt install patchelf    Arch: pacman -S patchelf
```

**Or bring your own** — if you already have a known-good `.so`, drop it in and hash
it so you know what you are running. Just do not substitute a build of this repo's
source and expect parity; see
[There are two different cracks](#there-are-two-different-cracks). Building the
repo's own smaller variant is documented in
[Building the library](#-building-the-library), but it is not a shortcut to a
working setup.

> **Both files are required.** `crack_plex.sh` looks for them at
> `/config/plexmediaserver_crack.so` and `/config/patchelf`. A missing `.so` or a
> missing `patchelf` is a documented failure mode in step 4.

### 🪝 2. Copy the entrypoint and crack script next to your compose file

```sh
cp examples/plex-entrypoint.sh .
cp scripts/crack_plex.sh .
chmod +x plex-entrypoint.sh
```

Both files must sit beside your compose file, because the compose block in the
next step mounts the whole directory into the container at `/host-docker`.

> **What the entrypoint does, in order:** it copies the NVIDIA driver libraries
> from `/lib` into `/usr/lib/plexmediaserver/lib/`, where `Plex Transcoder`
> actually looks for them (it uses its own `rpath`, not the system linker path) —
> without this, NVENC fails with `Cannot load libcuda.so.1` and Plex silently
> falls back to software transcoding. It then runs `crack_plex.sh`, which
> symlinks the `.so` next to `libsoci_core.so`, prepends it to that library's
> `DT_NEEDED` list, backs up `Preferences.xml`, forces
> `TranscoderHardwareAccelerated="1"` and `EnableHardwareEncoding="1"` into it,
> and verifies the patch by reading `DT_NEEDED` back. Finally it `exec`s `/init`
> to start Plex. The `Preferences.xml` backup is written next to the original
> with a timestamp suffix.

### 🧩 3. Add it to docker-compose

Start from [`examples/docker-compose.yml`](examples/docker-compose.yml). Three
things matter: the `nvidia` runtime, the entrypoint, and the mounts the
entrypoint needs.

```yaml
services:
  plex:
    image: linuxserver/plex:1.43.0.10492-121068a07-ls297   # see the pin
    container_name: plex
    restart: unless-stopped
    network_mode: host

    runtime: nvidia                                       # exposes /dev/nvidia*, renderD128

    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC
      - NVIDIA_VISIBLE_DEVICES=all
      - NVIDIA_DRIVER_CAPABILITIES=all
      - VERSION=1.43.0.10492-121068a07                      # see the pin
      # - PLEXCRACK_DEBUG=1                               # uncomment to log the sig scan

    volumes:
      - /path/to/media:/media
      - ./plex:/config                                  # holds the .so + patchelf
      - ./transcodes:/transcode
      - /etc/localtime:/etc/localtime:ro
      - ./plex-entrypoint.sh:/plex-entrypoint.sh:ro     # the entrypoint
      - .:/host-docker:ro                               # so crack_plex.sh is reachable

    entrypoint: /plex-entrypoint.sh
```

Two details that are easy to get wrong:

- **The `.so` and `patchelf` must be inside the mounted config dir** (`./plex`),
  because that is where `crack_plex.sh` expects to find them.
- **`.:/host-docker:ro` must be mounted**, because the entrypoint runs
  `/host-docker/crack_plex.sh`. If that mount is missing, the entrypoint logs
  `ERROR: crack_plex.sh not found` and starts Plex without the crack.

> **Preserve your existing config.** If you already run Plex, keep your current
> volume mounts, `PUID`/`PGID` and `TZ`, and only add what is missing above. The
> `runtime: nvidia` line is required rather than `deploy.resources`, because only
> the runtime form exposes `/dev/dri/renderD128`.

### 🔥 4. Start it and check the log

```sh
docker compose up -d
docker compose logs -f plex
```

**A good boot** copies the driver libraries:

```
=== Linking NVIDIA driver libs into Plex transcoder lib dir ===
Linked libcuda.so.1
Linked libnvidia-encode.so.1
Linked libnvcuvid.so.1
```

then runs the crack and reports success:

```
=== Running Plex Crack Script ===
Found crack_plex.sh at /host-docker/crack_plex.sh
Executing crack script...
🔧 Plex Media Server Crack Automation Script
==========================================
⚠️  Running inside container as root
📦 Running inside Plex container...
🔧 Applying crack...
✅ Verifying patch...
✅ Crack applied inside container
```

The `Verifying patch` step reads `DT_NEEDED` back before claiming success — the
script will not print the success line unless the library is actually listed.

**Failure modes:**

| Log line | Meaning |
|---|---|
| `ERROR: crack_plex.sh not found` | the `.:/host-docker:ro` mount is missing |
| `❌ Crack library not found at /config/plexmediaserver_crack.so` | step 1 not done |
| `❌ patchelf not found at /config/patchelf` | step 1, `patchelf` half not done |
| `❌ Failed to add crack library` | patchelf ran but `DT_NEEDED` was not updated — the patch did not take |
| *(nothing at all about the crack)* | the `entrypoint:` is not set, so it never ran |

> **None of these stop Plex from starting.** The entrypoint does not check the
> script's exit status, so a failed crack still ends in a running, **unpatched**
> server. The script itself no longer claims success unless it verified the
> patch, but the container comes up either way. Always confirm with step 5, not
> just by seeing the container up.

**If the crack did not apply, there is usually no error at all** — the library
fails its signature scan silently and Plex runs unpatched. Turn on debug logging
to see why:

```sh
PLEXCRACK_DEBUG=1 docker compose up -d && docker compose logs plex | grep '\[crack\]'
```

```
[crack] .text = 0x... - 0x...
[crack] is_feature_available = 0x...
```

`is_feature_available = 0` means the signature did not match (or matched more
than once) and the hook was **not** applied.

### ✅ 5. Confirm hardware transcoding actually works

**Do not test by running `Plex Transcoder` directly.** A direct invocation

```sh
Plex Transcoder -hwaccel nvdec -i in.mp4 -c:v h264_nvenc -f null -
```

**succeeds on every version**, including ones where hardware transcoding is
broken end-to-end. It bypasses Plex Media Server's transcode-decision engine,
which is where things actually fail. This produces a false positive.

**The valid test** is to let Plex Media Server pick the encoder itself, then read
its decision. Start any transcode (play something from a browser at a quality
below the source), then:

```sh
docker exec plex grep -E "Used slots for|encoder=" \
  "/config/Library/Application Support/Plex Media Server/Logs/Plex Media Server.log" | tail -3
```

| What you see | Meaning |
|---|---|
| `Used slots for 10de:<pci-id> …is now 1` | GPU slot registered — hardware path ✅ |
| `Used slots for CPU is now 1` | software slot — hardware path **not** taken ❌ |
| `encoder=h264_nvenc` | hardware encode selected ✅ |
| `encoder=libx264` | software encode selected ❌ |

**Working looks like this:**

```
Used slots for 10de:1be1:1043:13f0@0000:01:00.0is now 1
Reached Decision ... encoder=h264_nvenc ...
```

To force a session without a client, use the server's own token
(`PlexOnlineToken` in `Preferences.xml`):

```sh
TOKEN=$(docker exec plex grep -oP 'PlexOnlineToken="\K[^"]+' \
  "/config/Library/Application Support/Plex Media Server/Preferences.xml")

docker exec plex curl -s -o /dev/null -H "X-Plex-Token: $TOKEN" \
  "http://127.0.0.1:32400/video/:/transcode/universal/start.m3u8?path=%2Flibrary%2Fmetadata%2F<ratingKey>&mediaIndex=0&partIndex=0&protocol=hls&directPlay=0&directStream=1&videoResolution=1280x720&maxVideoBitrate=4000&session=test&X-Plex-Platform=Chrome&X-Plex-Client-Identifier=test"
```

Replace `<ratingKey>` with any item id from `/library/sections/<n>/all`, wait a
few seconds, then run the grep above.

---

### 🖥️ 6. Confirm Plex sees the GPU

Step 5 needs something to play. This check does not — and it is the one that
populates the **Settings → Transcoder → Hardware transcoding device** dropdown. If
the dropdown shows your GPU, the crack took.

```sh
docker exec plex sh -c 'T=$(grep -oP "PlexOnlineToken=\"\K[^\"]+" \
  "/config/Library/Application Support/Plex Media Server/Preferences.xml"); \
  curl -s "http://127.0.0.1:32400/:/prefs?X-Plex-Token=$T"' \
  | grep -o "<Setting id=\"HardwareDevicePath\"[^/]*/>"
```

Unlike a plain `grep` for the attribute, this reads the whole `<Setting …>` element,
which is where the useful part lives. On a working setup you get:

```
<Setting id="HardwareDevicePath" label="Hardware transcoding device" …
  default="" value="10de%3a1be1%3a1043%3a13f0@0000%3a01%3a00.0"
  … enumValues=":Auto|10de%3a…:NVIDIA GP104BM [GeForce GTX 1070 Mobile]" />
```

| What you see | Meaning |
|---|---|
| `value="10de…"` plus a real GPU name in `enumValues` | Plex enumerated the GPU and selected it ✅ |
| `value=""` and `enumValues=":Auto"` only | no device found — crack not working, or GPU not exposed ❌ |

Three things worth reading out of that line:

- **`10de`** is NVIDIA's PCI vendor id, so the prefix confirms the card was found.
  AMD would be `1002`, Intel `8086`.
- **`%3a` is URL-encoded `:`** — the value is a URL, not a typo.
- The device string is the **same one** that appears in the step 5 log line
  (`Used slots for 10de:1be1:1043:13f0@0000:01:00.0`), so you can cross-check the
  two. If Plex's `value` and its transcode log name different devices, look again.

The friendly name in `enumValues` is the same string the **Settings → Transcoder**
dropdown shows, so if you would rather just look, open Plex and check the
"Hardware transcoding device" list.

Also confirm the flags are on — they default on, but a carried-over
`Preferences.xml` can have them off:

```sh
docker exec plex sh -c 'T=$(grep -oP "PlexOnlineToken=\"\K[^\"]+" \
  "/config/Library/Application Support/Plex Media Server/Preferences.xml"); \
  curl -s "http://127.0.0.1:32400/:/prefs?X-Plex-Token=$T"' \
  | grep -oE '<Setting id="HardwareAccelerated(Codecs|Encoders)"[^/]*value="[^"]*"'
# want value="1" on both
```

> This proves the *device was selected*, not that a transcode used it. Step 5
> remains the only proof of the latter — this is a fast pre-check when you have
> nothing to play.

## 🌍 Remote access without a Plex Pass

Plex's own remote access needs a Plex Pass (or the rate-limited relay). Put the
server and your clients on a private VPN mesh and reach it at its mesh IP —
**no port forward, nothing exposed to the internet.**

This works well *because* of the crack, not in spite of it: hardware encoding
keeps the stream small. A 1080p NVENC stream is roughly 4–8 Mbit/s, which any VPN
tunnel carries comfortably — where direct-playing a 40 Mbit/s remux would not.
That headroom is the difference between one remote stream and several.

> [!IMPORTANT]
> **ZeroTier and WireGuard are *not* equivalent, and the reason took a while to
> find.** The symptom was that Plex would not load at all over WireGuard and
> sometimes demanded a Plex Pass, while ZeroTier worked fine. The cause is
> **not** Plex classification, **not** DNS, and **not** MTU — it is a **missing
> `PersistentKeepalive` on the NAT'd peer**, which silently kills the *inbound*
> direction to that host. See
> [The one that actually bit us](#the-one-that-actually-bit-us-persistentkeepalive).
> The explanations this file gave earlier — "Plex classifies WireGuard clients as
> remote", "the DNS layer is what makes it work", and an MTU mismatch — are kept
> below only because they were **disproven or shown to be non-causal**, and are
> worth knowing not to chase again.

### Pick your mesh: ZeroTier or WireGuard

| | ZeroTier / Tailscale | Plain WireGuard |
|---|---|---|
| Reach the server at its mesh IP | ✅ | ✅ |
| Server classifies the client as local | ✅ | ✅ *(verified in the server log)* |
| Remote playback without a Pass | ✅ | ✅ *(was the symptom of the broken path — confirm on your own setup)* |
| Setup effort | join network, authorise | configure hub + per-client keys, **and keepalive on every NAT'd peer** |

The mesh only decides how packets reach the server. It does not decide whether
the server calls you local — but it does appear to influence what the **client
app** concludes about the connection, and that is where the WireGuard case
currently fails. Do not assume the mesh choice is cosmetic here.

### DNS: a real requirement, but not the reason for the Pass prompt

Keep this separate from the Pass prompt. Both failures look like "the mesh is
broken", which is exactly why they get conflated — but fixing DNS does not fix
the prompt, and the prompt is not evidence of a DNS fault.

**Run your own DNS, and make sure it can resolve and reach hosts on whichever
VPN network you chose.** That resolver is what turns "reachable by IP" into
"reachable by name", and it is the layer that ties your mesh together. The
server reaches a client by name resolving to a mesh address, and a client
reaches the server the same way. Get this right and either mesh works; get it
wrong and you will blame the VPN.

In this deployment the resolver is **self-hosted** (pihole, inside a container),
and it answers on the mesh. It happens to sit on two networks here, but one is
enough — the requirement is only that the resolver is reachable from the network
you actually use. Two properties matter:

- **It answers on your VPN network.** Any host on the mesh can query it and get
  mesh addresses back.
- **DNS traffic stays on the internal path.** Queries go to the resolver over the
  VPN only — no lookup leaves for the public internet, so nothing is exposed and
  there is nothing to leak. (There is a DoH resolver running too, but the clients
  never touch it directly: they talk to the internal resolver, and that resolver
  is what talks outward.)

An address on one mesh is reachable **only over that mesh**, so if you do run
several, the resolver has to be reachable from each and the router between them
has to forward. Where two meshes meet, that forwarding is explicit:

```sh
# each mesh is a separate interface, and forwarding between them is allowed
ufw route allow in  on wg0     # wg0 <-> anywhere
ufw route allow out on wg0
```

With `DEFAULT_FORWARD_POLICY="DROP"` those rules are what let a client on one
mesh reach a resolver on the other. Remove them and DNS breaks silently while
the tunnel still looks healthy.

**The failure mode is deceptive**, which is why this wastes evenings: a
ZeroTier-only address works perfectly from any host that happens to be on
ZeroTier, so testing from the wrong machine makes a broken config look correct.

Two real failures, one box:

1. **`PEERDNS=<zerotier-ip>` in the WireGuard hub.** The phone had no route to
   the resolver, so *every* DNS lookup failed and the device looked like it had
   no internet at all. The tunnel itself was fine.
2. **`/etc/docker/daemon.json` pinned `"dns": ["<zerotier-ip>"]`** for every
   container on the host. When that mesh is down, **name resolution inside every
   container dies with it.** Plex is unaffected (it talks to IPs), but anything
   that resolves a hostname is not.

The fix is ordering, not removal — list resolvers so at least one is always
reachable:

```json
{ "dns": ["<mesh-resolver-ip>", "<other-resolver-ip>"] }
```

Ordering is a real trade, so choose deliberately:

- **Internal resolver first** — the intended setup: everything resolves through
  the self-hosted resolver on the mesh, with filtering intact.
- **A public/secondary resolver second** — a safety net, at the cost of
  occasionally resolving outside your own DNS.

Two gotchas when you apply it:

- **`systemctl reload docker` does not apply a `dns` change.** dockerd logs
  `Reloaded configuration` while its *effective* config still lists the old
  servers. You need a full `systemctl restart docker`. Containers with a
  restart policy (`always` / `unless-stopped`) come back on their own.
- **Verify from inside a container**, not from the host — they are different
  network namespaces:

  ```sh
  docker exec plex cat /etc/resolv.conf   # your new server must be listed
  ```

### What the server actually does (measured)

Plex tags every request it handles with the connection class it assigned, in the
`Plex Media Server.log`. Counted over a single log from the reference server:

| Client | Tag |
|---|---|
| LAN client | `(Subnet)` ×2598 |
| ZeroTier mesh client | `(Subnet)` ×30 |
| **WireGuard tunnel client** | **`(Subnet)` ×82, `(WAN)` ×0** |

**Plex already classifies WireGuard clients as local** — the same bucket as LAN
and mesh clients, not a single `(WAN)` among them. The only `(WAN)` entries in
that log came from an unrelated internet scanner probing the port, not from Plex
clients.

That refutes the two explanations this file used to give:

| Previous claim | Status |
|---|---|
| "WireGuard traffic arrives from a subnet Plex does not enumerate, so it is classified remote" | ❌ **false** — measured `(Subnet)`, zero `(WAN)` |
| "ZeroTier works because the kernel routes it via `dev lo`, so Plex sees loopback" | ❌ unsupported — mesh clients are tagged `(Subnet)`, same as everyone else |
| "The DNS layer is what makes remote playback work" | ❌ DNS governs *name resolution*; it does not control the Pass verdict |
| "`LanNetworksBandwidth` / `customConnections` fix the prompt" | ❌ both were set on a live server, both reverted — neither changed the outcome |

**What is left.** The server says local and the app still says remote, so the
verdict that gates playback is being taken somewhere the server log does not
cover — on the **client**. The leading, still-untested explanation is that the
Plex app decides from its *own* tunnel interface, and a client whose tunnel
address carries a bare `/32` has no local subnet containing the server.

This is the one measurement that separates the two cases. Run it from the server
while a stream from the affected client is playing:

```sh
docker exec plex sh -c 'T=$(grep -oP "PlexOnlineToken=\"\K[^\"]+" \
  "/config/Library/Application Support/Plex Media Server/Preferences.xml"); \
  curl -s "http://127.0.0.1:32400/status/sessions?X-Plex-Token=$T"' \
  | grep -oE 'local="[01]"|address="[^"]+"'
```

- `local="1"` **and the prompt still shows** ⇒ the cause is client-side.
- `local="0"` ⇒ the server gate is the cause after all, and the `(Subnet)` tags
  above do not mean what they look like.

### The tunnel mask: two knobs, only one of them a trap

These get conflated constantly, and they are unrelated:

| Knob | Set it wide | Why |
|---|---|---|
| **`Address`** (interface address + mask) | **safe** | `10.13.13.3/24` merely gives the client a local subnet that contains the server. Nothing on either side breaks. |
| **`AllowedIPs`** (crypto-routing table) | **trap on the server** | see below |

**The `AllowedIPs` trap — measured, not theorised.** Giving *every* peer the same
wide range (the linuxserver image's `SERVER_ALLOWEDIPS_PEER_*=<tunnel-subnet>`)
does **not** build a mesh. WireGuard's kernel resolves overlapping `AllowedIPs`
across peers by dropping the earlier entries, so once every peer claims the whole
subnet, `wg show` collapses 19 of 20 peers back to `/32` and **only the last peer
keeps the range** — and which peer that is can rotate on restart. It happens to
still work, because the per-peer `/32`s win by longest-prefix match, but the wide
range is decorative and the ordering is undefined.

The generated **per-peer `/32` table is correct as-is. Leave it alone.** That is
a different knob from the interface `Address`, and widening the `Address` mask
does not touch it.

### The one that actually bit us: `PersistentKeepalive`

If this file has one lesson worth taking, it is this one.

Symptom: **the app will not load at all** over the mesh, while the identical
setup is fine on ZeroTier. Not slow — nothing. And the tunnel looks healthy by
every casual check: `wg show` reports a recent handshake and the transfer
counters are climbing.

Cause: the peer that **sits behind NAT had no `PersistentKeepalive`**. A NAT'd
peer is only reachable at the endpoint its NAT last saw it use, and that mapping
expires after roughly 30–120 s of silence. Once it does, every packet the *other*
peers send toward it is dropped at the hub. The failure is **one-way**, which is
what makes it so confusing:

| Direction | Result |
|---|---|
| NAT'd peer → hub → everyone else | ✅ works (sending is what reopens the mapping) |
| everyone else → hub → NAT'd peer | ❌ dropped while the mapping is cold |

So a phone can pull hundreds of MB of media *out* of the server while its own
requests never land — "Plex won't load" behind a tunnel that reports itself
healthy. The Pass prompt fits here too: a client that cannot hold a working
direct connection is a client that falls back to the Relay.

**Fix** — on the NAT'd peer:

```ini
[Peer]
AllowedIPs = 10.13.13.0/24
PersistentKeepalive = 25
```

Apply it live without dropping the tunnel, then persist it in the conf:

```sh
sudo wg set wg0 peer <hub-public-key> persistent-keepalive 25
```

Two gotchas that cost real time:

- **Check the runtime, not the file.** `wg show <iface> persistent-keepalive`
  prints `off` when the line is absent — a conf that *looks* complete can still be
  missing it, and nothing warns you.
- **It is invisible in every other diagnostic.** Handshakes look current,
  counters move, and pings *from* the affected host succeed. Only traffic
  *toward* it fails. Test each direction separately, and read the application log
  for the client's source address with timestamps — a client with **zero** logged
  requests for hours, while data flowed outbound to it, is the tell.

Mesh VPNs that do their own NAT traversal and keepalive (ZeroTier, Tailscale) do
not have this failure mode at all. That is the real reason the same setup can
work on one mesh and be dead on another — not MTU, not DNS, not classification.

### Tunnel MTU: size the clients to the *hub*, not to themselves

A hub-and-spoke failure mode that presents as "the mesh is slow", and worth
checking before blaming anything else.

WireGuard adds ~60 bytes of overhead (IPv4), so a client's tunnel MTU has to fit
the **smallest egress link on the path**. In a hub-and-spoke mesh that is the
**hub's** link, because the hub re-encapsulates traffic it forwards between
peers:

| Link | MTU | Largest inner packet it can carry |
|---|---|---|
| hub `eth0` (egress) | 1400 | 1400 − 60 = **1340** |
| hub `wg0` | 1320 | sized correctly, 20 bytes of slack |
| a client `wg0` on the 1420 default | 1420 | **80 bytes too big** |

A packet from peer A to peer C is encapsulated, crosses the hub, and is
**re-encapsulated** for peer C — and on a 1400-MTU hub that second envelope does
not fit. WireGuard sets DF, so it is dropped rather than fragmented, and recovery
depends on ICMP PTB surviving the entire path. When it does not, you get
connections that stall and then "eventually" load: small requests fine, bulk TLS
and stream data hanging.

**Fix:** set `MTU` in every client's `[Interface]` to the hub's `wg0` MTU — or
`1280`, the IPv6-safe floor. Note the linuxserver image sizes the *hub's* `wg0`
from its `eth0` correctly, but writes **no MTU at all** into client configs, so
clients silently take the 1420 default.

```ini
[Interface]
Address = 10.13.13.3/24
MTU = 1320
```

This is **not** what caused the symptom above. It was believed to be the cause
for a while because the arithmetic fits the "stall" pattern neatly — but changing
the MTU did **not** fix it, and the real cause was the missing keepalive. Keep it
as config hygiene for a hub whose egress link is smaller than its clients'
tunnel, and check it when bulk transfers misbehave, but do not start here.

### ZeroTier setup — verified on this server

Server side, after joining your network in
[ZeroTier Central](https://my.zerotier.com/) and authorising the node:

```sh
sudo zerotier-cli listnetworks
# 200 listnetworks <nwid> <name> <mac> OK PRIVATE <iface> <mesh-ip>/16
```

That is the whole setup. There is nothing to configure for Plex — with
`network_mode: host` the server already listens on every interface, so the mesh
IP answers immediately:

```sh
curl -s "http://<mesh-ip>:32400/identity"
# <MediaContainer ... version="1.43.0.10492-121068a07"></MediaContainer>
```

Both halves of the pipeline work over the mesh: the server hardware-encodes
(`encoder=h264_nvenc`, per the check in step 5) and the client decodes the stream
normally. Streaming, transcoding and remote playback all behave the same as they
do on the LAN.

Then, from any device on the same network, open
`http://<mesh-ip>:32400/web`. In the Plex apps, add it as a manual connection
(`<mesh-ip>:32400`) — signing in with the same Plex account usually
auto-discovers it, but a manual connection is deterministic and does not depend
on Plex's own discovery services.

**Installing the mesh client on the viewing device is required**, phones and TVs
included. A browser on a friend's laptop that has not joined the network cannot
reach `<mesh-ip>` — which is the point.

### What actually has to be in place

| Requirement | Why | Where to set it |
|---|---|---|
| Node joined **and authorised** | an unauthorised node gets an interface but no route | ZeroTier Central → Members |
| `allowManaged=1` | lets ZeroTier assign the mesh address | `networks.d/<nwid>.local.conf` |
| `allowGlobal=0`, `allowDefault=0` | keeps ZeroTier out of your default route and global traffic — mesh only | same file |
| Firewall permits the mesh interface | UFW's default is deny-incoming | `ufw allow in on <iface>` |
| `network_mode: host` in compose | otherwise `32400` is only reachable inside the container's own netns | compose file |

`allowGlobal=0` and `allowDefault=0` are why this "just works" without touching
any routing: ZeroTier adds its own mesh route and interface, and nothing else.
Leave them off.

### Remote-access gotchas

- **Plex's "Remote Access" page will still say unavailable.** It tests the
  public-internet path via a port forward or Plex's relay, neither of which you
  are using. The red indicator is expected and means nothing here. Do not go
  chasing it with a manual port mapping or by enabling the relay.
- **ZeroTier's own DNS management is inert on a host without systemd-resolved.**
  It drives `systemd-resolved`, which is not installed on every host, so
  `allowDNS=1` does nothing there and the network advertises no resolver. On such
  a host `/etc/resolv.conf` is a plain static file, not a symlink.
- **Bitrate still matters.** Remote playback that needs more than your tunnel
  sustains will buffer. Cap the remote quality in the client rather than blaming
  the GPU — check the `encoder=` line first to confirm the transcode is on the
  hardware path at all.

### Plex settings that do *not* control any of this

Chasing the Pass prompt through Plex preferences wastes time. Measured, on a
signed-in server:

| Setting | Reality |
|---|---|
| `LanNetworksBandwidth` | **Bandwidth policy, not the local/remote verdict.** Setting it changes nothing about reachability. |
| `customConnections` | Publishes a URI to plex.tv, but the client still does not prefer it. |
| `allowedNetworks` | **Must stay empty.** It grants access **without login**, and only applies when the server is signed *out*. Filling it with a mesh subnet opens **unauthenticated** access to anything on the mesh. |
| `secureConnections` | `1` means **Preferred** — Plex's enum is inverted (`1:Preferred\|0:Required`). Do not "fix" it to `0`; that is the *stricter* setting and breaks plain-HTTP mesh clients. |

### Debug order: network first, preferences never

1. **Can the client reach the server at its tunnel IP?**

   ```sh
   curl http://<tunnel-ip>:32400/identity
   ```

   If that answers, **the network is fine** — the problem is classification, and
   no amount of Plex preference editing fixes classification.
2. **Is the client's mesh interface up, and is the handshake current?**

   ```sh
   sudo wg show          # WireGuard
   sudo zerotier-cli listnetworks   # ZeroTier
   ```

3. **Does the client resolve names at all?** If not, you are in the DNS problem
   in [DNS](#dns-a-real-requirement-but-not-the-reason-for-the-pass-prompt) above.

---

## 🧠 How the crack works

`plexmediaserver_crack.so` gets loaded into the `Plex Media Server` process
because it is added to the `DT_NEEDED` list of `libsoci_core.so`, which the
server always loads.

At load time its constructor runs `hook()`:

1. `get_dottext_info()` reads `/proc/self/maps` and finds the executable
   (`.text`) range of `Plex Media Server`.
2. `sig_scan()` does an AOB (array-of-bytes) scan of that range for a byte
   signature identifying the target function.
3. The first bytes of the target function are overwritten with a stub that
   `ret`s into `hook_is_feature_available()`:

   ```asm
   mov rax, <address of hook_is_feature_available>
   push rax
   ret
   ```

4. `hook_is_feature_available()` returns `true`, so every feature lookup
   succeeds.

### Why the last signature byte is a wildcard

Upstream's signature ended `... 48 8D 7B 30`, i.e. `lea rdi,[rbx+0x30]`. That
last byte is a **struct-member displacement**, and it drifts between Plex builds
— `0x30` in older ones, `0x70` in the builds tested here. Hard-coding it means
the scan finds nothing and the hook is silently never applied.

Wildcarding it makes one signature match exactly once on every build tested:

| Plex version | Signature hits |
|---|---|
| 1.43.0 | 1 ✅ |
| 1.43.3 | 1 ✅ |
| 1.43.4 | 1 ✅ |

**More than one hit is treated as failure.** `sig_scan` returns `0` rather than
guessing, so the hook is skipped instead of being applied to the wrong address.
Keep signatures long enough to be unique.

---

## 🔨 Building the library

The Plex Media Server process is a **musl** binary, so the crack must be built
against musl (Alpine). A host glibc build produces a `.so` that will not load
into the target process.

```sh
make                       # builds via the Alpine container, then verifies the linkage
```

or directly:

```sh
docker build -f docker/Dockerfile.build -o . .
```

Under the hood it is a single `g++` call, statically linking the C++ runtime so
the result depends only on `libc.musl-x86_64.so.1`:

```sh
g++ -shared -fPIC -O2 -std=c++17 -static-libstdc++ -static-libgcc \
    -o plexmediaserver_crack.so main.cpp hook.cpp -lrt
```

Always verify the result:

```sh
readelf -d plexmediaserver_crack.so | grep NEEDED
# must list libc.musl-x86_64.so.1, NOT libc.so.6
```

---

## 🧪 Cracking the newer builds

Everything below was measured, not assumed. Full detail in
[`docs/FINDINGS.md`](docs/FINDINGS.md).

### Short version

**Plex 1.43.4 breaks NVIDIA hardware transcoding, and this crack does not fix
it.** The working configuration is a pinned **1.43.0**.

### How that was established

A 1.43.4 container was given the **same known-good crack library** that works on
1.43.0 (9.9 MB, md5 `4d5dc96c8c7da383d84880b922935cd6`). Same server, same
request, same GPU:

| Plex | Crack | Transcode slot | Encoder chosen |
|---|---|---|---|
| 1.43.0 | known-good `.so` | `10de:1be1:1043:13f0@0000:01:00.0` | `h264_nvenc` |
| 1.43.4 | **same `.so`** | `CPU` | `libx264` |

The crack is not the variable. The regression is inside the Plex 1.43.4 binary.

### What 1.43.4 does differently

- **It never enumerates the GPU.** Grepping its log for the PCI-id pattern
  `10de:xxxx:xxxx:xxxx@…` returns nothing. 1.43.0 emits no such lines either, but
  its transcode-slot table still ends up keyed by the GPU PCI id, while 1.43.4's
  stays keyed to `CPU`.
- **It fetches server-side entitlement data** at startup from
  `https://servers.plex.tv/api/v2/server/users/features?filterFeatures[]=…`,
  `/users/subscriptions` and `/users/services`. **1.43.0 makes the same calls**,
  so this alone does not explain the difference.

The crack's signatures are **not** the problem — they still match exactly once in
both binaries. The gate 1.43.4 uses sits somewhere the crack does not reach.

### Ruled out

Each of these was tested and is **not** the cause:

1. **Stale signature** — the known-good crack's signatures still match exactly
   once in both 1.43.0 and 1.43.4.
2. **The `lea rdi,[rbx+0xNN]` displacement** — it does drift (`0x30` → `0x70`)
   and hard-coding it does cause silent failure, but correcting it does not make
   1.43.4 work. It is a real robustness fix, not the 1.43.4 cause.
3. **NVIDIA container toolkit / CDI** — a toolkit-1.18 regression does break
   `libcuda.so` visibility, and the entrypoint's driver-library copying works
   around it, but it affects all versions equally and is already handled.
4. **Entitlement / missing `hwtranscode` feature** — prefs correctly read
   `TranscoderHardwareAccelerated="1"` and `EnableHardwareEncoding="1"`, and the
   patched `hook_is_feature_available` is confirmed present in the running
   process returning `true`.
5. **Client capability profile** — a synthetic client and a real client both got
   the GPU slot on 1.43.0, so client-reported capabilities are not what changed.

### There are two different cracks

Do not assume this repo's source reproduces a working deployment — they are not
the same library:

| | ✅ Installed / known-good | 📦 This repo's source |
|---|---|---|
| **Size** | 9.9 MB | ~2 MB |
| **Disassembler** | **Zydis** | none |
| **Functions hooked** | 4: `is_feature_available`, `map_find`, `bitset_init`, `is_user_feature_set` | 1: `is_feature_available` |
| **Embedded feature GUIDs** | ~199 (incl. `hwtranscode`, `hardware_transcoding`, `transcode-hevc`, `transcode-tonemapping`) | 0 |

The larger, Zydis-based variant is the one that works on 1.43.0 — because it also
hooks the feature **bitset** (`hook_bitset_init`, `hook_is_user_feature_set`),
it patches entitlement at a different layer than the single-function variant.

**Upstream publishes both the source and a prebuilt binary**, and it is alive:
[`yuv420p10le/plexmediaserver_crack`](https://gitgud.io/yuv420p10le/plexmediaserver_crack)
carries `linux/hook.cpp` (the full 4-hook implementation), the vendored Zydis
source, and `binaries/plexmediaserver_crack.so` — the 9.9 MB build whose md5 is
quoted above. Download it from there rather than building this repo's source; see
step 1.

> Earlier revisions of this README claimed that source "does not appear to be
> published" because the upstream web UI returns **403** to anonymous requests.
> That was a misreading: the 403 is a bot-wall on the web front-end only. The
> GitLab API returns **200** and plain `git ls-remote` works, so the repo, its
> source, and its binary were reachable the whole time. The `gmh5225/plexmediaserver_crack`
> GitHub mirror does exist, but it is source-only — no binaries — and has been
> dormant since 2024.

Rebuilding this repo's smaller variant does **not** reproduce the working
deployment, and does not fix 1.43.4 either.

### Open questions

1. ~~Does the **Zydis-based** variant's source exist anywhere public?~~ **Answered:
   yes.** Upstream publishes `linux/hook.cpp` with all four hooks, the Zydis
   sources it links against, and a prebuilt binary. It is the correct starting
   point and it is downloadable — see step 1.
2. What function in 1.43.4 produces the CPU-keyed slot? `is_feature_available` is
   a red herring there.
3. Is the 1.43.4 behaviour reproducible on other NVIDIA setups **with a genuine
   Plex Pass**? If so it is an upstream bug and should be reported to Plex rather
   than worked around.

---

## 🚧 Gotchas

- **`Plex Transcoder` has a space in its name.** Shell quoting through
  `docker exec … bash -c "…"` mangles the path. Write a script file and
  `docker cp` it in instead.
- **The crack must be musl.** A glibc build will not load. Verify with
  `readelf -d plexmediaserver_crack.so | grep NEEDED`.
- **Plex's codec directory name is version-specific.** The downloaded codec pack
  sits under a hashed directory (e.g. `Codecs/a336ba9-…-linux-x86_64`) whose name
  changes between releases. A test script that hard-codes it fails with
  `no decoder found for: h264` on another version — resolve it at runtime.
- **Reading another process's maps is blocked in Docker even as root.** The Plex
  process can still read its own `/proc/self/maps` (which is what the crack uses).
  `PLEXCRACK_DEBUG=1` is the practical way to see whether the scan matched.
  Child processes also load the library and log a skip — expected, harmless.
- **`debian:bullseye` is no longer a usable build base** — its apt repos 404.
  Use Alpine.
- **Replacing the `.so` needs a container recreate.** The library is loaded at
  process start.

---

## 🤝 Get involved

The most useful thing you can contribute is a **data point**. "It works on
1.43.0" is one anecdote; the same result from ten independent setups is a fact.

- **📊 [`COMPATIBILITY.md`](COMPATIBILITY.md)** — which Plex builds and GPUs are
  known to work, from real reports.
- **🐛 [Open a hardware report](https://github.com/bpawnzZ/plexmediaserver-crack/issues/new?template=hardware-report.yml)**
  — a pass is as valuable as a failure. The form asks for exactly the fields that
  make the result verifiable.
- **🧪 [`docs/repro-1.43.4.md`](docs/repro-1.43.4.md)** — the fixed protocol for
  the open question: is 1.43.4 broken because of Plex or because of the crack?
- **💬 [Discussions](https://github.com/bpawnzZ/plexmediaserver-crack/discussions)**
  — setup help, troubleshooting, and ideas. Issues are for reports with data.
- **📖 [`CONTRIBUTING.md`](CONTRIBUTING.md)** — build, test, and what makes a
  report acceptable.

Cracking a newer Plex build is the open problem here, and the highest-value lead
is that the **Zydis-based** crack variant — the one that actually works on
1.43.0 — does not appear to have published source. Finding it matters more than
anything else in this repo. See
[Cracking the newer builds](#-cracking-the-newer-builds).

---

## 🔗 Relationship to upstream

Upstream is [`yuv420p10le/plexmediaserver_crack`](https://gitgud.io/yuv420p10le/plexmediaserver_crack)
on gitgud. It is **the authority on the library** — it builds and publishes the
crack, and it is where the binary comes from.

| | Upstream | This fork |
|---|---|---|
| **The crack library** | authors it | **downloads it** — never vendors or rebuilds it |
| **Install** | `crack_native.sh` / `crack_docker.sh`, run manually or on a cron | entrypoint applies it **at boot**, survives container recreation |
| **Pinning** | not addressed | pins Plex `1.43.0` and warns off `1.43.4` |
| **Version compatibility** | not discussed | the [1.43.4 finding](#-cracking-the-newer-builds), with evidence in [`evidence/`](evidence) |
| **NVIDIA / LinuxServer wiring** | — | driver-lib linking, `runtime: nvidia`, verified transcode check |
| **Remote access** | — | [ZeroTier / WireGuard](#-remote-access-without-a-plex-pass) notes |
| **Agent tooling** | — | [`AGENTS.md`](AGENTS.md) and the [agent prompt](#-hand-this-to-your-agent) |

**Where the binary actually lives.** Upstream's own installers fetch from
`gitgud.io/yuv420p10le/plexmediaserver_crack`, and that is the only place the
prebuilt `.so` is published:

```
https://gitgud.io/yuv420p10le/plexmediaserver_crack/-/raw/master/binaries/plexmediaserver_crack.so
```

**There is no GitHub equivalent.** A GitHub mirror
([`gmh5225/plexmediaserver_crack`](https://github.com/gmh5225/plexmediaserver_crack))
exists, but it is source-only — no `binaries/`, no releases — and has been
dormant since 2024. Its README points at `github.com/yuv420p10le/...`, which
returns **404**: those URLs were written before the project moved to gitgud and
were never updated. Do not fetch from GitHub; it will not work.

Upstream's web UI returns **403** to anonymous requests, which has repeatedly been
misread as the project being dead. It is not — the GitLab API returns **200** and
plain `git` works.

**If upstream is ever unreachable,** that is a real outage rather than a reason to
rebuild from this repo's source: this repo's build produces a *different, smaller*
library that does not reproduce a working deployment. See
[There are two different cracks](#there-are-two-different-cracks).

## 📁 Repo layout

| Path | What it is |
|---|---|
| `linux/` | C++ source for the crack preload library |
| `scripts/crack_plex.sh` | Wrapper the entrypoint runs to install the crack |
| `docker/Dockerfile.build` | Reproducible musl build |
| `examples/plex-entrypoint.sh` | Entrypoint showing how the crack is wired in |
| `examples/docker-compose.yml` | Compose service showing the required mounts |
| `docs/FINDINGS.md` | Full write-up of the 1.43.4 investigation |
| `docs/repro-1.43.4.md` | Fixed protocol for reproducing the 1.43.4 regression |
| `COMPATIBILITY.md` | The compatibility matrix — working and broken setups |
| `AGENTS.md` | Build/verify commands and constraints, for AI coding agents |
| `CONTRIBUTING.md` | How to contribute, and what counts as done |

**Canonical repo:** this repo lives on
[GitHub](https://github.com/bpawnzZ/plexmediaserver-crack). Issues, Discussions
and pull requests belong there.
[gitgud](https://gitgud.io/bpawnz/plexmediaserver_crack_updated) is a read-only
mirror; do not open issues on it.

This is a documentation-and-tooling fork; upstream is the authority on the
library itself. Commit messages follow
[Conventional Commits](https://www.conventionalcommits.org/). Issues and PRs are
welcome, but please read `docs/FINDINGS.md` first — several obvious hypotheses
have already been tested and ruled out.
