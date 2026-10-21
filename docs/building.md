# Building

Builds run in GitHub Actions. A Linux machine with Docker can reproduce them, but no build depends on a developer's machine.

## Workflows

| Workflow | Runs on | What it does |
|---|---|---|
| [`build.yml`](../.github/workflows/build.yml) | Pull requests, pushes to `main`, manual dispatch | Host-side tests; makes sure the toolchain image exists; cross-compiles, checks and packages the outputs |
| [`toolchain.yml`](../.github/workflows/toolchain.yml) | Called by `build.yml`; manual dispatch | Builds the GCCSDK toolchain image when no image exists for the current pins (one to two hours); otherwise does nothing |
| [`claude.yml`](../.github/workflows/claude.yml) | Issue and pull request comments mentioning `@claude` | Runs Claude Code on the request, for collaborators with write access |

Artifacts from a `build.yml` run:

- `TLTest-<commit>.zip`: the RISC OS test kit for Gate 1, uploaded unwrapped so the download is the RISC OS zip itself.
- `build-record`: `results.json`, compiler logs, the kit as a tree with `,xxx` filetype suffixes, and the emulator output.

## The toolchain image

`ghcr.io/kierennicolas/armtex_update/gccsdk:<tag>`, where the tag comes from `scripts/toolchain-image.sh`. [`architecture.md`](architecture.md#toolchain) explains the tag, the pins and the provenance record.

To change the toolchain, edit the pins in `upstream/manifest.json` (or the Dockerfile, or `scripts/build-toolchain.sh`) in a pull request. The new tag does not exist yet, so the pull request's build creates it.

After the first build of a new GCCSDK revision, copy `source-checksums.sha256` from the `toolchain-build-record` artifact to `toolchain/gccsdk/source-checksums.sha256` and commit it. That pins GCCSDK's own downloads for later builds. Because the checksum file is not part of the recipe hash, committing it does not trigger a rebuild.

## Reproducing a build locally

With Docker, and access to the image (it inherits this repository's visibility):

```
image=$(scripts/toolchain-image.sh | sed -n 's/^image=//p')
docker run --rm -v "$PWD:/work" -w /work "$image" scripts/build-toolchain-tests.sh out
docker run --rm -v "$PWD:/work" -w /work "$image" scripts/check-binaries.sh out
docker run --rm -v "$PWD:/work" -w /work "$image" scripts/package-testkit.sh out
```

To build the toolchain itself without CI, on Ubuntu 24.04 with GCCSDK's build dependencies installed (the list is in `toolchain.yml`):

```
git clone https://github.com/riscos-dot-info/gccsdk gccsdk
git -C gccsdk checkout "$(jq -r .toolchain.gccsdk.revision upstream/manifest.json)"
sudo mkdir -p /opt/riscos-gccsdk && sudo chown "$USER" /opt/riscos-gccsdk
scripts/build-toolchain.sh gccsdk toolchain-out
```

## Setting up the Claude Code workflow

A repository admin needs to do this once:

1. Install the Claude GitHub app on the repository: <https://github.com/apps/claude>.
2. Add a repository secret named `ANTHROPIC_API_KEY`, or `CLAUDE_CODE_OAUTH_TOKEN` (generated with `claude setup-token`).

Until then, `@claude` mentions start the workflow and it fails at the authentication step. Nothing else depends on it.
