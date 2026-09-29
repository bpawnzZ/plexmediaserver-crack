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

| Plex | Bound to fail | Evidence |
|---|---|---|
| **1.43.4** | Both the single-function and the Zydis crack | `Used slots for CPU` + `encoder=libx264` with the same `.so` that works on 1.43.0 |

The 1.43.4 regression is inside the Plex binary, not the crack. See
[`README.md` #cracking-the-newer-builds](README.md#-cracking-the-newer-builds) and
[`docs/FINDINGS.md`](docs/FINDINGS.md).

## Signature scan results

The crack's AOB signature matches exactly once on each build tested, so a
failing scan is not the reason for the 1.43.4 regression:

| Plex version | Signature hits | Notes |
|---|---|---|
| 1.43.0 | 1 ✅ | works |
| 1.43.3 | 1 ✅ | untested end-to-end |
| 1.43.4 | 1 ✅ | hook applies, hardware path still not taken |

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
