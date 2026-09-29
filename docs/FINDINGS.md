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
