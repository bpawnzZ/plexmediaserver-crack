# Reproducing the 1.43.4 regression

A fixed protocol so that reports from different machines are actually
comparable.

**The question this answers:** does Plex 1.43.4 fail to use NVIDIA hardware
transcoding because of Plex itself, or because of the crack?

**Expected outcome of a valid run:** the same `.so` that produces
`encoder=h264_nvenc` on 1.43.0 produces `encoder=libx264` on 1.43.4. If you can
show that with a **genuine Plex Pass**, it is an upstream Plex bug and worth
reporting to Plex.

## Prerequisites

- An NVIDIA GPU that supports NVENC.
- Docker, and an NVIDIA container toolkit setup that already works — that is a
  hard problem in its own right. Solve it before starting, and confirm
  `nvidia-smi` inside the container sees the GPU.

The crack library must be the **9.9 MB, Zydis-based** build. Note its hash:

```sh
md5sum plexmediaserver_crack.so
# reference: 4d5dc96c8c7da383d84880b922935cd6
```

This repo's own build output is a **different, smaller** library and is not a
valid input to this test. See [the two cracks](FINDINGS.md).

## Variables to hold fixed

Change exactly one thing — the Plex version. Everything else identical:

- the `plexmediaserver_crack.so` file (same hash both runs)
- the GPU and host driver
- the client, the media file, and the requested quality
- the `NVIDIA_*` environment variables and the `runtime: nvidia` setting

If more than the version differs between runs, the result proves nothing.

## Procedure

### 1. Get 1.43.0 working first

Run the [quick start](../README.md#-quick-start) with

```yaml
image: linuxserver/plex:1.43.0.10492-121068a07-ls297
VERSION: 1.43.0.10492-121068a07-ls297
```

Start a transcode and confirm the pass condition. Do not continue until you see
it:

```sh
docker exec plex grep -E "Used slots for|encoder=" \
  "/config/Library/Application Support/Plex Media Server/Logs/Plex Media Server.log" | tail -3

# expect: Used slots for 10de:<pci-id> ... is now 1
#         ... encoder=h264_nvenc ...
```

### 2. Change only the version

```yaml
image: linuxserver/plex:1.43.4.<build>-ls<nnn>
VERSION: 1.43.4.<build>-ls<nnn>      # must equal the tag, never "docker"
```

```sh
docker compose up -d --force-recreate
```

Then confirm the crack still applied, before reading anything else:

```sh
docker exec plex /config/patchelf --print-needed \
  /usr/lib/plexmediaserver/lib/libsoci_core.so | head -1
# expect: plexmediaserver_crack.so
```

If the crack did **not** apply, stop — you are testing a different thing. Re-run
with `PLEXCRACK_DEBUG=1` and check `[crack] is_feature_available = ...` is
nonzero.

### 3. Run the same transcode

Same client, same media, same quality as step 1. Then:

```sh
docker exec plex grep -E "Used slots for|encoder=" \
  "/config/Library/Application Support/Plex Media Server/Logs/Plex Media Server.log" | tail -3
```

### 4. Record both results

Paste both raw log excerpts into a
[hardware report](https://github.com/bpawnzZ/plexmediaserver-crack/issues/new?template=hardware-report.yml)
— or into a
[discussion](https://github.com/bpawnzZ/plexmediaserver-crack/discussions) if it
needs more room.

Include:

- both Plex versions and image tags
- the `md5sum` of the `.so` (same value for both runs)
- GPU, host driver version
- **whether the account has a real Plex Pass** — the single most valuable field
- both log excerpts, verbatim

## Why the direct-transcoder test is not acceptable

Do **not** substitute this for the procedure above:

```sh
Plex Transcoder -hwaccel nvdec -i in.mp4 -c:v h264_nvenc -f null -
```

It succeeds on every version tested, including 1.43.4, because it bypasses Plex
Media Server's transcode-decision engine. The decision engine is where the
regression lives. A green result here is a false positive and has already wasted
time once.

## What has already been ruled out

Do not re-test these — they are answered in [`FINDINGS.md`](FINDINGS.md):

- a stale or mismatched signature (matches exactly once on 1.43.0/1.43.3/1.43.4)
- the signature's `lea` displacement byte
- NVIDIA container toolkit / CDI library visibility
- the entitlement flag or a missing `hwtranscode` feature (the hook is live and
  returns `true`)
- the client capability profile
