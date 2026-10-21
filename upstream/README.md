# Upstream pins

[`manifest.json`](manifest.json) records every external input the build uses. Build scripts read pins only from here.

| Key | Meaning |
|---|---|
| `toolchain.gccsdk` | GCCSDK repository and commit, the compiler release it builds, its target and install prefix, and the file holding SHA-256 checksums of the source archives GCCSDK downloads |
| `toolchain.image` | Where the toolchain image is published, and its base image (pinned by digest once `base_image_digest` is set) |
| `tools` | Other downloaded tools, each with a URL and SHA-256 checksum |
| `texlive` | TeX Live source and support-file snapshots; pinned in Milestone 2 |

Changing anything under `toolchain` changes the toolchain image tag, so the next build creates a new image. See [`docs/architecture.md`](../docs/architecture.md#toolchain).

Upstream source trees are never committed; they are fetched at the pinned revisions.
