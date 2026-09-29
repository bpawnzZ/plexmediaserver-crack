# plexmediaserver_crack (updated fork)

A maintained fork of [`yuv420p10le/plexmediaserver_crack`](https://gitgud.io/yuv420p10le/plexmediaserver_crack)
/ the [`gmh5225` GitHub mirror](https://github.com/gmh5225/plexmediaserver_crack),
with notes, build tooling, and a version-independent signature.

The crack is a preload library (`plexmediaserver_crack.so`) that is patched into
Plex Media Server's `libsoci_core.so` so that Plex's feature-entitlement check
always returns `true` — enabling Plex Pass features (hardware transcoding, etc.)
on a server whose account does not have a Plex Pass.

> **Status / scope of this fork.** This repo carries the *source of the smaller
> upstream variant* plus everything learned while trying to make it work on Plex
> 1.43.4. **It does not currently make 1.43.4 work.** See
> [Hardware transcoding on 1.43.4](#hardware-transcoding-on-1434-the-important-part)
> for what was actually found. Read that section before assuming a rebuild fixes
> anything.

---

## Contents

| Path | What it is |
|---|---|
| `linux/` | C++ source for the crack preload library |
| `scripts/crack_plex.sh` | Wrapper the container entrypoint runs to install the crack |
| `docker/Dockerfile.build` | Reproducible musl build of `plexmediaserver_crack.so` |
| `examples/plex-entrypoint.sh` | Example container entrypoint showing how the crack is wired in |
| `examples/docker-compose.yml` | Example compose service showing the mounts the entrypoint expects |
| `docs/FINDINGS.md` | Full write-up of the 1.43.4 hardware-transcode investigation |

---

## How the crack works

`plexmediaserver_crack.so` is loaded into the `Plex Media Server` process because
it is added to the `DT_NEEDED` list of `libsoci_core.so`, which the server
always loads.

At load time the library's constructor runs `hook()`:

1. `get_dottext_info()` reads `/proc/self/maps` and locates the executable
   (`.text`) range of `Plex Media Server`.
2. `sig_scan()` does an AOB (array-of-bytes) scan of that range for a byte
   signature identifying the target function.
3. The first bytes of the target function are overwritten with a small
   shellcode stub that `ret`s into `hook_is_feature_available()`:

   ```asm
   mov rax, <address of hook_is_feature_available>
   push rax
   ret
   ```

4. `hook_is_feature_available()` returns `true` unconditionally, so every
   feature lookup succeeds.

The signature scanned is:

```
55 48 89 E5 41 57 41 56 53 50 49 89 F7 48 89 FB 4C 8D 77 08 4C 89 F7 E8 ? ? ? ? 48 8D 7B ?
```

### Why the last byte is a wildcard

Upstream's original signature ended `... 48 8D 7B 30`, i.e. `lea rdi,[rbx+0x30]`.
That last byte is a struct-member **displacement**, and it drifts between Plex
builds — `0x30` in older builds, `0x70` in the ones tested here. Hard-coding it
means the scan silently finds nothing and the hook is never applied (no error,
no log, just features staying disabled).

Wildcarding the final displacement byte makes the same signature match once,
unambiguously, on every build tested:

| Plex version | Signature hits |
|---|---|
| 1.43.0 | 1 |
| 1.43.3 | 1 |
| 1.43.4 | 1 |

**A signature that returns more than one hit is treated as a failure** — the
scan returns `0`, and the hook is skipped rather than applied to the wrong
address. Keep signatures long enough to be unique.

---

## Building

The target process is a **musl** binary, so the crack must be built against musl
(Alpine), not glibc. Building on the host (glibc) produces a `.so` that will not
load.

```sh
make            # builds plexmediaserver_crack.so via the Alpine container
```

or directly:

```sh
docker build -f docker/Dockerfile.build -o . .
```

The build is a single `g++` invocation, statically linking the C++ runtime so
the result depends only on `libc.musl-x86_64.so.1`:

```sh
g++ -shared -fPIC -O2 -std=c++17 -static-libstdc++ -static-libgcc \
    -o plexmediaserver_crack.so main.cpp hook.cpp -lrt
```

---

## How it is installed in the container

Two things have to happen at container start:

1. **NVIDIA driver libraries have to be exposed to the transcoder.** The
   `nvidia` container runtime injects the driver libs into `/lib`, but
   `Plex Transcoder` resolves them through its own `rpath`
   (`/usr/lib/plexmediaserver/lib`). Without this step NVENC fails with
   `Cannot load libcuda.so.1` and Plex silently falls back to software
   transcoding.

2. **The crack library has to be linked into `libsoci_core.so`.**

Both are done by the entrypoint. See
[`examples/plex-entrypoint.sh`](examples/plex-entrypoint.sh) and
[`examples/docker-compose.yml`](examples/docker-compose.yml).

The entrypoint:

- copies `libcuda.so.1`, `libnvidia-encode.so.1`, `libnvcuvid.so.1`,
  `libnvidia-ptxjitcompiler.so.1`, `libnvidia-ml.so.1` from `/lib` into
  `/usr/lib/plexmediaserver/lib/` (copying the live versions each boot so the
  library version always matches the active runtime), then
- runs `crack_plex.sh`, which symlinks `plexmediaserver_crack.so` next to
  `libsoci_core.so` and uses `patchelf` to prepend it to that library's
  `DT_NEEDED` list, then
- `exec /init` to start Plex.

### Compose wiring

The container needs:

```yaml
runtime: nvidia
environment:
  - NVIDIA_VISIBLE_DEVICES=all
  - NVIDIA_DRIVER_CAPABILITIES=all
volumes:
  - ./plex:/config                                # config, incl. the .so + patchelf
  - ./plex-entrypoint.sh:/plex-entrypoint.sh:ro   # entrypoint
  - .:/host-docker:ro                             # so crack_plex.sh is reachable
entrypoint: /plex-entrypoint.sh
```

The `.so` and `patchelf` binary live in the mapped config directory (`./plex`),
which `crack_plex.sh` symlinks into the Plex library directory at runtime.

---

## Hardware transcoding on 1.43.4 (the important part)

### Summary

**Plex 1.43.4 breaks NVIDIA hardware transcoding, and this crack does not fix
it.** Pinning to **1.43.0** is the working configuration.

### How this was established

A test container running 1.43.4 was given the **exact same, known-good
`plexmediaserver_crack.so`** that works on 1.43.0 (9.9 MB, md5
`4d5dc96c8c7da383d84880b922935cd6`). Same server, same request, same GPU:

| Version | Crack | Transcode slot | Encoder chosen |
|---|---|---|---|
| 1.43.0 | known-good `.so` | `10de:1be1:1043:13f0@0000:01:00.0` | `h264_nvenc` |
| 1.43.4 | **same** `.so` | `CPU` | `libx264` |

The crack is not the variable. The regression is inside the Plex 1.43.4 binary.

### Why this is easy to get wrong

**Do not test by running `Plex Transcoder` directly.** A direct invocation like

```sh
Plex Transcoder -hwaccel nvdec -i in.mp4 -c:v h264_nvenc -f null -
```

**succeeds on every version**, including 1.43.4 — because it bypasses Plex Media
Server's transcode-decision engine, which is where the regression lives. A
direct-binary test produces a false positive.

The only valid test is to let **Plex Media Server itself** choose the encoder,
then read the decision out of its log:

- **Working:** the log shows `Used slots for 10de:<gpu-pci-id>` and
  `encoder=h264_nvenc`.
- **Broken:** the log shows `Used slots for CPU` and `encoder=libx264`.

You can trigger a real session with the server's own token (from
`Preferences.xml`):

```sh
curl -H "X-Plex-Token: $TOKEN" \
  "http://127.0.0.1:32400/video/:/transcode/universal/start.m3u8?path=%2Flibrary%2Fmetadata%2F<id>&mediaIndex=0&partIndex=0&protocol=hls&directPlay=0&directStream=1&videoResolution=1280x720&maxVideoBitrate=4000&session=test&X-Plex-Platform=Chrome&X-Plex-Client-Identifier=test"
```

then grep `Plex Media Server.log` a few seconds later.

### What 1.43.4 actually does

- It **never enumerates the GPU**. Grepping its log for the PCI-id pattern
  `10de:xxxx:xxxx:xxxx@...` returns nothing at all; there are no GPU/encoder
  initialisation lines. 1.43.0 has no such lines either, but its transcode-slot
  table still ends up keyed by the GPU PCI id, whereas 1.43.4's stays keyed to
  `CPU`.
- It fetches server-side entitlement data from
  `https://servers.plex.tv/api/v2/server/users/features?filterFeatures[]=...`,
  `/users/subscriptions`, and `/users/services` at startup. **1.43.0 makes the
  same calls**, so this alone does not explain the difference.

The crack's signatures are **not** the problem: the signatures it uses still
match exactly once in both 1.43.0 and 1.43.4 binaries. The gate 1.43.4 uses sits
somewhere the crack does not reach.

### There are two different cracks

Do not assume the GitHub source reproduces a working deployment. The two are
quite different:

| | Installed / known-good | This repo's source (upstream GitHub) |
|---|---|---|
| Size | 9.9 MB | ~2 MB |
| Toolchain | Alpine / GCC 12 musl | same, but different build |
| Disassembler | **Zydis** | none |
| Functions hooked | 4: `is_feature_available`, `map_find`, `bitset_init`, `is_user_feature_set` | 1: `is_feature_available` |
| Embedded feature GUIDs | ~199 (incl. `hwtranscode`, `hardware_transcoding`, `transcode-hevc`, `transcode-tonemapping`) | 0 |

The larger, Zydis-based variant is the one that actually works on 1.43.0. Its
source does not appear to be published — the upstream gitgud repo returns 403 and
the GitHub mirror has been dormant since 2024.

---

## Gotchas

- **`Plex Transcoder` has a space in its name.** Shell quoting through
  `docker exec … bash -c "…"` mangles the path. Write a script file and
  `docker cp` it into the container instead.
- **The crack must be built against musl.** A glibc build will not load into
  Plex's musl process. Verify with
  `readelf -d plexmediaserver_crack.so | grep NEEDED` — it should list
  `libc.musl-x86_64.so.1`, not `libc.so.6`.
- **A stored codec directory name is version-specific.** Plex's downloaded codec
  pack lives under a hashed directory (e.g.
  `Codecs/a336ba9-…-linux-x86_64`) whose name changes between releases. Any test
  script that hard-codes it will fail with `no decoder found for: h264` on a
  different version — resolve it at runtime.
- **Debugging the hook.** Reading another user's `/proc/<pid>/maps` is blocked in
  Docker even as root, but the Plex process can still read its own
  `/proc/self/maps` (which is what the crack relies on). Set
  `PLEXCRACK_DEBUG=1` in the container environment to log the scanned `.text`
  range, the resolved target address, and whether the signature matched. Without
  it the library is silent. Note that child processes also load the library and
  log a skip — expected and harmless.
- **`debian:bullseye` is no longer a usable build base** — its apt repositories
  now 404. Use Alpine.
- **Writes do not always take effect immediately.** After replacing the `.so`,
  recreate the container; the library is loaded at process start.

---

## Repo notes

- This is a documentation-and-tooling fork. Upstream is the authority on the
  library itself.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/).
- Issues/PRs welcome, but please read `docs/FINDINGS.md` first — several of the
  obvious hypotheses there have already been tested and ruled out.
