# Envision-OCI GHCR Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore a buildable official Envision source pin and publish maintained amd64 stable and edge images to GHCR for Bazzite users.

**Architecture:** Restore official gabmus/envision as a pinned submodule consumed by one Fedora 44 Containerfile. Validate pull requests without registry access, publish pinned main and version channels from the committed gitlink, and move only the nightly edge job to upstream main before building. Keep the Nushell launcher thin: it pulls the public GHCR image, permits an environment-based channel override, and forwards the existing host integration into Podman.

**Tech Stack:** Git submodules, Fedora 44, Docker/BuildKit, Podman, Nushell 0.114.1, GitHub Actions, GHCR, actionlint 1.7.12, Bash repository checks

---

## File Map

- .gitmodules — declare the official Envision submodule URL.
- vendor/envision — store the pinned official Envision gitlink, initially aa84e48.
- tests/verify-repository.sh — provide fast repository-level regression checks for source wiring, image configuration, publishing configuration, launcher defaults, and retired infrastructure.
- Containerfile — build official Envision and provide its Fedora 44 XR build/runtime environment.
- runner.nu — pull and run latest by default while allowing ENVISION_OCI_IMAGE to select edge or rollback images.
- build-oci.nu — build and optionally push the amd64 image to the personal GHCR namespace.
- pkg/homebrew/install.nu — retain the reusable package installer while updating it to current Nushell standard-library import syntax.
- .github/workflows/container.yml — validate pull requests and publish stable, semantic-version, SHA, and edge tags.
- README.md — document Bazzite installation, image channels, GHCR visibility, source updates, compatibility findings, and project attribution.
- .tangled/workflows/homebrew.yaml — remove the obsolete Tangled release workflow.
- pkg/homebrew/update-archive.nu — remove the uploader tied to MatrixFurry's GitLab project.

### Task 1: Restore the Official Envision Source Pin

**Files:**
- Create: tests/verify-repository.sh
- Modify: .gitmodules:1-3
- Create gitlink: vendor/envision

- [ ] **Step 1: Write the failing submodule regression check**

Create tests/verify-repository.sh with this complete content:

~~~bash
#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_equal() {
    local description=$1
    local expected=$2
    local actual=$3

    if [[ "$actual" != "$expected" ]]; then
        fail "$description: expected '$expected', got '$actual'"
    fi
}

assert_contains() {
    local file=$1
    local pattern=$2

    if ! grep -Eq "$pattern" "$file"; then
        fail "$file does not match required pattern: $pattern"
    fi
}

assert_not_contains() {
    local file=$1
    local pattern=$2

    if grep -Eq "$pattern" "$file"; then
        fail "$file contains forbidden pattern: $pattern"
    fi
}

assert_file_absent() {
    local file=$1

    if [[ -e "$file" ]]; then
        fail "$file must not exist"
    fi
}

submodule_url=$(git config -f .gitmodules --get submodule.vendor/envision.url)
assert_equal "Envision submodule URL" "https://gitlab.com/gabmus/envision" "$submodule_url"

submodule_mode=$(git ls-files --stage vendor/envision | awk '{print $1}')
assert_equal "vendor/envision must be a gitlink" "160000" "$submodule_mode"

pinned_revision=$(git ls-files --stage vendor/envision | awk '{print $2}')
if [[ ! "$pinned_revision" =~ ^[0-9a-f]{40}$ ]]; then
    fail "pinned Envision revision is not a full Git commit: $pinned_revision"
fi

checked_out_revision=$(git -C vendor/envision rev-parse HEAD)
assert_equal "checked-out Envision revision" "$pinned_revision" "$checked_out_revision"

printf 'repository checks passed\n'
~~~

Make it executable:

~~~bash
chmod 755 tests/verify-repository.sh
~~~

- [ ] **Step 2: Run the check and verify it fails**

Run:

~~~bash
bash tests/verify-repository.sh
~~~

Expected: exit 1 with:

~~~text
FAIL: vendor/envision must be a gitlink: expected '160000', got ''
~~~

- [ ] **Step 3: Add and pin the official submodule**

Run these commands individually:

~~~bash
git submodule add --force https://gitlab.com/gabmus/envision vendor/envision
git -C vendor/envision checkout --detach aa84e48e8de86dd12d62604340a29748b599d298
git add .gitmodules vendor/envision tests/verify-repository.sh
~~~

Expected:

~~~text
vendor/envision is staged with mode 160000 at aa84e48e8de86dd12d62604340a29748b599d298
~~~

- [ ] **Step 4: Run the check and verify it passes**

Run:

~~~bash
bash tests/verify-repository.sh
~~~

Expected:

~~~text
repository checks passed
~~~

- [ ] **Step 5: Commit the source restoration**

~~~bash
git commit -m "build: restore official Envision source"
~~~

### Task 2: Modernize the Fedora Image

**Files:**
- Modify: tests/verify-repository.sh
- Modify: Containerfile:1-41

- [ ] **Step 1: Add failing Containerfile assertions**

Add this helper after assert_not_contains in tests/verify-repository.sh:

~~~bash
assert_count() {
    local file=$1
    local pattern=$2
    local expected=$3
    local actual

    actual=$(grep -Ec "$pattern" "$file")
    assert_equal "$file match count for $pattern" "$expected" "$actual"
}
~~~

Add these assertions immediately before the final printf:

~~~bash
assert_contains Containerfile '^ARG FEDORA_VERSION=44$'
assert_contains Containerfile '^ARG ENVISION_REVISION=unknown$'
assert_contains Containerfile '^FROM fedora:\$\{FEDORA_VERSION\} AS builder$'
assert_contains Containerfile '^FROM fedora:\$\{FEDORA_VERSION\} AS dist$'
assert_contains Containerfile '^COPY \.git/modules/vendor/envision /tmp/envision-git$'
assert_contains Containerfile 'org\.opencontainers\.image\.source="https://github\.com/johnneerdael/envision-oci"'
assert_contains Containerfile 'io\.github\.johnneerdael\.envision\.revision="\$\{ENVISION_REVISION\}"'
assert_contains Containerfile 'dnf clean all'
assert_not_contains Containerfile 'fedora:latest'
assert_not_contains Containerfile 'tangled\.org/matrixfurry\.com/envision-oci'
assert_count Containerfile 'bzip2-devel' 1
~~~

- [ ] **Step 2: Run the checks and verify the first image assertion fails**

Run:

~~~bash
bash tests/verify-repository.sh
~~~

Expected: exit 1 reporting that Containerfile does not match ARG FEDORA_VERSION=44.

- [ ] **Step 3: Replace Containerfile with the Fedora 44 implementation**

Use this complete file:

~~~dockerfile
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2026 MatrixFurry <matrix@matrixfurry.com>

ARG FEDORA_VERSION=44
ARG ENVISION_REVISION=unknown

# Stage 1: Build Envision
FROM fedora:${FEDORA_VERSION} AS builder
ARG ENVISION_REVISION

RUN dnf -y builddep envision && \
    dnf -y group install development-tools && \
    dnf clean all

WORKDIR /build/envision
COPY vendor/envision /build/envision
COPY .git/modules/vendor/envision /tmp/envision-git
RUN rm -f .git && \
    mv /tmp/envision-git .git && \
    git -C / config --file /build/envision/.git/config --unset core.worktree && \
    test "$(git rev-parse HEAD)" = "${ENVISION_REVISION}"
RUN meson setup build -Dprefix="/opt/envision"
RUN ninja -C build
RUN ninja -C build install

# Stage 2: Create the distributable image
FROM fedora:${FEDORA_VERSION} AS dist

ARG ENVISION_REVISION

LABEL org.opencontainers.image.title="Envision-OCI Runtime" \
    org.opencontainers.image.description="Envision and XR build dependencies for Fedora Atomic and Bazzite" \
    org.opencontainers.image.source="https://github.com/johnneerdael/envision-oci" \
    org.opencontainers.image.licenses="AGPL-3.0-only" \
    org.opencontainers.image.authors="John Neerdael" \
    io.github.johnneerdael.envision.revision="${ENVISION_REVISION}"

COPY --from=builder /opt/envision /opt/envision

RUN dnf -y install \
    @development-tools \
    openxr-libs openvr-api \
    libuvc openhmd opencv onnxruntime librealsense opencv-video eigen3-devel \
    bc boost-devel bzip2-devel libepoxy-devel libxkbcommon-devel \
    yaml-cpp-devel ccache mold sqlite-devel \
    envision-monado \
    envision-xrizer \
    onnxruntime-devel \
    fmt-devel git-lfs glew-devel gtest-devel jq lz4-devel tbb-devel && \
    dnf -y builddep opencomposite && \
    dnf clean all

RUN ln -s /home /var/home

ENTRYPOINT ["/opt/envision/bin/envision"]
~~~

- [ ] **Step 4: Run fast image checks**

Run:

~~~bash
bash tests/verify-repository.sh
docker build --check --file Containerfile .
~~~

Expected: repository checks passed, followed by a successful Docker build check with exit 0.

- [ ] **Step 5: Commit the image update**

~~~bash
git add Containerfile tests/verify-repository.sh
git commit -m "build: update Fedora image for maintained Envision"
~~~

### Task 3: Retarget and Validate the Nushell Tools

**Files:**
- Modify: tests/verify-repository.sh
- Modify: runner.nu:7-30,80-82
- Modify: build-oci.nu:5-35
- Modify: pkg/homebrew/install.nu:5

- [ ] **Step 1: Add failing launcher and local-build assertions**

Add these assertions before the final printf in tests/verify-repository.sh:

~~~bash
assert_contains runner.nu '^use std/log$'
assert_contains runner.nu '^const default_image = "ghcr\.io/johnneerdael/envision-oci:latest"$'
assert_contains runner.nu 'ENVISION_OCI_IMAGE'
assert_contains runner.nu 'Failed to download Envision image'
assert_not_contains runner.nu 'registry\.gitlab\.com'
assert_not_contains runner.nu 'let gid ='

assert_contains build-oci.nu '^const registry = "ghcr\.io"$'
assert_contains build-oci.nu '^const project = "johnneerdael"$'
assert_contains build-oci.nu 'GHCR_USERNAME'
assert_contains build-oci.nu 'GHCR_TOKEN'
assert_contains build-oci.nu 'password-stdin'
assert_contains build-oci.nu 'platform linux/amd64'
assert_not_contains build-oci.nu 'CI_REGISTRY_'

assert_contains pkg/homebrew/install.nu '^use std/log$'
~~~

- [ ] **Step 2: Run the checks and verify the launcher assertion fails**

Run:

~~~bash
bash tests/verify-repository.sh
~~~

Expected: exit 1 reporting that runner.nu does not match use std/log.

- [ ] **Step 3: Update runner.nu**

Apply these exact changes:

~~~diff
-use std log
+use std/log

-const image = "registry.gitlab.com/matrixfurry/xr-packages/envision-oci:latest"
+const default_image = "ghcr.io/johnneerdael/envision-oci:latest"

 def main --wrapped [...args] {
+    let image = $env.ENVISION_OCI_IMAGE? | default $default_image
+
     try {
         podman pull $image | tee {try {zenity --progress ...[
@@
     } catch {|e|
-        zerr $e.rendered "Failed to download Envision"
+        zerr $e.rendered $"Failed to download Envision image ($image)"
     }

     let uid = id -u
-    let gid = id -g
     let container_home = "/home" | path join ($env.HOME | path basename)
@@
     } catch {|e|
-        zerr $e.rendered "Envision-OCI failed"
+        zerr $e.rendered $"Envision-OCI failed using ($image)"
     }
 }
~~~

Keep the existing Podman arguments and pass $image to both podman pull and podman run.

- [ ] **Step 4: Replace build-oci.nu with the GHCR implementation**

Use this complete file:

~~~nu
#!/usr/bin/env nu
# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightText: MatrixFurry <matrix@matrixfurry.com>

const name = "envision-oci"
const registry = "ghcr.io"
const project = "johnneerdael"

const root = path self .
const registry_path = [$registry $project $name] | str join '/'

def main [
    --username (-u): string
    --token (-t): string
    --no-login (-l) # Use this if the machine is already authenticated with GHCR
] {
    let username = $username | default $env.GHCR_USERNAME?
    let token = $token | default $env.GHCR_TOKEN?

    if ($username | is-empty) and not $no_login {
        error make {
            msg: "Username not provided"
            help: "Provide --username or set $env.GHCR_USERNAME"
        }
    }
    if ($token | is-empty) and not $no_login {
        error make {
            msg: "Token not provided"
            help: "Provide --token or set $env.GHCR_TOKEN"
        }
    }

    if not $no_login {
        $token | podman login $registry --username $username --password-stdin
    }

    let image = $"($registry_path):latest"
    podman build --platform linux/amd64 --tag $image $root
    podman push $image
}
~~~

- [ ] **Step 5: Update the retained Homebrew installer import**

Apply:

~~~diff
-use std log
+use std/log
~~~

in pkg/homebrew/install.nu.

- [ ] **Step 6: Run repository and Nushell parser checks**

Run:

~~~bash
bash tests/verify-repository.sh
docker run --rm -v "$PWD:/work" -w /work ghcr.io/nushell/nushell:0.114.1 --no-config-file runner.nu --help
docker run --rm -v "$PWD:/work" -w /work ghcr.io/nushell/nushell:0.114.1 --no-config-file build-oci.nu --help
docker run --rm -v "$PWD:/work" -w /work ghcr.io/nushell/nushell:0.114.1 --no-config-file pkg/homebrew/install.nu --help
docker run --rm -v "$PWD:/work" -w /work ghcr.io/nushell/nushell:0.114.1 --no-config-file pkg/homebrew/uninstall.nu --help
~~~

Expected: repository checks passed; every Nushell command prints help and exits 0 without invoking Podman or changing user files.

- [ ] **Step 7: Commit the launcher and local-build update**

~~~bash
git add runner.nu build-oci.nu pkg/homebrew/install.nu tests/verify-repository.sh
git commit -m "feat: use the maintained GHCR image"
~~~

### Task 4: Add GitHub Actions Validation and Publishing

**Files:**
- Create: .github/workflows/container.yml
- Modify: tests/verify-repository.sh

- [ ] **Step 1: Add failing workflow assertions**

Add this helper after assert_contains:

~~~bash
assert_contains_literal() {
    local file=$1
    local text=$2

    if ! grep -Fq "$text" "$file"; then
        fail "$file does not contain required text: $text"
    fi
}
~~~

Add these assertions before the final printf:

~~~bash
assert_contains .github/workflows/container.yml "^  schedule:$"
assert_contains_literal .github/workflows/container.yml "cron: '17 3 * * *'"
assert_contains_literal .github/workflows/container.yml "packages: write"
assert_contains_literal .github/workflows/container.yml "attestations: write"
assert_contains_literal .github/workflows/container.yml "id-token: write"
assert_contains_literal .github/workflows/container.yml "value=latest"
assert_contains_literal .github/workflows/container.yml "value=edge"
assert_contains_literal .github/workflows/container.yml "type=semver,pattern={{version}}"
assert_contains_literal .github/workflows/container.yml "type=sha,prefix=sha-,format=long"
assert_contains_literal .github/workflows/container.yml "file: Containerfile"
assert_contains_literal .github/workflows/container.yml "ENVISION_REVISION=${{ steps.source.outputs.revision }}"
assert_contains_literal .github/workflows/container.yml "actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803"
assert_contains_literal .github/workflows/container.yml "docker/setup-buildx-action@bb05f3f5519dd87d3ba754cc423b652a5edd6d2c"
assert_contains_literal .github/workflows/container.yml "docker/login-action@af1e73f918a031802d376d3c8bbc3fe56130a9b0"
assert_contains_literal .github/workflows/container.yml "docker/metadata-action@dc802804100637a589fabce1cb79ff13a1411302"
assert_contains_literal .github/workflows/container.yml "docker/build-push-action@53b7df96c91f9c12dcc8a07bcb9ccacbed38856a"
assert_contains_literal .github/workflows/container.yml "actions/attest@f7c74d28b9d84cb8768d0b8ca14a4bac6ef463e6"
~~~

- [ ] **Step 2: Run the checks and verify the workflow is missing**

Run:

~~~bash
bash tests/verify-repository.sh
~~~

Expected: exit 1 reporting that .github/workflows/container.yml does not match the required schedule pattern.

- [ ] **Step 3: Create the container workflow**

Create .github/workflows/container.yml with this complete content:

~~~yaml
name: Build and publish container image

on:
  pull_request:
  push:
    branches:
      - main
    tags:
      - "v*"
  schedule:
    - cron: "17 3 * * *"
  workflow_dispatch:
    inputs:
      channel:
        description: Image source channel to publish
        required: true
        default: pinned
        type: choice
        options:
          - pinned
          - edge

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

permissions:
  contents: read

jobs:
  validate:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    steps:
      - name: Check out the repository
        uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803 # v6
        with:
          submodules: recursive

      - name: Resolve pinned Envision revision
        id: source
        shell: bash
        run: |
          revision=$(git -C vendor/envision rev-parse HEAD)
          test -n "$revision"
          echo "revision=$revision" >> "$GITHUB_OUTPUT"

      - name: Set up Buildx
        uses: docker/setup-buildx-action@bb05f3f5519dd87d3ba754cc423b652a5edd6d2c # v4

      - name: Build without pushing
        uses: docker/build-push-action@53b7df96c91f9c12dcc8a07bcb9ccacbed38856a # v7
        with:
          context: .
          file: Containerfile
          platforms: linux/amd64
          push: false
          build-args: |
            ENVISION_REVISION=${{ steps.source.outputs.revision }}
          cache-from: type=gha,scope=container-pinned

  publish:
    if: github.event_name != 'pull_request'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
      attestations: write
      id-token: write
    steps:
      - name: Check out the repository
        uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803 # v6
        with:
          fetch-depth: 0
          submodules: recursive

      - name: Resolve Envision source
        id: source
        shell: bash
        run: |
          channel=pinned
          if [[ "$GITHUB_EVENT_NAME" == "schedule" ]]; then
            channel=edge
          fi
          if [[ "$GITHUB_EVENT_NAME" == "workflow_dispatch" ]]; then
            channel="${{ inputs.channel }}"
          fi

          if [[ "$channel" == "edge" ]]; then
            git -C vendor/envision fetch --depth=1 origin main
            git -C vendor/envision checkout --detach FETCH_HEAD
          fi

          revision=$(git -C vendor/envision rev-parse HEAD)
          test -n "$revision"
          echo "channel=$channel" >> "$GITHUB_OUTPUT"
          echo "revision=$revision" >> "$GITHUB_OUTPUT"

      - name: Set up Buildx
        uses: docker/setup-buildx-action@bb05f3f5519dd87d3ba754cc423b652a5edd6d2c # v4

      - name: Log in to GHCR
        uses: docker/login-action@af1e73f918a031802d376d3c8bbc3fe56130a9b0 # v4
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Generate image metadata
        id: meta
        uses: docker/metadata-action@dc802804100637a589fabce1cb79ff13a1411302 # v6
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          flavor: |
            latest=false
          tags: |
            type=raw,value=latest,enable=${{ steps.source.outputs.channel == 'pinned' && ((github.event_name == 'push' && github.ref == 'refs/heads/main') || github.event_name == 'workflow_dispatch') }}
            type=sha,prefix=sha-,format=long,enable=${{ steps.source.outputs.channel == 'pinned' && ((github.event_name == 'push' && github.ref == 'refs/heads/main') || github.event_name == 'workflow_dispatch') }}
            type=semver,pattern={{version}},enable=${{ startsWith(github.ref, 'refs/tags/v') }}
            type=semver,pattern={{major}}.{{minor}},enable=${{ startsWith(github.ref, 'refs/tags/v') }}
            type=semver,pattern={{major}},enable=${{ startsWith(github.ref, 'refs/tags/v') }}
            type=raw,value=edge,enable=${{ steps.source.outputs.channel == 'edge' }}
          labels: |
            org.opencontainers.image.source=https://github.com/${{ github.repository }}
            io.github.johnneerdael.envision.revision=${{ steps.source.outputs.revision }}

      - name: Build and push
        id: push
        uses: docker/build-push-action@53b7df96c91f9c12dcc8a07bcb9ccacbed38856a # v7
        with:
          context: .
          file: Containerfile
          platforms: linux/amd64
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          build-args: |
            ENVISION_REVISION=${{ steps.source.outputs.revision }}
          cache-from: type=gha,scope=container-${{ steps.source.outputs.channel }}
          cache-to: type=gha,mode=max,scope=container-${{ steps.source.outputs.channel }}

      - name: Attest image provenance
        uses: actions/attest@f7c74d28b9d84cb8768d0b8ca14a4bac6ef463e6 # v4
        with:
          subject-name: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          subject-digest: ${{ steps.push.outputs.digest }}
          push-to-registry: true
~~~

- [ ] **Step 4: Run repository checks and actionlint**

Run:

~~~bash
bash tests/verify-repository.sh
docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.12
~~~

Expected: repository checks passed and actionlint exits 0 without diagnostics.

- [ ] **Step 5: Commit the GitHub Actions workflow**

~~~bash
git add .github/workflows/container.yml tests/verify-repository.sh
git commit -m "ci: publish stable and edge images to GHCR"
~~~

### Task 5: Remove Retired Publishing and Rewrite User Documentation

**Files:**
- Modify: tests/verify-repository.sh
- Modify: README.md:1-28
- Delete: .tangled/workflows/homebrew.yaml
- Delete: pkg/homebrew/update-archive.nu

- [ ] **Step 1: Add failing retirement and documentation assertions**

Add these assertions before the final printf in tests/verify-repository.sh:

~~~bash
assert_file_absent .tangled/workflows/homebrew.yaml
assert_file_absent pkg/homebrew/update-archive.nu

assert_contains README.md '^# Envision-OCI$'
assert_contains_literal README.md 'ghcr.io/johnneerdael/envision-oci:latest'
assert_contains_literal README.md 'ghcr.io/johnneerdael/envision-oci:edge'
assert_contains_literal README.md 'ENVISION_OCI_IMAGE'
assert_contains_literal README.md 'aa84e48'
assert_contains_literal README.md 'Package settings'
assert_not_contains README.md 'Envision-OCI is unmaintained'
assert_not_contains README.md 'brew install envision-oci'

for active_file in Containerfile runner.nu build-oci.nu .github/workflows/container.yml; do
    assert_not_contains "$active_file" 'registry\.gitlab\.com'
done
~~~

- [ ] **Step 2: Run the checks and verify retired files are detected**

Run:

~~~bash
bash tests/verify-repository.sh
~~~

Expected:

~~~text
FAIL: .tangled/workflows/homebrew.yaml must not exist
~~~

- [ ] **Step 3: Delete infrastructure that cannot publish this fork**

Delete exactly these files:

~~~text
.tangled/workflows/homebrew.yaml
pkg/homebrew/update-archive.nu
~~~

Retain pkg/homebrew/install.nu and pkg/homebrew/uninstall.nu.

- [ ] **Step 4: Replace README.md with maintained-fork documentation**

Use this complete file:

~~~markdown
<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- Copyright (c) 2026 MatrixFurry <matrix@matrixfurry.com> -->
<!-- Copyright (c) 2026 John Neerdael -->

# Envision-OCI

Envision-OCI runs [Envision](https://gitlab.com/gabmus/envision) inside a Fedora container that already contains the dependencies needed to build Monado, xrizer, OpenComposite, and optional tracking components. It is intended for immutable Fedora systems such as Bazzite and Fedora Atomic desktops.

This repository maintains the OCI wrapper originally created by [MatrixFurry](https://tangled.org/matrixfurry.com/envision-oci). Envision itself remains an independent upstream project.

## Requirements

- An x86_64 Bazzite or Fedora Atomic installation
- [Podman](https://podman.io)
- [Homebrew](https://brew.sh) with [Nushell](https://www.nushell.sh)
- Git

Bazzite includes Podman. Install Nushell through Homebrew:

~~~bash
brew install nushell
~~~

## Installation

Clone the wrapper with its pinned Envision source and install the launcher:

~~~bash
git clone --recurse-submodules https://github.com/johnneerdael/envision-oci
cd envision-oci
install -Dm755 runner.nu "$HOME/.local/bin/envision"
~~~

Ensure $HOME/.local/bin is in PATH, then launch:

~~~bash
envision
~~~

The launcher pulls the selected public image before each run, mounts the host resources required by Envision, and removes the temporary container when Envision exits.

## Image Channels

| Tag | Envision source | Intended use |
| --- | --- | --- |
| latest | Envision revision pinned by this repository | Normal use |
| sha-COMMIT | Same pin as a specific wrapper commit | Rollback and debugging |
| MAJOR.MINOR.PATCH | Pin released by an Envision-OCI version tag | Versioned deployments |
| edge | Current official Envision main branch at the nightly build time | Early testing |

Use edge for one launch:

~~~bash
ENVISION_OCI_IMAGE=ghcr.io/johnneerdael/envision-oci:edge envision
~~~

For rollback, copy a sha-COMMIT tag from the package page and select it:

~~~bash
ROLLBACK_TAG=sha-0123456789abcdef0123456789abcdef01234567
ENVISION_OCI_IMAGE="ghcr.io/johnneerdael/envision-oci:$ROLLBACK_TAG" envision
~~~

Unset ENVISION_OCI_IMAGE to return to latest.

## GHCR Visibility

GitHub creates a new container package as private. After the first successful workflow:

1. Open the repository on GitHub.
2. Open Packages and select envision-oci.
3. Open Package settings.
4. Under Danger Zone, change package visibility to Public.

The launcher can then pull without registry credentials.

## Local Image Builds

Initialize the pinned source and resolve its revision:

~~~bash
git submodule update --init
ENVISION_REVISION=$(git -C vendor/envision rev-parse HEAD)
~~~

Build the amd64 image with Podman:

~~~bash
podman build --platform linux/amd64 --build-arg "ENVISION_REVISION=$ENVISION_REVISION" --tag ghcr.io/johnneerdael/envision-oci:latest .
~~~

The build-oci.nu helper can also log in and push. Set GHCR_USERNAME and GHCR_TOKEN, or pass --no-login after authenticating Podman separately.

## Updating the Stable Envision Pin

Fetch official upstream and move the submodule gitlink:

~~~bash
git -C vendor/envision fetch origin main
git -C vendor/envision checkout --detach FETCH_HEAD
bash tests/verify-repository.sh
git add vendor/envision
git commit -m "build: update the pinned Envision revision"
~~~

Review upstream changes and run the full verification sequence from the implementation plan before publishing.

## Compatibility Baseline

The previous wrapper intended to use Envision 373646a. The initial maintained pin is aa84e48 and adds:

- dependency detection for udev rules installed under /etc;
- more accurate setcap warnings;
- correct ellipsizing for long profile names.

The earlier pin already included after-stop XR plugins and the Proton 11/Steam Linux Runtime 4 environment fix. Official Envision keeps the system profile under /usr, which matches the Fedora packages inside this image.

## License

Envision-OCI is licensed under AGPL-3.0-only. Documentation is licensed under CC-BY-SA-4.0. Envision is licensed separately by its upstream project.
~~~

- [ ] **Step 5: Run documentation and repository checks**

Run:

~~~bash
bash tests/verify-repository.sh
git diff --check
~~~

Expected: repository checks passed; git diff --check exits 0.

- [ ] **Step 6: Commit the cleanup and documentation**

~~~bash
git add README.md tests/verify-repository.sh pkg/homebrew/install.nu pkg/homebrew/uninstall.nu
git add -u .tangled/workflows/homebrew.yaml pkg/homebrew/update-archive.nu
git commit -m "docs: document the maintained Bazzite distribution"
~~~

### Task 6: Perform Full amd64 Verification

**Files:**
- Verify: all implementation files
- Add if the full build exposes the expected headless version-check limitation: `tests/verify-image.sh`
- Change other files only when a command exposes a concrete defect, then rerun the affected task's checks before committing that correction.

- [ ] **Step 1: Run all fast checks from a clean index**

Run:

~~~bash
bash tests/verify-repository.sh
docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.12
docker run --rm -v "$PWD:/work" -w /work ghcr.io/nushell/nushell:0.114.1 --no-config-file runner.nu --help
docker run --rm -v "$PWD:/work" -w /work ghcr.io/nushell/nushell:0.114.1 --no-config-file build-oci.nu --help
docker run --rm -v "$PWD:/work" -w /work ghcr.io/nushell/nushell:0.114.1 --no-config-file pkg/homebrew/install.nu --help
docker run --rm -v "$PWD:/work" -w /work ghcr.io/nushell/nushell:0.114.1 --no-config-file pkg/homebrew/uninstall.nu --help
git diff --check
~~~

Expected: every command exits 0. The repository script prints repository checks passed; both containerized linters emit no error diagnostics.

- [ ] **Step 2: Build the complete pinned amd64 image**

Run:

~~~bash
ENVISION_REVISION=$(git -C vendor/envision rev-parse HEAD)
docker buildx build --platform linux/amd64 --file Containerfile --build-arg "ENVISION_REVISION=$ENVISION_REVISION" --tag envision-oci:test --load .
~~~

Expected: both Fedora stages complete successfully and Docker loads envision-oci:test as a linux/amd64 image.

- [ ] **Step 3: Verify the installed Envision artifact**

Run:

~~~bash
bash tests/verify-image.sh envision-oci:test "$ENVISION_REVISION"
~~~

Expected:

~~~text
image checks passed: envision-oci:test (aa84e48e8de86dd12d62604340a29748b599d298, 3.2.0-aa84e48)
~~~

The script checks the embedded version string, shared-library resolution, architecture, entrypoint, labels, packaged XR components, and `/var/home` link. Direct `envision --version` is not a valid headless smoke test because upstream initializes GTK before handling command-line options.

- [ ] **Step 4: Inspect architecture, entrypoint, and upstream revision metadata**

Run:

~~~bash
docker image inspect envision-oci:test --format '{{.Architecture}}'
docker image inspect envision-oci:test --format '{{json .Config.Entrypoint}}'
docker image inspect envision-oci:test --format '{{index .Config.Labels "io.github.johnneerdael.envision.revision"}}'
docker image inspect envision-oci:test --format '{{index .Config.Labels "org.opencontainers.image.source"}}'
~~~

Expected outputs, in order:

~~~text
amd64
["/opt/envision/bin/envision"]
aa84e48e8de86dd12d62604340a29748b599d298
https://github.com/johnneerdael/envision-oci
~~~

- [ ] **Step 5: Review the complete local change set**

Run:

~~~bash
git status --short --branch
git diff --check origin/main...HEAD
git diff --stat origin/main...HEAD
git log --oneline origin/main..HEAD
~~~

Expected: the branch is ahead only by the approved design, plan, and implementation commits; no unstaged implementation changes remain; diff checking exits 0; no credential file or unrelated source file appears.

## Operator Follow-up After Explicit Push Approval

Do not push from plan execution without explicit user authorization. After main is pushed:

1. Confirm the Build and publish container image workflow completes.
2. Confirm latest and sha-COMMIT exist under ghcr.io/johnneerdael/envision-oci.
3. Change the package visibility to Public through Package settings.
4. Pull latest from an unauthenticated environment.
5. Trigger the edge channel manually once and confirm its Envision revision label matches current official upstream main.
6. Allow the next nightly run to confirm the scheduled path.
