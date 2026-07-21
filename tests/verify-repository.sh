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
if [[ ! "$pinned_revision" =~ ^[0-9a-f]{40}$ ]]; then fail "pinned Envision revision is not a full Git commit: $pinned_revision"; fi
checked_out_revision=$(git -C vendor/envision rev-parse HEAD)
assert_equal "checked-out Envision revision" "$pinned_revision" "$checked_out_revision"
printf 'repository checks passed\n'
