# Compatibility matrix

Which Plex builds actually work, from real reports. Because Plex's own binary is
the variable that matters, one report proves nothing — several independent
reports on the same version do.

**Add your setup:** open a
[hardware report](https://github.com/bpawnzZ/plexmediaserver-crack/issues/new?template=hardware-report.yml).
Passes are as wanted as failures.

## Verified working

Click the Plex version to see the reports behind a row.

| Plex | Image tag | GPU | Driver | Crack | Result | Report |
|---|---|---|---|---|---|---|
| **1.43.0** | `linuxserver/plex:1.43.0.10492-121068a07-ls297` | GTX 1070 (10de:1be1) | 570.153.02 | Zydis variant, 9.9 MB, md5 `4d5dc96c8c7da383d84880b922935cd6` | ✅ `h264_nvenc` | [in-repo](docs/FINDINGS.md) |

## Verified broken

| Plex | Image tag | GPU | Driver | Crack | Result | Evidence |
|---|---|---|---|---|---|---|
| **1.43.4** | `linuxserver/plex:1.43.4.10903-e5521bd8c-ls326` | GTX 1070 (10de:1be1) | 570.153.02 | Zydis variant, 9.9 MB, md5 `4d5dc96c8c7da383d84880b922935cd6` | ❌ `Used slots for CPU` + `encoder=libx264` | [AB run](docs/FINDINGS.md#session-2026-092930--controlled-ab-reproduction-root-cause-isolated), `evidence/AB-decision.txt` |

Both the single-function and the Zydis crack fail on 1.43.4 with the **same `.so`**
that works on 1.43.0. The regression is inside the Plex binary, not the crack.
See [`README.md` #cracking-the-newer-builds](README.md#-cracking-the-newer-builds)
and [`docs/FINDINGS.md`](docs/FINDINGS.md).

### Why 1.43.4 fails — isolated mechanism (2026-09-30, refined)

The GPU is fully visible to 1.43.4 (`/proc/driver/nvidia/gpus/0000:01:00.0`,
`/dev/nvidia*`, `/dev/dri/*`, `nvidia-smi`, `libcuda.so.1` all present in the
container), yet 1.43.4 **never runs the hardware capability probe**. 1.43.0 logs
`Codecs: testing h264_nvenc (encoder)` and `Codecs: hardware transcoding: testing
API nvenc for device 'pci:0000:01:00.0'`; 1.43.4 logs **neither**, so `nvenc`
never enters the candidate set and the slot falls to `CPU`. The `CPU` slot is a
symptom of a skipped probe, not a CPU decision.

**The library/loader/FFmpeg/build layers are all exonerated** (each tested
2026-09-30, full detail in [`docs/FINDINGS.md`](docs/FINDINGS.md)):

- the `.so` files exist and `ldd`/`ldconfig` resolve them in **both** containers;
- `cuInit`/`cuDeviceGetCount` enumerate the GTX 1070 identically in **both**
  (`pci=0000:01:00.0`), and `NvEncodeAPICreateInstance` resolves in **both**;
- `avcodec_find_encoder_by_name("h264_nvenc")` returns `FOUND` in **both**;
- the `Plex Transcoder` build `configuration:` string is **identical
  option-for-option** between builds (`--enable-encoder=h264_nvenc` present in
  both);
- `Preferences.xml` is identical apart from one unrelated key;
- the whole probe code path (probe emitter, loop driver, CUDA dlopen+dlsym
  chain, hwdevice construction) is instruction-for-instruction equivalent.

**What actually changed is entitlement resolution**, and there are two structural
diffs, both new in 1.43.4:

1. `FeatureManager` gained a `bool`-returning, `bool`-taking method
   (`__bind<FeatureManager,bool(bool)>` exists only in 1.43.4, where 1.43.0 has
   only `__bind<FeatureManager,void()>`).
2. The feature fetch was narrowed from `%s/api/v2/server/users/features` to a
   hard-coded five-GUID `filterFeatures[]` request (plus `/refreshFeatures`).
   Those five GUIDs are `ios14-privacy-banner`, `custom-home-removal`,
   `client-radio-stations`, and two not in the crack's 199-entry table —
   **none of them is `hwtranscode`**.

So the crack patches the *local* `is_feature_available` / bitset layer, and on
1.43.4 that layer no longer gates the hardware path. The capability probe is
never entered, `libnvidia-encode.so.1` and `libnvcuvid.so.1` are never dlopened
(both are **absent** from the running 1.43.4 server's `/proc/<pid>/maps` while
present in 1.43.0's), and the slot falls to `CPU`.

Corroborating: the decision moved from the `Transcode` log namespace (1.43.0) to
`Transcode/TPU` (1.43.4), and the `TPU:` prefix was stripped from the
hardware-transcoding log format strings in 1.43.4 — a refactor footprint on
exactly this path. 1.43.4 also advertises `transcodeHwEncoding="nvenc"` to the
client while actually launching `Plex Transcoder … -codec:0 libx264`.

**Porting implication:** fixing 1.43.4 needs more than a refreshed signature. The
hardware-transcode entitlement has to be restored at the layer 1.43.4 now
consults — the filtered feature response and/or `FeatureManager`'s new
`bool(bool)` predicate. That is a behavioural change, not an address patch.

**Confirmed by experiment (2026-09-30):** the gate is the 1.43.4 *code path*, not
the entitlement *data*. Copying prod's known-good entitlement caches
(`CloudUsersF.dat`, `CloudUsersServices.dat`, `CloudUsersV2.dat`, `Flags.dat`)
into the 1.43.4 container and restarting changed nothing — it still decides
`Used slots for CPU is now 1` / `encoder=libx264`. 1.43.4 additionally
*overwrites* `Flags.dat` on startup, i.e. it regenerates its feature cache from
its own code path rather than consuming a supplied one. So no cache/account-data
workaround exists; only a behavioural patch to the server's entitlement handling
(`FeatureManager::f(bool)` and/or the narrowed `filterFeatures[]` request) can
restore hardware transcoding. `CloudUsersF.dat` was byte-identical across both
builds even before the test.

**Also tested and negative — RO-pinning (2026-09-30):** bind-mounting prod's
`Flags.dat` **read-only** over the 1.43.4 path (write reliably blocked;
`SafelyWriteFile: failed to write over "…/Flags.dat": Rename failed`) still
decides `Used slots for CPU is now 1` / `encoder=libx264`. So `Flags.dat`'s
content is not an input to the decision at all — it is derived output nothing
reads back. Note the server writes it temp-file + rename, so an RO pin fails
safely rather than corrupting state. No file-state manipulation (supply, pin, or
protect) can restore hardware transcoding.

## Signature scan results

The crack's AOB signature matches exactly once on each build tested, so a
failing scan is not the reason for the 1.43.4 regression:

| Plex version | Signature hits | Notes |
|---|---|---|
| 1.43.0 | 1 ✅ | works |
| 1.43.3 | 1 ✅ | untested end-to-end |
| 1.43.4 | 1 ✅ | hook applies, `libsoci_core.so` graft lands, hardware probe never runs |

`libsoci_core.so` is structurally identical across 1.43.0 and 1.43.4 (same
223,560-byte size, same 18 `NEEDED` entries, only BuildID differs), so the
`patchelf --add-needed` graft applies identically to both. Injection is not the
variable.

## Untested

| Plex version | Status |
|---|---|
| 1.43.1, 1.43.2 | untested — reports wanted |
| 1.43.5+ | untested — reports wanted |
| AMD (AMF) / Intel (Quick Sync) | untested — reports wanted |

## What makes a report verifiable

The report form asks for the fields that let someone reproduce or trust your
result:

- exact Plex version **and** image tag (a `latest` container is not a data point)
- `md5sum` of `plexmediaserver_crack.so` (proves the variable under test)
- GPU model and `nvidia-smi` driver version
- whether your account has a real Plex Pass
- the two decisive log lines: `Used slots for …` and `encoder=…`

Without the last two, a report cannot distinguish "the crack failed" from "Plex
changed its mind about this GPU".

## A note on `VERSION=docker`

If your container reports a Plex version you did not pin, check the `VERSION`
environment variable. `VERSION=docker` makes Plex self-update on boot, so the
version in your report will not be the version in your compose file.
