# Pull request

## What does this change?

<!-- One or two sentences. If it fixes an issue, link it. -->

## Type

- [ ] Fix — the crack stops working on a Plex build
- [ ] Compatibility data — a report or matrix row
- [ ] Docs — setup, findings, or collaboration
- [ ] Build — the musl build or CI
- [ ] Other:

## Definition of done

A change to the library is only done when all three hold. Paste the raw output;
"I tested it" is not evidence.

- [ ] `make` passes, and `readelf -d plexmediaserver_crack.so | grep NEEDED` shows
      `libc.musl-x86_64.so.1` (not `libc.so.6`)
- [ ] A real transcode through Plex Media Server logs
      `Used slots for 10de:<pci-id> ... is now 1` — a GPU slot, not
      `Used slots for CPU`
- [ ] The same log shows `encoder=h264_nvenc` — not `encoder=libx264`

```
<paste the readelf output, the Used slots line, and the encoder= line here>
```

**Do not test by invoking `Plex Transcoder` directly.** It succeeds on builds
where hardware transcoding is broken end to end — the decision engine is where
the failure lives. That result is a false positive and has already cost time
once.

## If this touches the signature scan

- [ ] The last byte of the signature (`48 8D 7B ?`) is still wildcarded
- [ ] I checked `PLEXCRACK_DEBUG=1` output and `is_feature_available` is nonzero
      on at least one version
- [ ] If the scan missed on some build, I recorded which one and why in
      `docs/FINDINGS.md`

## Template for a compatibility row

```
| <Plex version> | `linuxserver/plex:<tag>` | <GPU> | <driver> | <crack variant + md5> | <result> | #<issue> |
```

## Anything the reviewer should know

<!-- Negative results welcome here too. -->
