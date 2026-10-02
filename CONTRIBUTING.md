# Contributing

Thanks for helping. This repo is a documentation-and-tooling fork of
[`yuv420p10le/plexmediaserver_crack`](https://gitgud.io/yuv420p10le/plexmediaserver_crack).

**Upstream is the authority on the library.** It authors and publishes the
`.so`; this repo downloads it and never vendors or rebuilds it. Changes to how
the crack *works* belong upstream, not here — see
[Relationship to upstream](README.md#-relationship-to-upstream) for the split.

Bugs in *this* repo's tooling — the entrypoint, `crack_plex.sh`, the compose
example, the docs — belong here. The GitHub
[`gmh5225` mirror](https://github.com/gmh5225/plexmediaserver_crack) is not
upstream and carries no binaries; do not treat it as an alternative source.

**The most valuable thing you can contribute is a data point.** See
[Reporting a working configuration](#reporting-a-working-configuration).

## Before you open an issue

- Read [`docs/FINDINGS.md`](docs/FINDINGS.md). Several obvious hypotheses have
  already been tested and ruled out, and re-reporting one costs everyone time.
- Read [`AGENTS.md`](AGENTS.md) if you are contributing code — it lists the
  constraints that must not be broken, and the definition of done.
- "Hardware transcoding is not working" is not actionable on its own. Use the
  [hardware report form](https://github.com/bpawnzZ/plexmediaserver-crack/issues/new?template=hardware-report.yml),
  which asks for the fields that make it debuggable.

## Reporting a working configuration

Two ways, both useful:

- **It works for you** — open a
  [hardware report](https://github.com/bpawnzZ/plexmediaserver-crack/issues/new?template=hardware-report.yml)
  and note the result is a pass. It gets added to [`COMPATIBILITY.md`](COMPATIBILITY.md).
- **It does not work** — same form, with the failing log lines. The form's fields
  are chosen so the difference between a pass and a fail is visible without a
  round trip.

`COMPATIBILITY.md` is the repo's most load-bearing document. A single "works on
1.43.0" claim is an anecdote; the same claim from ten independent setups is a
fact people can rely on.

## Contributing code

```sh
make               # builds the .so in Alpine and verifies the musl linkage
```

Run it before opening a PR. Requirements: Docker, and nothing else.

Keep the diff minimal and on target. This codebase is small on purpose — it
patches one function. Do not add abstractions, configurability, or features that
were not asked for. See `AGENTS.md` for the constraints (musl build, no network
calls, keep the signature's wildcard byte) and the definition of done.

### Definition of done

A change is done when `make` passes **and** a real transcode through Plex Media
Server logs a GPU slot (`Used slots for 10de:…`) with `encoder=h264_nvenc`.
Testing by running `Plex Transcoder` directly proves nothing — it succeeds on
broken builds too.

State in your PR description which of those checks you ran, and paste the output.

## Reporting failed hypotheses

Open an issue or a discussion even when the answer is "that did not work". A
documented negative result is a real contribution here: it is the reason
`docs/FINDINGS.md` is worth reading. If you tested something and it failed, add
it to the *Ruled out* list with the evidence.

## Licensing

By contributing you agree your contribution is licensed under this repo's
[MIT license](LICENSE). There is no CLA — attribution to upstream plus the MIT
terms is enough.
