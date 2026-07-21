#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
image=${1:-envision-oci:test}
expected_revision=${2:-$(git -C "$repo_root/vendor/envision" rev-parse HEAD)}
expected_source=https://github.com/johnneerdael/envision-oci
base_version=$(awk -F '"' '/^version = "/ { print $2; exit }' "$repo_root/vendor/envision/Cargo.toml")
expected_version="${base_version}-${expected_revision:0:7}"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

[[ $(docker image inspect "$image" --format '{{.Os}}') == linux ]] || fail "$image is not a Linux image"
[[ $(docker image inspect "$image" --format '{{.Architecture}}') == amd64 ]] || fail "$image is not amd64"
[[ $(docker image inspect "$image" --format '{{json .Config.Entrypoint}}') == '["/opt/envision/bin/envision"]' ]] || fail "$image has the wrong entrypoint"
[[ $(docker image inspect "$image" --format '{{index .Config.Labels "org.opencontainers.image.source"}}') == "$expected_source" ]] || fail "$image has the wrong source label"
[[ $(docker image inspect "$image" --format '{{index .Config.Labels "io.github.johnneerdael.envision.revision"}}') == "$expected_revision" ]] || fail "$image has the wrong Envision revision label"

docker run --rm --platform linux/amd64 \
    --entrypoint /usr/bin/bash \
    --env "EXPECTED_VERSION=$expected_version" \
    "$image" -lc '
        set -euo pipefail
        test -x /opt/envision/bin/envision
        missing=$(ldd /opt/envision/bin/envision | grep "not found" || true)
        if [[ -n "$missing" ]]; then
            printf "%s\n" "$missing" >&2
            exit 1
        fi
        strings /opt/envision/bin/envision > /tmp/envision.strings
        grep -Fq -- "$EXPECTED_VERSION" /tmp/envision.strings
        test -L /var/home
        test "$(readlink /var/home)" = /home
        rpm -q envision-monado envision-xrizer >/dev/null
    ' || fail "$image failed runtime artifact checks (expected $expected_version)"

printf 'image checks passed: %s (%s, %s)\n' "$image" "$expected_revision" "$expected_version"
