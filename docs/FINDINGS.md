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

| | Installed / known-good | Upstream GitHub source |
|---|---|---|
| Size | 9.9 MB | ~2 MB |
| Disassembler | **Zydis** | none |
| Functions hooked | 4: `is_feature_available`, `map_find`, `bitset_init`, `is_user_feature_set` | 1: `is_feature_available` |
| Embedded feature GUIDs | ~199 (incl. `hwtranscode`, `hardware_transcoding`, `transcode-hevc`, `transcode-tonemapping`) | 0 |

Because the larger variant also hooks the feature **bitset**
(`hook_bitset_init`, `hook_is_user_feature_set`), it patches entitlement at a
different layer than the single-function variant. Its source does not appear to
be published: the upstream gitgud repo returns 403 and the GitHub mirror has been
inactive since 2024.

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

# Session 2026-09-29/30 — controlled A/B reproduction, root cause isolated

All of the below is new, verified this session, on this host (workstation, GTX 1070
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
strings). The `TPU: ` prefix was stripped from the hardware-transcoding log
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
