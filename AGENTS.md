# AGENTS.md

Instructions for AI coding agents working in this repo. Humans: read
[CONTRIBUTING.md](CONTRIBUTING.md) instead.

## What this is

`plexmediaserver_crack.so` is a preload library patched into Plex Media Server's
`libsoci_core.so`, so it loads into the `Plex Media Server` process. Its
constructor AOB-scans the server's executable segment for
`is_feature_available(user, feature)` and overwrites the first bytes of that
function with a stub that jumps to a hook returning `true`. Every feature lookup
then succeeds, which unlocks Plex Pass features (hardware transcoding and
others) on a server whose account has no Plex Pass.

Source: [`linux/hook.cpp`](linux/hook.cpp), [`linux/main.cpp`](linux/main.cpp),
[`linux/hook.hpp`](linux/hook.hpp).

## Build

```sh
make
```

Builds through `docker/Dockerfile.build` (Alpine) and then runs `make verify`.
Requires Docker; nothing to install on the host.

## Verify

```sh
readelf -d plexmediaserver_crack.so | grep NEEDED
# must list libc.musl-x86_64.so.1 — NOT libc.so.6
```

`make` already runs this and deletes the output on failure.

## Constraints — do not violate

1. **The output must be a musl build.** Plex Media Server is a musl binary; a
   glibc `.so` will not load. Never build on the host, never switch
   `Dockerfile.build` off Alpine.
2. **Do not bump the Plex version pin** (`linuxserver/plex:1.43.0.10492-121068a07-ls297`)
   and do not change `VERSION=` away from that same version string. Plex 1.43.4
   breaks NVIDIA hardware transcoding on its own — the crack is not involved.
   `VERSION=docker` makes Plex self-update on boot and silently walks past the pin.
3. **Do not add network calls, telemetry, or remote fetches** to the library.
   It hooks a licensing check; anything else it does is scope creep with a
   security cost.
4. **When the signature scan misses, do not "fix" it by adding more signatures
   blindly.** `sig_scan` returns 0 for *no match or an ambiguous match*, and
   skipping is deliberate — patching the wrong address is worse than not
   patching. Investigate the build first, then record what you found.
5. Keep the last signature byte (`48 8D 7B ?`) wildcarded. The `lea
   rdi,[rbx+0xNN]` displacement drifts between Plex builds (`0x30` pre-1.43,
   `0x70` in 1.43.x); hard-coding it causes a silent no-op.

## Definition of done

A change is only done when all three hold, with the raw output recorded:

1. `make` succeeds and the readelf check reports a musl build.
2. Driving a real session through Plex Media Server logs
   `Used slots for 10de:<pci-id> ... is now 1` (a GPU slot — not
   `Used slots for CPU`).
3. The same log shows `encoder=h264_nvenc` (not `encoder=libx264`).

**Never test by invoking `Plex Transcoder` directly.** It succeeds on every
version, including builds where hardware transcoding is broken end to end,
because it bypasses the server's transcode-decision engine. That result is a
false positive.

## Dead ends — do not re-investigate

These have been tested and ruled out. Full detail in
[`docs/FINDINGS.md`](docs/FINDINGS.md); read it before proposing a hypothesis.

- Stale or wrong signature — it matches exactly once in 1.43.0, 1.43.3 and 1.43.4.
- The signature's `lea` displacement byte — real robustness issue, fixed, but it
  is **not** why 1.43.4 fails.
- NVIDIA container toolkit / CDI regressions — already worked around by the
  entrypoint copying driver libraries; affects all versions equally.
- Missing entitlement or `hwtranscode` feature flag — preferences are correct and
  the hook is confirmed live and returning `true`.
- Client capability profile — synthetic and real clients both got the GPU slot on
  1.43.0.

## Things worth working on

Open questions live as issues (see
[the issue list](https://github.com/bpawnzZ/plexmediaserver-crack/issues)) and in
[`README.md` #cracking-the-newer-builds](README.md#-cracking-the-newer-builds).
The highest-value one: the **Zydis-based** crack variant is the one that actually
works on 1.43.0, and its source does not appear to be published. Finding it
matters more than anything else here.

## When you learn something durable

Add it to [`docs/FINDINGS.md`](docs/FINDINGS.md) — including negative results.
This repo's value is mostly in the hypotheses that were tested and killed. If you
confirm a working configuration, add a row to
[`COMPATIBILITY.md`](COMPATIBILITY.md) too.
