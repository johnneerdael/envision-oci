<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- Copyright (c) 2026 MatrixFurry <matrix@matrixfurry.com> -->

# Envision-OCI #

> [!WARNING]
> Envision-OCI is unmaintained. Please use Envision + Monado from [Homebrew-XR](https://tangled.org/matrixfurry.com/homebrew-xr/) instead.

Envision-OCI allows builds inside [Envision](https://wiki.vronlinux.org/docs/fossvr/envision/) to work on any distro,
including Fedora Atomic Desktops and Bazzite, without manually installing any build dependencies.

## Installation ##

One-line install (using Homebrew): `bash -c "$(curl -fsSL https://tangled.org/matrixfurry.com/homebrew-xr/raw/main/scripts/setup.sh)" && brew install envision-oci`

Homebrew:
1. If you don't already have [Homebrew](https://brew.sh) and the [XR Tap](https://tangled.org/matrixfurry.com/homebrew-xr),
   follow the [setup instructions](https://tangled.org/matrixfurry.com/homebrew-xr#setup)
2. Install Envision-OCI: `brew install envision-oci`

Manual (not recommended):
1. Install [Nushell](https://nushell.sh) and [Podman](https://podman.io)
2. Clone this repo: `git clone --depth 1 https://tangled.org/matrixfurry.com/envision-oci`
3. Copy `runner.nu` to somewhere in your `PATH` and rename it to `envision`

## Usage ##

Launch and use Envision as normal, everything else will be handled for you automatically!
