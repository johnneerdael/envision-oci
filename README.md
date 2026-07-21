<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- Copyright (c) 2026 MatrixFurry <matrix@matrixfurry.com> -->
<!-- Copyright (c) 2026 John Neerdael -->

# Envision-OCI

Envision-OCI is a maintained distribution of the official
[Envision](https://gitlab.com/gabmus/envision) application for x86_64 Bazzite and
other Fedora Atomic desktops. It runs Envision in a Fedora dependency container,
so Envision can build and configure Monado, xrizer, OpenComposite, and supported
tracking stacks without layering their development toolchains onto the host.

The container targets `linux/amd64` only. It is designed around the Podman and
host-integration behavior available on Bazzite/Fedora Atomic, rather than as a
general-purpose container for every Linux distribution.

## Requirements

- An x86_64 Bazzite or Fedora Atomic installation
- [Podman](https://podman.io/), including rootless containers
- [Homebrew](https://brew.sh/) with [Nushell](https://www.nushell.sh/) installed
- Git
- `$HOME/.local/bin` on `PATH`

Bazzite includes Podman. Install Nushell through Homebrew if it is not already
available:

```sh
brew install nushell
```

## Install

Clone the maintained repository and its Envision submodule, then install the
runner as `envision`:

```sh
git clone --recurse-submodules https://github.com/johnneerdael/envision-oci.git
cd envision-oci
install -Dm755 runner.nu "$HOME/.local/bin/envision"
```

Launch Envision normally:

```sh
envision
```

The runner pulls the selected image before every launch, passes through the host
display, device, and runtime paths Envision needs, and forwards additional
arguments to Envision. The temporary container is removed when Envision exits.

## Image channels

Images are published at `ghcr.io/johnneerdael/envision-oci`.

| Tag | Intended use |
| --- | --- |
| `latest` | Normal use. Built from the Envision revision pinned in this repository. |
| `sha-COMMIT` | Rollback and debugging for a particular Envision-OCI repository commit, for example `sha-0123456789abcdef0123456789abcdef01234567`. |
| `MAJOR.MINOR.PATCH` | A versioned Envision-OCI release. |
| `edge` | Early testing. Rebuilt nightly from the official Envision `main` branch. |

The installed runner defaults to
`ghcr.io/johnneerdael/envision-oci:latest`. Override it for the current Nushell
session to test edge:

```nu
$env.ENVISION_OCI_IMAGE = "ghcr.io/johnneerdael/envision-oci:edge"
envision
```

Or select an immutable rollback image:

```nu
$env.ENVISION_OCI_IMAGE = "ghcr.io/johnneerdael/envision-oci:sha-0123456789abcdef0123456789abcdef01234567"
envision
```

Return to the default channel by unsetting the override:

```nu
hide-env ENVISION_OCI_IMAGE
```

### Make the GHCR package public

GitHub Container Registry creates the first published package as private. After
the first successful workflow run, open the GitHub account and follow:

**Packages -> envision-oci -> Package settings -> Danger Zone -> Public**

Confirm the visibility change when GitHub prompts for it. Public images can be
pulled by Bazzite users without registry credentials.

## Local amd64 builds

Initialize the official upstream submodule and label the image with its exact
Envision revision:

```sh
git submodule update --init --recursive
ENVISION_REVISION=$(git -C vendor/envision rev-parse HEAD)
podman build \
  --platform linux/amd64 \
  --build-arg "ENVISION_REVISION=$ENVISION_REVISION" \
  --tag ghcr.io/johnneerdael/envision-oci:latest \
  .
```

`build-oci.nu` performs the same amd64 build and then pushes the `latest` tag.
Provide the GHCR username and enter the token at the helper's hidden prompt:

```sh
GHCR_USERNAME=johnneerdael ./build-oci.nu
```

For non-interactive use, set `GHCR_TOKEN` in the environment instead. In both
cases the helper passes the token to `podman login` over standard input. If
Podman is already authenticated separately, skip the helper's login step:

```sh
podman login ghcr.io
./build-oci.nu --no-login
```

## Updating the stable Envision pin

Stable images build the checked-in gitlink, while `edge` follows upstream
automatically. Review upstream changes before advancing the stable pin, then use
the fetched commit explicitly:

```sh
git -C vendor/envision fetch https://gitlab.com/gabmus/envision.git main
git -C vendor/envision checkout --detach FETCH_HEAD
bash tests/verify-repository.sh
git add vendor/envision
git commit -m "build: update pinned Envision revision"
```

Run a full local amd64 image build and smoke test before publishing an updated
pin.

## Compatibility audit

The old distribution intended to pin Envision at `373646a`. This maintained fork
starts at `aa84e48`. The upstream changes between those revisions add `/etc`
udev-rule detection, show setcap warnings at more accurate times, and correctly
ellipsize long profile names in the profile dropdown.

The older `373646a` revision already included after-stop XR plugin execution and
the environment fix for Proton 11 and Steam Linux Runtime 4. Those behaviors are
therefore preserved by the maintained pin; they are not new downstream patches.

Envision's built-in system profile uses `/usr`, which matches the Fedora package
layout used by the container for its packaged XR components. This audit describes
the compatibility baseline at the initial maintained pin; the `edge` channel is
the place to exercise later upstream changes before moving the stable gitlink.

## Credits and license

MatrixFurry created the
[original Envision-OCI distribution](https://tangled.org/matrixfurry.com/envision-oci).
John Neerdael maintains this GitHub fork and its GHCR publishing workflow.
Envision itself is maintained by GabMus and its upstream contributors.

The wrapper code and container scripts are licensed under `AGPL-3.0-only`. This
documentation is licensed under `CC-BY-SA-4.0`. The vendored Envision submodule
remains a separate upstream project under its own license.
