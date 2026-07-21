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
submodule_url=$(git config -f .gitmodules --get submodule.vendor/envision.url)
assert_equal "Envision submodule URL" "https://gitlab.com/gabmus/envision" "$submodule_url"
submodule_mode=$(git ls-files --stage vendor/envision | awk '{print $1}')
assert_equal "vendor/envision must be a gitlink" "160000" "$submodule_mode"
pinned_revision=$(git ls-files --stage vendor/envision | awk '{print $2}')
if [[ ! "$pinned_revision" =~ ^[0-9a-f]{40}$ ]]; then fail "pinned Envision revision is not a full Git commit: $pinned_revision"; fi
checked_out_revision=$(git -C vendor/envision rev-parse HEAD)
assert_equal "checked-out Envision revision" "$pinned_revision" "$checked_out_revision"
assert_contains Containerfile '^ARG FEDORA_VERSION=44$'
assert_contains Containerfile '^FROM fedora:\$\{FEDORA_VERSION\} AS builder$'
assert_contains Containerfile '^FROM fedora:\$\{FEDORA_VERSION\} AS dist$'
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
bash tests/verify-nushell-tools.sh
printf 'repository checks passed\n'
