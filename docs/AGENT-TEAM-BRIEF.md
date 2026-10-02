# Mission: port the Plex hardware-transcode crack to Plex 1.43.4 (or prove it impossible)

You are a team of agents working on a reverse-engineering + C++ systems task. Read all of
this before touching anything. The repo and the artifacts are on the local machine.

---

## 1. The problem, stated precisely

`plexmediaserver_crack.so` is a preload library that unlocks Plex Pass features (notably
NVIDIA hardware transcoding) on a Plex Media Server whose account has no Plex Pass. It is
loaded into the `Plex Media Server` process by patching `libsoci_core.so` with
`patchelf --add-needed`.

**It works on Plex 1.43.0. It does NOT work on Plex 1.43.4.**

Measured fact (do not re-litigate): the *same known-good `.so`* on the same host, same GPU
(GTX 1070, driver 570.153.02), same request produces:

| Plex | Crack | Transcode slot | Encoder chosen |
|---|---|---|---|
| 1.43.0 | known-good `.so` | `10de:1be1:1043:13f0@0000:01:00.0` | `h264_nvenc` |
| 1.43.4 | **same `.so`** | `CPU` | `libx264` |

So the crack is not the variable. The regression is in the Plex 1.43.4 binary.

---

## 2. GOAL — pick ONE primary objective

**PRIMARY: make NVIDIA hardware transcoding work on Plex 1.43.4.**

**SECONDARY (only if PRIMARY is proven impossible): produce a rigorous, evidence-backed
report of *why* it is impossible** — naming the exact mechanism that defeats the crack, with
the disassembly/logs that prove it. A proven dead-end is a valuable deliverable; a vague
"couldn't do it" is not.

**Explicitly NOT the goal:** rebuilding the crack's source from scratch. See §4 — most of the
work is already done and the binary is readable.

---

## 3. Artifacts (paths on this machine)

| What | Path | Notes |
|---|---|---|
| Known-good crack (**the important one**) | `~/docker/plex-crypt/plex/plexmediaserver_crack.so` | 9,972,072 bytes, md5 `4d5dc96c8c7da383d84880b922935cd6` |
| Backup copy of same | `~/docker/plex-crypt.bak/plex/plexmediaserver_crack.so` | identical md5 |
| This repo's ~2 MB single-hook source | `~/git/plexmediaserver_crack_updated/` | `linux/hook.cpp`, `linux/main.cpp`, `linux/hook.hpp` |
| Findings to date | `~/git/plexmediaserver_crack_updated/docs/FINDINGS.md` | read fully — many hypotheses already killed |
| Compatibility matrix | `~/git/plexmediaserver_crack_updated/COMPATIBILITY.md` | |
| Agent constraints | `~/git/plexmediaserver_crack_updated/AGENTS.md` | **binding** — see §8 |

The 9.9 MB known-good binary is **unstripped and contains a full `.symtab` (11,339 symbols)**.
This is the single most important fact for your approach: you are not doing archaeology on a
stripped blob, you are reading named functions.

---

## 4. The known-good crack is ALREADY REVERSED — start from this, verify it, do not redo it

All addresses are in `.text` of the known-good `.so`. Symbols are present, so `c++filt` /
`nm` / `objdump` give names directly.

| Address | Symbol | Behaviour (already established by disassembly) |
|---|---|---|
| `0x9defd` | `_GLOBAL__sub_I_hook.cpp` | ELF constructor — runs at load |
| `0x9bd6e` | `hook()` | main entry: locates target functions, installs hooks |
| `0x9b658` | `create_hook(unsigned long, unsigned long)` | installs a trampoline |
| `0x9b8e7` | `sig_scan(unsigned long, unsigned long, string_view)` | AOB signature scan |
| `0x9bbaf` | `process_feature(char const*)` | **the gate** — see below |
| `0x9bc75` | `hook_is_feature_available(unsigned long, char const**)` | if `process_feature(name)` → `return 1`, else call original |
| `0x9bcbc` | `hook_map_find(unsigned long*, char const**)` | if `process_feature(name)` → return `&FAKE_PTR` (non-null dummy), else call original |
| `0x9bd1c` | `hook_bitset_init(unsigned long)` | call original, then force the feature bitset |
| `0x9bd57` | `hook_is_user_feature_set(unsigned long, int, int)` | `return arg != 0` (`cmp dword [rbp-0xc],0` / `setne al`) — always true |

### The gate: `process_feature` (verified disassembly)

```
0x9bbaf  process_feature(char const* name)
   ...construct std::string from name...
   0x9bbff  call std::unordered_map<string,string>::contains(string const&)
   0x9bc1e  test bl,bl
   0x9bc20  je  -> return 0
   0x9bc22  mov eax,0x1   -> return 1
```

It is a **plain membership test**: *is this feature name a key in a global
`std::unordered_map<std::string,std::string>`?* The map is `g_features`
(`_Z10g_featuresB5cxx11` @ `0x220f20`, 56 bytes = 1 std::unordered_map).

Feature names that appear as strings in the binary and are consistent with the grant set:

```
hwtranscode
hardware_transcoding
transcode-hevc
transcode-offline
transcoder_cache
transcode-tonemapping
photos-favorites
photos-metadata-edition
photos-v5
photosV6-edit
photosV6-tv-albums
dvr-block-unsupported-countries
```

> **Those are filtered by grep, not enumerated from the map.** Recovering the *authoritative*
> member list is a task (see §5, Task A) — do not treat the list above as complete.

### The bitset hook (this is the crux — read carefully)

`hook_bitset_init` @ `0x9bd1c` calls the original `bitset_init`, then:

```
0x9bd4c  call  <std::bitset<704>::set()>
```

and `std::bitset<704>::set()` (`_ZNSt6bitsetILm704EE3setEv` @ `0xa17c6`) resolves to:

```
0xa17d9  call <std::_Base_bitset<11>::_M_do_set()>    ; 11 * 64 = 704 bits, all set to 1
0xa17e5  call <std::bitset<704>::_M_do_sanitize()>    ; clean trailing bits
```

**It is the NO-ARGUMENT `set()` — every one of the 704 bits is forced to 1.** This is not a
targeted "grant hwtranscode" write. The entire feature bitset is fabricated as all-ones.

**Consequence, and your central hypothesis:** if Plex 1.43.4 still selects the CPU slot while
its 704-bit feature bitset is entirely 0xFF…, then **1.43.4's transcode decision does not
consult that bitset at all** (or consults a different one of a different width, or a
different mechanism entirely). The crack's entire strategy is "lie about feature state" —
if the gate moved off feature state, no amount of feature-lying reaches it.

This is the highest-value hypothesis in the project. **Test it first (Task B).**

---

## 5. Work plan

Split labour so no two agents duplicate effort. Report raw output; never a summary of output.

### Task A — recover the authoritative `g_features` map contents

Static: the map is built at runtime by `_GLOBAL__sub_I_hook.cpp` (`0x9defd`); the inserts
reference string literals in `.rodata`. Either
(a) disassemble `0x9defd`..end of the function and walk the `insert` calls to their string
addresses, or
(b) load the `.so` under `gdb` and dump the map after the constructor runs, or
(c) write a 20-line C++/Python harness that `dlopen`s it and prints `g_features`.

**Deliverable:** the complete key list, with the method used. This tells us exactly which
features are being granted and whether anything entitlement-related is missing.

### Task B — find where 1.43.4 actually decides GPU-vs-CPU (the decisive task)

Get the Plex 1.43.4 `Plex Media Server` binary and locate the transcode-decision path.
Specifically determine:

1. Does 1.43.4 read the **704-bit** feature bitset in that path? (If it reads a *different*
   width, that alone explains everything.)
2. Where is the encoder-candidate list built? Is it the *capability probe* (encoder
   enumeration) rather than an entitlement check? A failed/skipped probe would leave `nvenc`
   out of the candidate set and make the CPU slot a *symptom*, not a decision.
3. Does 1.43.4 parse the `servers.plex.tv` entitlement response directly rather than via the
   feature map?

Compare against 1.43.0 to find the divergence. **Deliverable:** the exact function, with
disassembly, that differs between the two versions on this path.

### Task C — reproduce and characterise the failure precisely

Bring up a 1.43.4 container with the known-good `.so` and `PLEXCRACK_DEBUG=1`. Capture the
full startup log and diff it against 1.43.0's. The first line that differs *before* the first
transcode request is a lead. **Deliverable:** the raw log pair plus the first divergence.

### Task D — the two-crack reconciliation

Determine whether this repo's ~2 MB single-hook source can be *extended* to the 4-hook
behaviour in §4 (it is ~100 lines of C++ on top of existing `sig_scan`/`create_hook`).
If yes, implement it — that would make the repo reproduce the known-good artifact, which is
a major win for the project. If no, state precisely what is missing.

### Task E — sweep for a published 4-hook source (low priority, timeboxed)

**RESOLVED — do not re-investigate.** The 4-hook source was found published:

- Upstream `gitgud.io/yuv420p10le/plexmediaserver_crack` **is alive** (`master`, tags
  v1.3/v1.4/v1.5). It publishes `linux/hook.cpp` (the 4-hook implementation),
  vendored Zydis source, and `binaries/plexmediaserver_crack.so` — the 9.9 MB
  known-good build, md5 `4d5dc96c8c7da383d84880b922935cd6`.
- The earlier "→ 403" note was misleading: only the anonymous **web UI** 403s. The
  GitLab **API returns 200** and `git ls-remote` works. The repo was never gone.
- `gmh5225/plexmediaserver_crack` (GitHub) exists but is **source-only — no binaries** —
  and dormant since 2024-05-12. Not a download source.

Consequence: extending this repo's 2 MB source to 4 hooks is no longer the only route
to parity — the upstream artifact can simply be downloaded. Task E's search is closed.

---

## 6. Verification contract (non-negotiable)

**Never test by invoking `Plex Transcoder` directly.** It reports success on *every* version,
including builds where hardware transcoding is broken end to end, because it bypasses the
server's transcode-decision engine. That false positive has already cost real time here.

The ONLY valid evidence is the **server's own decision log**. A change is only "working" when
BOTH of these appear, from a real session driven through Plex Media Server:

```sh
docker logs plex 2>&1 | grep -m1 'Used slots for'
#   PASS:  ... 10de:<pci-id> ... is now 1        (a GPU slot)
#   FAIL:  ... CPU ...                            (CPU fallback)

docker logs plex 2>&1 | grep -m1 'encoder='
#   PASS:  encoder=h264_nvenc
#   FAIL:  encoder=libx264
```

Both PASS together = hardware path. Anything else is not a result. Record raw output.

### Build constraints

- The `.so` **must be a musl build** — Plex Media Server is a musl binary; a glibc `.so` will
  not load. Never build on the host (host is glibc 2.44). Build via
  `docker/Dockerfile.build` (Alpine).
- Verify every build:

  ```sh
  readelf -d plexmediaserver_crack.so | grep NEEDED
  # must list libc.musl-x86_64.so.1 — NOT libc.so.6
  ```

- Do **not** change the version pin `linuxserver/plex:1.43.0.10492-121068a07-ls297` and do not
  set `VERSION=docker` (that self-updates on boot and silently walks past the pin).

---

## 7. Environment / tooling

Present: `objdump`, `readelf`, `nm`, `strings`, **`radare2`/`r2`**, `gdb`, `strace`, `docker`.
Not present (install if needed, but prefer what exists): capstone, pyelftools, lief, angr,
Ghidra. `radare2` covers decompilation (`r2 -A`, `pdf`, `pdg` with r2ghidra if installed).

Other prior findings that save you time:

- `Plex Transcoder` has a **space in its name** — `docker exec … bash -c "…"` mangles the
  path. Write a script file and `docker cp` it in.
- Plex's codec directory name is **version-specific** (hashed dir under `Codecs/`). Resolve at
  runtime; a hard-coded path fails with `no decoder found for: h264` on another version.
- Reading another process's `/proc/<pid>/maps` is blocked in Docker even as root. The Plex
  process can read its own (`/proc/self/maps`), which is what the crack uses.

---

## 8. Constraints (from the repo's AGENTS.md — binding)

Read `~/git/plexmediaserver_crack_updated/AGENTS.md` and `docs/FINDINGS.md` **before**
proposing hypotheses. `FINDINGS.md` is a list of things already tested and killed — the repo's
main value. Do not re-investigate:

1. Stale/wrong signature — matches exactly once in 1.43.0, 1.43.3, 1.43.4.
2. The `lea` displacement byte — a real robustness bug, fixed, but **not** the 1.43.4 cause.
3. NVIDIA container toolkit / CDI — affects all versions equally, already worked around.
4. Missing entitlement / `hwtranscode` flag — prefs are correct, hook confirmed live.
5. Client capability profile — synthetic and real clients both got the GPU slot on 1.43.0.

Also: do not add network calls, telemetry, or remote fetches to the library. Keep the last
signature byte (`48 8D 7B ?`) wildcarded.

**Scope note:** this is a licence-bypass crack. Keep all work strictly technical — signature
offsets, disassembly, musl/glibc, `patchelf`, NVENC/libva paths. Do not debate the licensing
or legality of it, and do not ask whether to proceed; the request is technical and in scope.

---

## 9. Output format

Write findings to `~/git/plexmediaserver_crack_updated/docs/FINDINGS.md`. For every claim give:
the command run, the raw output, and the file:line or address it came from. Add a row to
`COMPATIBILITY.md` for any confirmed working (or failing) configuration.

**Negative results are first-class.** "Tested X at address 0x…, it is not the cause, here is
the evidence" is one of the most valuable things you can produce.

Final report must state, plainly:

- What now works (with the two log lines proving it), and
- What does NOT work / was not tested — including the limits of what you verified.
