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

assert_literal() {
    local file=$1
    local text=$2

    if ! grep -Fq -- "$text" "$file"; then
        fail "$file does not contain required text: $text"
    fi
}

assert_block_literal() {
    local file=$1
    local required_block=$2

    if ! REQUIRED_BLOCK="$required_block" awk '
        BEGIN { needle = ENVIRON["REQUIRED_BLOCK"] }
        { contents = contents $0 ORS }
        END { exit(index(contents, needle) == 0) }
    ' "$file"; then
        fail "$file does not contain the required contiguous block"
    fi
}

assert_count() {
    local file=$1
    local pattern=$2
    local expected=$3
    local actual

    actual=$(awk -v pattern="$pattern" '
        { count += gsub(pattern, "&") }
        END { print count + 0 }
    ' "$file")
    assert_equal "$file match count for $pattern" "$expected" "$actual"
}

assert_file_absent() {
    local file=$1

    if [[ -e "$file" ]]; then
        fail "$file must not exist"
    fi
}

assert_file_present() {
    local file=$1

    if [[ ! -f "$file" ]]; then
        fail "$file must exist"
    fi
}

assert_job_contains() {
    local file=$1
    local job=$2
    local pattern=$3
    local section

    section=$(awk -v job="$job" '
        $0 == "  " job ":" { in_job = 1; next }
        in_job && $0 ~ /^  [[:alnum:]_-]+:$/ { exit }
        in_job { print }
    ' "$file")

    if ! grep -Eq "$pattern" <<<"$section"; then
        fail "$file job $job does not match required pattern: $pattern"
    fi
}

assert_job_not_contains() {
    local file=$1
    local job=$2
    local pattern=$3
    local section

    section=$(awk -v job="$job" '
        $0 == "  " job ":" { in_job = 1; next }
        in_job && $0 ~ /^  [[:alnum:]_-]+:$/ { exit }
        in_job { print }
    ' "$file")

    if grep -Eq "$pattern" <<<"$section"; then
        fail "$file job $job contains forbidden pattern: $pattern"
    fi
}

submodule_url=$(git config -f .gitmodules --get submodule.vendor/envision.url)
assert_equal "Envision submodule URL" "https://gitlab.com/gabmus/envision" "$submodule_url"
submodule_mode=$(git ls-files --stage vendor/envision | awk '{print $1}')
assert_equal "vendor/envision must be a gitlink" "160000" "$submodule_mode"
pinned_revision=$(git ls-files --stage vendor/envision | awk '{print $2}')
if [[ ! "$pinned_revision" =~ ^[0-9a-f]{40}$ ]]; then fail "pinned Envision revision is not a full Git commit: $pinned_revision"; fi
checked_out_revision=$(git -C vendor/envision rev-parse HEAD)
assert_equal "checked-out Envision revision" "$pinned_revision" "$checked_out_revision"
assert_contains Containerfile '^ARG FEDORA_VERSION=44$'
assert_contains Containerfile '^ARG ENVISION_REVISION=unknown$'
assert_count Containerfile '^ARG ENVISION_REVISION$' 2
assert_contains Containerfile '^FROM fedora:\$\{FEDORA_VERSION\} AS builder$'
assert_contains Containerfile '^FROM fedora:\$\{FEDORA_VERSION\} AS dist$'
assert_contains Containerfile '^COPY \.git/modules/vendor/envision /tmp/envision-git$'
assert_literal Containerfile 'git -C / config --file /build/envision/.git/config --unset core.worktree'
# This assertion intentionally contains literal Containerfile shell syntax.
# shellcheck disable=SC2016
assert_literal Containerfile 'test "$(git rev-parse HEAD)" = "${ENVISION_REVISION}"'
assert_contains Containerfile 'org\.opencontainers\.image\.source="https://github\.com/johnneerdael/envision-oci"'
assert_contains Containerfile 'io\.github\.johnneerdael\.envision\.revision="\$\{ENVISION_REVISION\}"'
assert_not_contains Containerfile 'fedora:latest'
assert_not_contains Containerfile 'https://tangled\.org/matrixfurry\.com/envision-oci'
assert_count Containerfile 'dnf clean all' 2
assert_count Containerfile 'bzip2-devel' 1
assert_contains runner.nu '^use std/log$'
assert_contains runner.nu '^const default_image = "ghcr\.io/johnneerdael/envision-oci:latest"$'
assert_contains runner.nu '^def main --wrapped \[--help \(-h\), \.\.\.args\] \{$'
assert_contains runner.nu 'ENVISION_OCI_IMAGE'
assert_contains runner.nu 'Failed to download Envision image'
assert_contains runner.nu '[-][-]volume /dev/bus/usb:/dev/bus/usb:rslave'
assert_not_contains runner.nu 'registry\.gitlab\.com'
assert_not_contains runner.nu 'let gid ='
assert_contains build-oci.nu '^const registry = "ghcr\.io"$'
assert_contains build-oci.nu '^const project = "johnneerdael"$'
assert_contains build-oci.nu 'GHCR_USERNAME'
assert_contains build-oci.nu 'GHCR_TOKEN'
assert_contains build-oci.nu 'password-stdin'
assert_contains build-oci.nu 'platform linux/amd64'
assert_contains build-oci.nu 'ENVISION_REVISION'
assert_not_contains build-oci.nu 'CI_REGISTRY_'
assert_not_contains build-oci.nu '\-\-token'
assert_contains pkg/homebrew/install.nu '^use std/log$'
assert_file_present pkg/homebrew/install.nu
assert_file_present pkg/homebrew/uninstall.nu
assert_file_present tests/verify-image.sh
if [[ ! -x tests/verify-image.sh ]]; then fail "tests/verify-image.sh must be executable"; fi
assert_file_absent .tangled/workflows/homebrew.yaml
assert_file_absent pkg/homebrew/update-archive.nu

assert_literal README.md '<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->'
assert_literal README.md 'https://gitlab.com/gabmus/envision'
assert_literal README.md 'ghcr.io/johnneerdael/envision-oci:latest'
assert_literal README.md 'ghcr.io/johnneerdael/envision-oci:edge'
assert_literal README.md 'sha-0123456789abcdef0123456789abcdef01234567'
assert_literal README.md 'MAJOR.MINOR.PATCH'
assert_literal README.md 'ENVISION_OCI_IMAGE'
assert_literal README.md 'Package settings'
assert_literal README.md 'Danger Zone'
assert_literal README.md 'Public'
assert_literal README.md 'linux/amd64'
assert_literal README.md 'x86_64'
assert_literal README.md 'Bazzite'
assert_literal README.md 'Fedora Atomic'
assert_literal README.md 'Bazzite includes Podman'
assert_literal README.md 'brew install nushell'
assert_literal README.md 'temporary container is removed'
assert_literal README.md 'aa84e48'
assert_literal README.md '373646a'
assert_literal README.md 'udev-rule detection'
assert_literal README.md 'setcap warnings at more accurate times'
assert_literal README.md 'ellipsize long profile names'
assert_literal README.md 'after-stop XR plugin execution'
assert_literal README.md 'Proton 11 and Steam Linux Runtime 4'
assert_literal README.md "system profile uses \`/usr\`"
assert_literal README.md 'git -C vendor/envision fetch https://gitlab.com/gabmus/envision.git main'
assert_literal README.md 'git -C vendor/envision checkout --detach FETCH_HEAD'
assert_literal README.md "ENVISION_REVISION=\$(git -C vendor/envision rev-parse HEAD)"
assert_literal README.md 'GHCR_USERNAME'
assert_literal README.md 'GHCR_TOKEN'
assert_literal README.md '--no-login'
assert_literal README.md 'AGPL-3.0-only'
assert_literal README.md 'CC-BY-SA-4.0'
assert_literal README.md 'MatrixFurry'
assert_literal README.md 'John Neerdael'
assert_literal README.md 'https://tangled.org/matrixfurry.com/envision-oci'
assert_not_contains README.md 'Envision-OCI is unmaintained'
assert_not_contains README.md 'brew install envision-oci'
assert_not_contains README.md 'git clone.*tangled\.org'
assert_not_contains README.md 'curl.*tangled\.org'
assert_not_contains README.md 'Homebrew-XR|homebrew-xr'
assert_not_contains README.md 'registry\.gitlab\.com'

for active_file in Containerfile runner.nu build-oci.nu .github/workflows/container.yml; do
    assert_not_contains "$active_file" 'registry\.gitlab\.com'
done

workflow=.github/workflows/container.yml
assert_file_present "$workflow"
assert_contains "$workflow" '^  pull_request:$'
assert_contains "$workflow" '^  push:$'
assert_contains "$workflow" '^      - main$'
assert_contains "$workflow" "^      - 'v\\*'$"
assert_contains "$workflow" '^  schedule:$'
assert_contains "$workflow" "^    - cron: '17 3 \\* \\* \\*'$"
assert_contains "$workflow" '^  workflow_dispatch:$'
assert_contains "$workflow" '^      source:$'
assert_contains "$workflow" '^        type: choice$'
assert_contains "$workflow" '^        default: pinned$'
assert_contains "$workflow" '^          - pinned$'
assert_contains "$workflow" '^          - edge$'
assert_job_contains "$workflow" validate "if: github\\.event_name == 'pull_request'"
assert_job_contains "$workflow" validate '^      contents: read$'
assert_job_not_contains "$workflow" validate 'docker/login-action@'
assert_job_not_contains "$workflow" validate 'attest'
assert_job_not_contains "$workflow" validate '^      packages: write$'
assert_job_not_contains "$workflow" validate '^          push: true$'
assert_job_contains "$workflow" validate '^          push: false$'
assert_job_contains "$workflow" publish "if: github\\.event_name != 'pull_request'"
assert_job_contains "$workflow" publish '^      contents: read$'
assert_job_contains "$workflow" publish '^      packages: write$'
assert_job_contains "$workflow" publish '^      attestations: write$'
assert_job_contains "$workflow" publish '^      id-token: write$'
assert_job_contains "$workflow" publish 'docker/login-action@'
assert_job_contains "$workflow" publish '^          push: true$'
assert_count "$workflow" 'submodules: true' 2
assert_job_contains "$workflow" publish '^          set -euo pipefail$'
source_selection_block=$(printf '%s\n' \
    "          if [[ \"\$EVENT_NAME\" == \"schedule\" ]]; then" \
    '            mode="edge"' \
    "          elif [[ \"\$EVENT_NAME\" == \"workflow_dispatch\" ]]; then" \
    "            mode=\"\$DISPATCH_SOURCE\"" \
    '          else' \
    '            mode="pinned"' \
    '          fi')
assert_block_literal "$workflow" "$source_selection_block"
assert_contains "$workflow" 'git -C vendor/envision fetch https://gitlab\.com/gabmus/envision\.git main$'
assert_contains "$workflow" 'git -C vendor/envision checkout --detach FETCH_HEAD$'
assert_contains "$workflow" 'git -C vendor/envision rev-parse HEAD'
stable_enable="\${{ steps.source.outputs.mode == 'pinned' && ((github.event_name == 'push' && github.ref == 'refs/heads/main') || github.event_name == 'workflow_dispatch') }}"
assert_literal "$workflow" "type=raw,value=latest,enable=$stable_enable"
assert_literal "$workflow" "type=sha,prefix=sha-,format=long,enable=$stable_enable"
assert_literal "$workflow" "type=semver,pattern={{version}},enable=\${{ github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v') }}"
assert_literal "$workflow" "type=semver,pattern={{major}}.{{minor}},enable=\${{ github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v') }}"
assert_literal "$workflow" "type=semver,pattern={{major}},enable=\${{ github.event_name == 'push' && startsWith(github.ref, 'refs/tags/v') }}"
assert_literal "$workflow" "type=raw,value=edge,enable=\${{ steps.source.outputs.mode == 'edge' }}"
assert_contains "$workflow" '^          flavor: latest=false$'
assert_contains "$workflow" 'org\.opencontainers\.image\.source=https://github\.com/johnneerdael/envision-oci'
assert_contains "$workflow" 'io\.github\.johnneerdael\.envision\.revision=\$\{\{ steps\.source\.outputs\.revision \}\}'
assert_count "$workflow" 'file: Containerfile' 2
assert_count "$workflow" 'platforms: linux/amd64' 2
assert_count "$workflow" 'ENVISION_REVISION=' 2
assert_job_contains "$workflow" validate '^          cache-from: type=gha,scope=container-pinned$'
assert_job_contains "$workflow" publish '^          cache-from: type=gha,scope=container-\$\{\{ steps\.source\.outputs\.mode \}\}$'
assert_job_contains "$workflow" publish '^          cache-to: type=gha,mode=max,scope=container-\$\{\{ steps\.source\.outputs\.mode \}\}$'
assert_job_contains "$workflow" publish 'actions/attest@f7c74d28b9d84cb8768d0b8ca14a4bac6ef463e6'
assert_not_contains "$workflow" 'actions/attest-build-provenance@'
assert_count "$workflow" 'actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803 # v6' 2
assert_count "$workflow" 'docker/setup-buildx-action@bb05f3f5519dd87d3ba754cc423b652a5edd6d2c # v4' 2
assert_count "$workflow" 'docker/build-push-action@53b7df96c91f9c12dcc8a07bcb9ccacbed38856a # v7' 2
assert_count "$workflow" 'docker/login-action@af1e73f918a031802d376d3c8bbc3fe56130a9b0 # v4' 1
assert_count "$workflow" 'docker/metadata-action@dc802804100637a589fabce1cb79ff13a1411302 # v6' 1
assert_count "$workflow" 'actions/attest@f7c74d28b9d84cb8768d0b8ca14a4bac6ef463e6 # v4' 1
bash tests/verify-nushell-tools.sh
printf 'repository checks passed\n'
