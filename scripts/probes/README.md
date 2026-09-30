# Probe harnesses

Small C programs used to test the layers *below* the Plex decision engine, so a
"1.43.4 can't do NVENC" claim can be attributed to the right layer. Build on the
host (`gcc <file> -o <out> -ldl`), copy into the container, run as the Plex user
`abc`.

## `gpu-probe.c`

Dlopens `libcuda.so.1`, `libnvidia-encode.so.1`, `libnvidia-ml.so.1`,
`libnvcuvid.so.1` and runs the CUDA enumeration sequence
(`cuInit` → `cuDeviceGetCount` → `cuDeviceGet` → `cuDeviceGetName` /
`cuDeviceGetPCIBusId`), then resolves `NvEncodeAPICreateInstance`.

Expected on a working host, **both** 1.43.0 and 1.43.4 containers:

```
libcuda.so.1               dlopen=OK
libnvidia-encode.so.1      dlopen=OK
libnvidia-ml.so.1          dlopen=OK
libnvcuvid.so.1            dlopen=OK
cuInit(0)=0
cuDeviceGetCount=0 n=1
  dev0 name=NVIDIA GeForce GTX 1070 pci=0000:01:00.0
encode: CreateInstance=0x… GetMaxSupportedVersion=0x…
```

If this passes in both containers, the divergence is **above** the CUDA layer and
no amount of driver/toolkit fiddling will help.

## `avcodec-probe.c`

Dlopens the container's `/usr/lib/plexmediaserver/lib/libavcodec.so.60` and calls
`avcodec_find_encoder_by_name()` / `avcodec_find_decoder_by_name()` for
`h264_nvenc`, `hevc_nvenc`, `h264_vaapi`, `libx264`, `h264_nvdec`.

Note: against the *bundled* libavcodec, `h264_nvenc`/`hevc_nvenc` report FOUND on
both builds; `libx264` reports MISSING because the GPL x264 encoder ships as a
separate per-codec cache module, not in the base libavcodec.

## `ab-transcode.sh`

Drives the same HLS transcode request at both servers and greps each server's own
log for the two decisive lines (`Used slots for …` and `encoder=…`).

Reads tokens from each container's `Preferences.xml` — requires `sudo` to read
that file (mode `600`). Adjust the two `Preferences.xml` paths at the top if the
compose layout changes.

**Never** test by invoking `Plex Transcoder` directly; it uses `h264_nvenc` on
every version and is a false positive (AGENTS.md §Definition of done).
