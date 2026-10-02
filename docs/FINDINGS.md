# Findings: NVIDIA hardware transcoding and the Plex 1.43.x crack

Investigation notes from trying to restore NVIDIA hardware transcoding on a Plex
Media Server running in Docker (linuxserver/plex image), with the crack applied.

Everything below was reproduced directly; the failed hypotheses are listed too,
because they are the ones most likely to be repeated.

## Headline

**Plex 1.43.4 breaks NVIDIA hardware transcoding. The crack is not the cause.**
The working configuration is a pinned **1.43.0**.

## Methodology (read this first)

The transcode encoder is chosen by **Plex Media Server**, not by the `Plex
Transcoder` binary. Testing by invoking the transcoder directly gives a false
positive — it encodes with `h264_nvenc` on every version, including broken ones,
because it bypasses the decision engine.

**Valid test:** drive a real session through the server and read the decision
from its log.

Trigger one (token is in `Preferences.xml` as `PlexOnlineToken`):

```sh
curl -H "X-Plex-Token: $TOKEN" \
  "http://127.0.0.1:32400/video/:/transcode/universal/start.m3u8?path=%2Flibrary%2Fmetadata%2F<id>&mediaIndex=0&partIndex=0&protocol=hls&directPlay=0&directStream=1&videoResolution=1280x720&maxVideoBitrate=4000&session=test&X-Plex-Platform=Chrome&X-Plex-Client-Identifier=test"
```

Then, a few seconds later:

```sh
grep -E "Used slots for|encoder=" "Plex Media Server.log" | tail
```

Interpretation:

| Log line | Meaning |
|---|---|
| `Used slots for 10de:<pci-id> …is now 1` | GPU slot registered — hardware path |
| `Used slots for CPU is now 1` | software slot — hardware path not taken |
| `encoder=h264_nvenc` | hardware encode selected |
| `encoder=libx264` | software encode selected |

`TPU: hardware transcoding: final decoder: nvdec, final encoder: nvenc` confirms
the transcoder itself then used the hardware path, but the *decision* lines above
are what prove the server chose it.

## Result

Controlled comparison, same input file, same GPU, same compose config. The
1.43.4 container was given the **same known-good crack library** that works on
1.43.0 (9.9 MB, md5 `4d5dc96c8c7da383d84880b922935cd6`):

| Plex | Crack | Transcode slot | Encoder |
|---|---|---|---|
| 1.43.0 | known-good `.so` | `10de:1be1:1043:13f0@0000:01:00.0` | `h264_nvenc` |
| 1.43.4 | **same `.so`** | `CPU` | `libx264` |

The crack is not the variable.

## What 1.43.4 does differently

- **No GPU enumeration.** Grepping the 1.43.4 log for `10de:xxxx:xxxx:xxxx@…`
  returns nothing; there are no GPU/encoder init lines. 1.43.0 emits no such
  lines either, but its slot table ends up GPU-keyed while 1.43.4's stays
  CPU-keyed.
- **Server-side entitlement calls.** 1.43.4 fetches
  `https://servers.plex.tv/api/v2/server/users/features?filterFeatures[]=…`,
  `/users/subscriptions` and `/users/services` at startup. **1.43.0 makes the
  same calls** (7 vs 5 occurrences in comparable logs), so this is not on its own
  the differentiator.

## Ruled out

Each of these was tested and is **not** the cause:

1. **Stale signature in the crack.** The known-good crack's signatures still match
   **exactly once** in both the 1.43.0 and 1.43.4 binaries. Not the problem.
2. **The `lea rdi,[rbx+0xNN]` displacement.** It does drift between builds
   (`0x30` → `0x70`), and hard-coding it does cause silent scan failure — but
   correcting it does not make 1.43.4 work. It is a real robustness fix for the
   signature, not the 1.43.4 cause.
3. **NVIDIA container toolkit / CDI.** A toolkit-1.18 regression does break
   `libcuda.so` visibility, and the entrypoint's driver-library copying works
   around it — but it affects all versions equally and is already handled.
4. **Plex Pass entitlement / missing `hwtranscode` feature.** The server reports
   `TranscoderHardwareAccelerated="1"` and `EnableHardwareEncoding="1"`, and the
   crack's `hook_is_feature_available` returns `true` for `hwtranscode`; the
   patched function is confirmed present in the running process.
5. **Client capability profile.** A synthetic client and a real client both got
   the GPU slot on 1.43.0, so client-reported capabilities are not what changed.

## Two different crack variants

The installed, working crack and the published upstream source are **not the same
library**:

| | Installed / known-good | This repo's source |
|---|---|---|
| Size | 9.9 MB | ~2 MB |
| Disassembler | **Zydis** | none |
| Functions hooked | 4: `is_feature_available`, `map_find`, `bitset_init`, `is_user_feature_set` | 1: `is_feature_available` |
| Embedded feature GUIDs | ~199 (incl. `hwtranscode`, `hardware_transcoding`, `transcode-hevc`, `transcode-tonemapping`) | 0 |

Because the larger variant also hooks the feature **bitset**
(`hook_bitset_init`, `hook_is_user_feature_set`), it patches entitlement at a
different layer than the single-function variant. **Both its source and a
prebuilt binary are published upstream** at
`gitgud.io/yuv420p10le/plexmediaserver_crack` (`linux/hook.cpp` holds all four
hooks; `binaries/plexmediaserver_crack.so` is the 9.9 MB build, md5
`4d5dc96c8c7da383d84880b922935cd6`). An earlier revision of this file claimed the
source was unpublished because the web UI returns 403 to anonymous requests —
that was a bot-wall, not a dead repo: the GitLab API returns 200 and `git` works.

Rebuilding the small upstream variant and installing it does **not** reproduce
the working deployment, and does not fix 1.43.4 either.

## Reproducing the known-good failure (sanity check)

The fastest way to confirm the finding is to take the working setup and change
only the image tag to a 1.43.4 build, then run the valid test above. The slot
line flips from the GPU PCI id to `CPU`.

## If this is picked up again

Open questions, in rough order of usefulness:

1. Does the **Zydis-based** variant's source exist anywhere public? That variant
   is what works on 1.43.0 and would be the correct starting point.
2. What function in 1.43.4 produces the CPU-keyed slot?
   `is_feature_available` is a red herring on 1.43.4.
3. Is the 1.43.4 behaviour reproducible on other NVIDIA setups with a legitimate
   Plex Pass? If so, it is an upstream bug and should be reported to Plex rather
   than worked around.

---

## Session 2026-09-29/30 — controlled A/B reproduction, root cause isolated

All of the below is new, verified this session, on this host (GTX 1070
Mobile `10de:1be1`, driver 570.153.02). Logs and binaries retained under
`evidence/` and `work/bin/`.

## Method (the two-server A/B)

Both servers run **simultaneously**, both using the **same config copy of the prod
library DB**, same host, same GPU, same known-good crack `.so`
(md5 `4d5dc96c8c7da383d84880b922935cd6`):

| | prod (`plex`) | test (`plex-test2`) |
|---|---|---|
| Image | `linuxserver/plex:1.43.0.10492-121068a07-ls297` | `linuxserver/plex:1.43.4.10903-e5521bd8c-ls326` |
| Compose | `~/docker/plex-crypt/docker-compose.nvidia.yml` | `~/docker/plex-test2/docker-compose.yml` |
| Port | `32400` | `32403` |
| Network | host | `backend` (bridge) |
| Config | `~/docker/plex-crypt/plex` | `~/docker/plex-test2/plex` (copy of the above) |

Same request to both — HLS transcode of library item `9524` (h264 1080p, 50 fps,
`/megaMedia/CathyBulgakova/Copy_of_IMG_4500.mp4`), `directPlay=0 directStream=0
maxVideoBitrate=20000 videoResolution=1920x1080 protocol=hls hasMDE=1`:

```sh
curl -s -G "http://127.0.0.1:<port>/video/:/transcode/universal/start.m3u8" \
  -H "X-Plex-Token: $TOKEN" -H "X-Plex-Client-Identifier: zzeta" \
  -H "X-Plex-Platform: Chrome" -H "X-Plex-Product: Plex Web" \
  --data-urlencode "path=/library/metadata/9524" \
  --data-urlencode "mediaIndex=0" --data-urlencode "partIndex=0" \
  --data-urlencode "protocol=hls" --data-urlencode "directPlay=0" \
  --data-urlencode "directStream=0" --data-urlencode "maxVideoBitrate=20000" \
  --data-urlencode "videoResolution=1920x1080" --data-urlencode "hasMDE=1" \
  --data-urlencode "session=$SID"
# then GET session/$SID/base/index.m3u8 and .../base/00000.ts to force the
# transcoder to actually spawn and produce segments.
```

## Result — the §6 pass/fail pair, both servers, side by side

`evidence/AB-decision.txt`:

```
### 1.43.0 (prod :32400) — PASS
[Req#11b/Transcode] Streaming Resource: Adding session …  Used slots for 10de:1be1:1043:13f0@0000:01:00.0is now 1
[Req#11b/Transcode] Streaming Resource: Reached Decision … Video=(… decision=transcode bitrate=17697 encoder=h264_nvenc …)

### 1.43.4 (test :32403) — FAIL
[Req#b9/Transcode/TPU] Streaming Resource: Adding session …  Used slots for CPUis now 1
[Req#b9/Transcode/TPU] Streaming Resource: Reached Decision … Video=(… decision=transcode bitrate=17697 encoder=libx264 …)
```

The real `Plex Transcoder` argv confirms it (`evidence/1434-repro.txt`):
1.43.4 spawns the job with `-codec:0 libx264`; the source-side filter graph still
advertises `format=pix_fmts=yuv420p|nv12`, i.e. the binary knows about the GPU
formats but does not pick the GPU encoder.

## Finding 1 — the device/GPU is fully visible to 1.43.4 (rules out the easy causes)

Inside **both** containers, `plex-test2` included, everything the probe needs is
present and identical:

```
/proc/driver/nvidia/gpus/0000:01:00.0      present
/sys/bus/pci/devices/0000:01:00.0/vendor   0x10de
/sys/bus/pci/devices/0000:01:00.0/device   0x1be1
/dev/nvidia0 /dev/nvidiactl /dev/nvidia-uvm … present
/dev/dri/card0 /dev/dri/renderD128         present
nvidia-smi -L   GPU 0: NVIDIA GeForce GTX 1070 …
/usr/lib/plexmediaserver/lib/libcuda.so.1  present (71 MB)
/usr/lib/plexmediaserver/lib/libnvidia-encode.so.1 present
```

So: not a missing device, not a missing driver lib, not the NVIDIA container
toolkit, not the entrypoint's lib-linking, not the crack. 1.43.4 can see the GPU
and simply **does not probe it**.

## Finding 2 — 1.43.0 runs the capability probe; 1.43.4 never does

1.43.0 startup, at decision time (`[Req#11b/Transcode]`):

```
Codecs: testing h264_nvenc (encoder)
Codecs: hardware transcoding: testing API nvenc for device 'pci:0000:01:00.0' (NVIDIA GP104BM [GeForce GTX 1070 Mobile])
[FFMPEG] - Loaded lib: libcuda.so.1
[FFMPEG] - Loaded sym: NvEncodeAPICreateInstance
Codecs: testing h264 (decoder) with hwdevice nvdec
Codecs: hardware transcoding: testing API nvdec for device 'pci:0000:01:00.0' (NVIDIA GP104BM [GeForce GTX 1070 Mobile])
TPU: hardware transcoding: using hardware decode accelerator nvdec
TPU: hardware transcoding: final decoder: nvdec, final encoder: nvenc
```

1.43.4, same request: **not one of those lines appears.** No `testing h264_nvenc`,
no `testing API nvenc`, no `Loaded lib: libcuda.so.1`. The probe is never entered,
so `nvenc` never enters the encoder-candidate set, so the slot falls to `CPU`.
The `CPU` slot is a **symptom of a skipped probe**, not a decision to use the CPU.

## Finding 3 — the decision moved from `Transcode` to `Transcode/TPU`

Same operation, log-namespace tag differs by version:

| | 1.43.0 | 1.43.4 |
|---|---|---|
| Tag on "Adding session…/Reached Decision" | `[Req#11b/Transcode]` | `[Req#b9/Transcode/**TPU**]` |

`TPU` is present in both binaries but trimmed in 1.43.4 (19 → 10 `TPU`-prefixed
strings). The `TPU:` prefix  was stripped from the hardware-transcoding log
format strings in 1.43.4 while the non-TPU `Codecs: hardware transcoding: testing
API {}` format string is byte-identical in both (1.43.0 `@0x27311f`, 1.43.4
`@0x27cb57`). This is the refactor footprint on exactly the code path under test.

## Finding 4 — 1.43.4 tells the client it will use nvenc, then runs libx264

Two layers disagree inside the *same* server. `Plex Transcoder Statistics.log`
(`evidence/1434-variant-xml.txt`):

```xml
<Variant … transcodeHwRequested="1" transcodeHwDecoding="nvdec"
         transcodeHwEncoding="nvenc" transcodeHwFullPipeline="1"> … </Variant>
```

…while the job the server actually launches is `-codec:0 libx264`. So the
client-facing "can do nvenc" advertisement on 1.43.4 is not backed by the real
encoder selection — consistent with Finding 2 (probe skipped, advertisement built
from a different source).

## Finding 5 — the crack, the `.so`, and the injection are all *not* the variable

- Known-good `.so`, md5 `4d5dc96c8c7da383d84880b922935cd6`, loaded on both, via
  the same `patchelf --add-needed plexmediaserver_crack.so` graft.
- `libsoci_core.so` is **structurally identical across versions**: same size
  223,560 bytes, same 18 `NEEDED` entries, only the BuildID differs. The patchelf
  graft applies identically to both, and `patchelf --print-needed` on the
  `plex-test2` container confirms `plexmediaserver_crack.so` at the top of the
  list after boot.
- 1.43.4's container exposes `/dev/dri/card0` + `renderD128` and the crack script
  reports `✅ Crack applied inside container`.

Conclusion: the regression is **inside the 1.43.4 `Plex Media Server` binary**, on
the code path that decides whether to run the hardware capability probe. The
crack's "lie about feature state" strategy is not what is being defeated — the
gate has moved off the thing the crack patches, on this path.

## Binary targets retained this session

`work/bin/` holds `PMS-1.43.0`, `PMS-1.43.4`, `soci-1.43.0-clean.so`,
`soci-1.43.4.so`. Relevant addresses touched (for the next session):

| Item | 1.43.0 | 1.43.4 |
|---|---|---|
| `Codecs: hardware transcoding: testing API {}` fmt | str `0x27311f`, ref `0x10181fe` | str `0x27cb57` |
| `… which is using transcoder slot.  Used slots for %sis now %d` | str `0x214764`, ref `0x104f012` | str `0x21c39e`, ref `0x10c2960` |
| `FeatureManager::GetSingleton()` | `0xd9fe24` | `0xe04dfc` |
| `TPU: hardware transcoding: final decoder: %s, final encoder: %s` | str `0x1e8c3c` | str `0x1ef876` |
| `TPU: hardware transcoding: using hardware decode accelerator %s` | str `0x1e55d6` | str `0x1ec0fa` |

## Open next step (unchanged priority)

Diff the function that **calls** the `testing API {}` format string between the two
versions and find what gates entry into the probe loop. Everything above says the
probe function itself still exists in 1.43.4; the question is now "who stopped
calling it / what guard now returns early", which is a bounded disassembly diff at
`0x10181fe` (1.43.0) vs the equivalent site in 1.43.4.

## Incident note for the operator

The running prod container `plex` has `VERSION=docker` in its environment, which
`AGENTS.md` §2 warns against because Plex self-updates on boot past the pin. It did
**not** self-update this session (`/identity` still reports
`1.43.0.10492-121068a07-ls297`), but it remains a latent hazard: any future boot
with a published newer build will silently walk off the pinned version and
invalidate the A/B baseline. The `plex-test2` compose correctly sets
`VERSION=1.43.4.10903-e5521bd8c` instead.

---

## Session 2026-09-29 (later) — root cause narrowed to a missing library, not the crack

New this pass: the failure is visible **in the running process**, before any
transcode is requested. No disassembly is needed to see it.

## Method — read the live process maps

Both servers were left running with the same known-good crack `.so`. For each,
read `/proc/<pid>/maps` of the running `Plex Media Server` process (run the read
as the Plex user — root is refused `/proc/<pid>/maps`):

```sh
docker exec -u abc <container> bash -c '
  PID=$(pgrep -f "Plex Media Server" | head -1)
  grep -c plexmediaserver_crack /proc/$PID/maps
  grep -c libcuda              /proc/$PID/maps
  grep -oE "[^ ]*libnvidia[^ ]*" /proc/$PID/maps | sort -u'
```

## Result — what is actually mapped in each server

| Mapped into `Plex Media Server` | 1.43.0 (prod) | 1.43.4 (test) |
|---|---|---|
| `plexmediaserver_crack.so` | ✅ 5 segments | ✅ 5 segments |
| `libcuda.so.1` | ✅ 6 segments | ✅ 6 segments |
| `libnvidia-ml.so.1` | ✅ 3 segments | ❌ **absent** |
| `libnvidia-encode.so.1` | ✅ present | ❌ **absent** |

The crack is loaded on both. `libcuda.so.1` (the runtime driver) loads on both.
But **`libnvidia-encode.so.1` — the NVENC encoder library — is never loaded in
1.43.4**, and neither is `libnvidia-ml.so.1`.

No NVENC library in the process ⇒ no `testing h264_nvenc` log line ⇒ `nvenc`
never enters the encoder-candidate set ⇒ the transcode slot falls to `CPU` and
the encoder is `libx264`. The earlier "probe is skipped" observation is the
*symptom*; the missing library is the mechanism.

## Corroboration in the server log

Count of `nvidia|nvml|libcuda|nvenc|hardware transcode` lines in each server's
own `Plex Media Server.log`:

| | 1.43.0 (prod) | 1.43.4 (test) |
|---|---|---|
| matching lines | **12** | **0** |

1.43.4's log does not mention NVIDIA, NVENC, libcuda or hardware transcoding
**at all**. 1.43.0's shows the full sequence — `testing h264_nvenc (encoder)`,
`testing API nvenc for device 'pci:0000:01:00.0'`, `[FFMPEG] - Loaded lib:
libnvidia-encode.so.1`, `Loaded sym: NvEncodeAPICreateInstance`, and the real job
with `-init_hw_device cuda=cuda:pci:0000:01:00.0 … scale_cuda … -codec:0
h264_nvenc`.

## Binary check — the loader code is unchanged

The server binary's NVIDIA loader is byte-identical between builds. 1.43.4 does
call `dlopen("libcuda.so.1", RTLD_LAZY)` and the same 7-entry `dlsym` chain:

| | 1.43.0 | 1.43.4 |
|---|---|---|
| `dlopen(libcuda.so.1)` site | `0x10f1106` | `0x1165782` |
| next failure check | `0f 84 59 01 00 00` (`je`) | `0f 84 59 01 00 00` (`je`) |

`libnvidia-encode.so.1` appears as a string in **neither** binary — it is loaded
by the bundled FFmpeg (the `[FFMPEG] - Loaded lib:` lines come from the decoder /
transcoder plugin), not by the server. So the server-side loader is not where the
two builds differ; the FFmpeg/transcoder side is where `libnvidia-encode.so.1`
would have been pulled in and was not.

## String-level footprint (unchanged from the prior session, still relevant)

1.43.4 strips the `TPU:` prefix  from every hardware-transcode log format
string (`TPU: hardware transcoding: final decoder: %s, final encoder: %s` →
`hardware transcoding: final decoder: %s, final encoder: %s`), while the
`Codecs: hardware transcoding: testing API {} for device '{}' ({})` format
string is byte-identical in both (1.43.0 `@0x27311f`, 1.43.4 `@0x27cb57`), and
the emit-block around it is byte-identical (same guards on the `+0xb8` / `+0x3f`
bool fields, same `Log::GetSingleton` call, same line number `0x41` and level
`0xddd`). The refactor is on the logging and the FFmpeg-side library load, not on
the crack's patch target.

## What this means for the crack's strategy

The crack lies about feature entitlement (`is_feature_available` → `true`). That
lie still lands — `hwtranscode` is reported available and the crack is mapped and
running. What defeats it is downstream: with `libnvidia-encode.so.1` never
loaded, the hardware encoder does not exist as an option regardless of what the
entitlement check says. The gate that matters on 1.43.4 is the **library-load
gate feeding the encoder-candidate list**, and it is not the function the crack
patches.

## Next step (narrowed)

Find why 1.43.4's bundled FFmpeg/transcoder does not `dlopen`
`libnvidia-encode.so.1` in this container when 1.43.0's does. Candidate checks,
cheapest first:

1. Whether `libnvidia-encode.so.1` resolves at all inside the 1.43.4 container
   (it is present on disk — `/usr/lib/plexmediaserver/lib/libnvidia-encode.so.1`,
   297,688 bytes — so a bare "missing file" is ruled out; the question is what
   refuses to load it).
2. Whether the encoder-candidate list in 1.43.4 is built from a capability query
   that now returns "no encoder" before the load is attempted.
3. Whether the 1.43.4 FFmpeg build gates NVENC behind a configure/runtime flag
   the 1.43.0 build did not.

---

## Session 2026-09-30 — all three candidates above tested and killed; the gate is entitlement resolution, not the library load path

Raw evidence: `evidence/2026-09-30-nvenc-vs-ffmpeg-vs-featuremanager.txt` and
`evidence/2026-09-30-first-divergence.txt`. Live A/B reproduction and a fresh
`/proc/<pid>/maps` read of both running servers were both re-done this session.

## Result of the three candidate checks — all three are NO

1. **Capability query returning "no encoder" before the load** — **NO.**
   `avcodec_find_encoder_by_name("h264_nvenc")` returns `FOUND` in **both**
   containers when run against the container's own
   `/usr/lib/plexmediaserver/lib/libavcodec.so.60`. Both libavcodec copies
   contain `h264_nvenc`, `hevc_nvenc`, `nvenc.c`, `nvenc_hevc.c` and
   `NvEncodeAPICreateInstance`. The per-codec cache directories
   (`Codecs/74455c4-…` vs `Codecs/a336ba9-…`) are structurally identical —
   same file list, same sizes — and neither contains an NVENC module (NVENC is
   a driver library, not a Plex codec module).
2. **FFmpeg build-time gate** — **NO.** The `configuration:` string embedded in
   `Plex Transcoder` is **identical option-for-option** between builds (verified
   by extracting both and diffing the option set: zero unique options either
   side). Both carry `--enable-encoder=h264_nvenc`, `--enable-encoder=hevc_nvenc`,
   `--enable-cuda-llvm`, `--enable-hwaccel=av1_nvdec`, and the same
   `ffnvcodec/11.1.5.3-43d9170`. Only conan package *revisions* differ.
3. **Env / LD_LIBRARY_PATH / entrypoint lib-copy differences** — **NO.**
   `/proc/<pid>/environ` is comparable between the two servers (identical
   `NVIDIA_*`, `PLEX_*`, `NVIDIA_CTK_LIBCUDA_DIR`; only `VERSION` differs by
   design). Both have empty `LD_LIBRARY_PATH`. `ldconfig -p` resolves
   `libnvidia-encode.so.1`, `libnvcuvid.so.1` and `libcuda.so.1` to
   `/lib/...` in **both**. `ldd libnvidia-encode.so.1` resolves cleanly in
   both. PREFERENCES ARE IDENTICAL: the two `Preferences.xml` differ by exactly
   one unrelated key (`PubSubServerPing` 55 vs 64) and both carry
   `TranscoderHardwareAccelerated="1"`, `EnableHardwareEncoding="1"`,
   `HardwareDevicePath="10de:1be1:1043:13f0@0000:01:00.0"`.

## Fourth check (not in the list) — is the GPU actually enumerable? YES, in both

A direct dlopen/ctypes probe run **inside each container** (both as the Plex
user `abc` and as root) gives byte-identical results:

```
libcuda.so.1 dlopen=OK   libnvidia-encode.so.1 dlopen=OK
libnvidia-ml.so.1 dlopen=OK   libnvcuvid.so.1 dlopen=OK
cuInit(0)=0   cuDeviceGetCount=0 n=1
dev0 name=NVIDIA GeForce GTX 1070  pci=0000:01:00.0
encode: NvEncodeAPICreateInstance=OK  NvEncodeAPIGetMaxSupportedVersion=OK
```

So 1.43.4 *can* enumerate the GPU and *can* load NVENC. It simply never tries.

## Fresh `/proc/<pid>/maps` of the running servers (this session)

| mapped into `Plex Media Server` | 1.43.0 | 1.43.4 |
|---|---|---|
| `plexmediaserver_crack.so` | 5 segments | 5 segments |
| `libcuda.so.1` | 6 segments | 6 segments |
| `libnvidia-encode.so.1` | **3 segments** | **ABSENT** |
| `libnvcuvid.so.1` | **3 segments** | **ABSENT** |
| `libnvidia-ml.so.1` | ABSENT | ABSENT |
| total mapped regions | 545 | 392 |

Note: the earlier session's table listed `libnvidia-ml.so.1` as present (3 segs)
on 1.43.0. Re-read this session gives **ABSENT for nvml in both**. The nvml
mapping that session saw was most likely a transcoder *child*, not the server.
The correction does not change the conclusion: the two NVENC/NVDEC **device**
libraries are the only thing that differs between the servers.

## The disassembly is functionally identical on the whole probe path

Instruction-level comparison (normalising addresses/displacements/registers)
shows the probe code is the same in both builds:

| | 1.43.0 | 1.43.4 |
|---|---|---|
| probe-entry log emitter (`Codecs: testing %s %s%s`) | `0x101a0a3` | `0x108d8a5` |
| probe body (`av_hwdevice_ctx_create`) | `0x1018273` | `0x108b8f7` |
| "hardware transcoding: testing API …" emit | `0x10181fe` | `0x108b882` |
| final decoder/encoder emit site | `0x106e31f` | `0x10e1dc7` |
| CUDA loader `dlopen("libcuda.so.1")` | `0x10f10fa` | `0x1165776` |
| CUDA enumeration fn entry | `0x10f0db2` | `0x116542e` (2 callers each) |

The candidate-name string table consumed by the loop is identical in both:
`h264_nvenc`, `vc1_vaapi`, `_omx`, `_qsv`, `h264_mf`, `hevc_mf`, `ac3_mf`,
`eac3_eae`, `PLEX_MEDIA_SERVER_IS_KAMINO`. The dlsym chain is identical:
`cuInit, cuDeviceGetCount, cuDeviceGet, cuDeviceGetPCIBusId, cuDeviceGetName,
cuGetErrorString, cuDeviceGetLuid, cuDeviceGetAttribute, nvmlInit,
nvmlDeviceGetHandleByPciBusId, nvmlDeviceGetPciInfo_v2, nvmlErrorString,
nvmlShutdown`.

**The probe is byte-equivalent code that is simply never called on 1.43.4.**

## What actually changed — two structural diffs on the entitlement path

### (1) `FeatureManager` gained a `bool f(bool)` method

Symbols present **only** in 1.43.4:

```
N5boost3_bi6bind_tIbNS_4_mfi3mf1Ib14FeatureManagerbEENS0_5list2INS0_5valueIPS4_EENS7_IbEEEEEE
NSt3__26__bindIM14FeatureManagerFbbEJPS1_bEEE
NSt3__218__weak_result_typeIM14FeatureManagerFbbEEE
NSt3__215binary_functionIP14FeatureManagerbbEE
```

where 1.43.0 has only the void/void form:

```
N5boost3_bi6bind_tIvNS_4_mfi3mf0Iv14FeatureManagerEENS0_5list1INS0_5valueIPS4_EEEEEE
NSt3__26__bindIM14FeatureManagerFvvEJPS1_EEE
NSt3__218__weak_result_typeIM14FeatureManagerFvvEEE
NSt3__214unary_functionIP14FeatureManagervEE
```

`FeatureManager::f(void) -> void` became `FeatureManager::f(bool) -> bool`.
A predicate was added on the entitlement path in 1.43.4.

### (2) The features endpoint narrowed from "everything" to a five-GUID filter

```
1.43.0:  "%s/api/v2/server/users/features"
1.43.4:  "/api/v2/server/users/features?filterFeatures[]=b83c8dc9-5a01-4b7a-a7c9-5870c8a6e21b
                                          &filterFeatures[]=926bc176-58ca-47da-b8e3-080ed14ea6ba
                                          &filterFeatures[]=ea791163-c28d-4b7c-af88-bcc9553b206d
                                          &filterFeatures[]=6ab6677b-ad9b-444f-9ca1-b8027d05b3e1
                                          &filterFeatures[]=56cd352b-0d47-436d-aced-f20db3508de5"
```

1.43.4 also adds `/refreshFeatures`.

Resolving those five GUIDs against the **crack's own embedded 199-entry
GUID→name table**:

| GUID | name |
|---|---|
| `b83c8dc9-…` | `ios14-privacy-banner` |
| `926bc176-…` | `custom-home-removal` |
| `6ab6677b-…` | `client-radio-stations` |
| `ea791163-…` | (absent from the crack's table) |
| `56cd352b-…` | (absent from the crack's table) |

**Not one of them is a hardware-transcode feature.** The crack's table maps:

| name | GUID (in crack) | in server binary? |
|---|---|---|
| `hwtranscode` | `4742780c-af9d-4b44-bf5b-7b27e3369aa8` | no |
| `hardware_transcoding` | `84a754b0-d1ca-4433-af2d-c949bf4b4936` | no |
| `transcode-hevc` | `044a1fac-6b55-47d0-9933-25a035709432` | no |
| `transcode-tonemapping` | `0e2acda2-d70d-4df6-96e0-f63cf264d217` | no |

The server binaries contain the *names* `hwtranscode` and
`hardware_transcoding` in both builds but **never the GUIDs** — the GUIDs come
from the network response (`/api/v2/server/users/features`). 1.43.4 changed the
request to a narrowed, hard-coded filter that no longer includes the transcode
features.

### (3) TPU namespace refactor (footprint, not cause)

Decision-time tag moved `[Req#NN/Transcode]` → `[Req#NN/Transcode/TPU]`, and all
eight `TPU: hardware transcoding: …` format strings lost the `TPU:` prefix .
The emit **sites** survive (`0x106e31f` → `0x10e1dc7`), so the code is present
and simply never runs.

## The first divergence line, precisely

Anchor present in both:

```
[Req#X/Transcode] MDE: Selected protocol hls; container: mpegts
```

- 1.43.0's very next line: `Codecs: testing h264_nvenc (encoder)`
- 1.43.4's very next line: `Streaming Resource: Adding session … Used slots for CPUis now 1`

Seven lines of probe output exist in 1.43.0 and zero in 1.43.4. Everything
downstream follows deterministically. Full artefact:
`evidence/2026-09-30-first-divergence.txt`.

## Conclusion for this session

The 1.43.4 regression is **not** a library, loader, GPU-visibility, FFmpeg-build
or probe-code problem — every one of those was tested and is identical across the
two builds. The mechanism is **entitlement resolution**: 1.43.4 narrowed its
feature fetch to a hard-coded five-GUID filter that excludes the hardware
transcode features and gave `FeatureManager` a new `bool(bool)` predicate. The
crack patches the *local* `is_feature_available` / bitset layer, and on 1.43.4
that layer no longer gates the hardware path — so the capability probe is never
entered, `libnvidia-encode.so.1` / `libnvcuvid.so.1` are never dlopened, and the
transcode slot falls to `CPU`.

Porting the crack to 1.43.4 therefore requires more than a signature refresh: it
requires restoring the hardware-transcode entitlement at the layer 1.43.4 now
consults (the filtered `/api/v2/server/users/features` response and/or whatever
`FeatureManager::f(bool)` returns), which is a behavioural change, not an
address patch.

## Discriminating experiment (same day) — the gate is the CODE PATH, not the data

The remaining fork was: is the gate in the entitlement **data** the server is
given (fixable by supplying correct feature data), or in the 1.43.4 **code path**
that consumes it (not fixable by data)?

Method: copy prod's known-good entitlement caches
(`CloudUsersF.dat`, `CloudUsersServices.dat`, `CloudUsersV2.dat`, `Flags.dat`)
into `plex-test2`, restart, re-run the identical A/B request.

Result:

| | transcode slot | encoder |
|---|---|---|
| 1.43.0 (prod) | `10de:1be1:1043:13f0@0000:01:00.0` | `h264_nvenc` |
| 1.43.4 + **prod's entitlement caches installed** | `CPU` | `libx264` |

**Supplying prod's real entitlement data changed nothing.** Two corroborating
observations: 1.43.4 *overwrites* `Flags.dat` on startup (prod's copy came back
as the 1.43.4 value), and `CloudAccountV2.dat` is rewritten every boot — the
server regenerates these from its own code path rather than consuming external
ones.

Note also that `CloudUsersF.dat` was **already byte-identical** (`e8d36cad…`) on
both servers *before* this test — the primary cloud-features blob is the same on
the working and broken builds.

**Conclusion: the gate is the 1.43.4 code path.** Full artefact:
`evidence/2026-09-30-entitlement-data-vs-code-path.txt`.

## Third method — RO-pinning the file with prod's exact bytes (also negative)

Tested the "pin the good file read-only so the write fails" approach directly,
since it is strictly stronger than supplying a copy:

1. prod's `Flags.dat` (`e3cea60b…`, 9776 B) bind-mounted **read-only** over
   test2's target path (`mount --bind` + `-o remount,ro,bind`; `findmnt` confirms
   `ro`, `touch` returns `Read-only file system`).
2. Restarted test2, ran the standard A/B.

Result: the write failed exactly as intended and **harmlessly** —

```
WARN  - Failed to rename ".../Flags.dat.tmp.e75d48b3-…" to ".../Flags.dat": Resource busy
ERROR - SafelyWriteFile: failed to write over ".../Flags.dat": Rename failed
```

— server booted normally in 14 s, prod's bytes stayed pinned. **And the decision
did not change: still `Used slots for CPU is now 1` / `encoder=libx264`.**

So `Flags.dat`'s *content* is not an input to the transcode decision at all. The
server writes it via temp-file + rename, which is why an RO pin fails safely
rather than corrupting anything — useful if any future work needs to freeze Plex
state files.

Full artefact: `evidence/2026-09-30-ro-pinned-flags-dat.txt`.

**This is the third independent method (after cache-copy and the
derivation-fingerprint) confirming the gate is the 1.43.4 code path.** No
file-state manipulation can restore hardware transcoding.

## Still open

1. What exactly `FeatureManager::f(bool) -> bool` decides, and whether the
   transcode path consults it. Bounded disassembly at the 1.43.4 bind site.
   **This is now the only lead with a plausible port path.**
2. The two GUIDs absent from the crack's table (`ea791163-…`, `56cd352b-…`).
   Low value — they behave like client-UI flags and the experiment above shows
   feature data is not the gate.
3. Whether a legitimate Plex Pass account on 1.43.4 also loses hardware
   transcoding on this GPU. If it does, this is an upstream Plex bug and should
   be reported rather than worked around. (Answers "whose fault", not "can we
   port".)
