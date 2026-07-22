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

assert_output_contains() {
    local description=$1
    local output=$2
    local expected=$3

    if [[ "$output" != *"$expected"* ]]; then
        fail "$description: output does not contain '$expected'"
    fi
}

nushell_image=ghcr.io/nushell/nushell:0.114.1
nushell_bin=${NUSHELL_BIN:-}
nushell_mode=

if [[ -n "$nushell_bin" ]]; then
    [[ -x "$nushell_bin" ]] || fail "NUSHELL_BIN is not executable: $nushell_bin"
    nushell_mode=host
elif command -v nu >/dev/null 2>&1; then
    nushell_bin=$(command -v nu)
    nushell_mode=host
elif command -v docker >/dev/null 2>&1 && docker image inspect "$nushell_image" >/dev/null 2>&1; then
    nushell_mode=docker
else
    fail "Nushell is unavailable; install nu or pre-load $nushell_image"
fi

test_tmp=$(mktemp -d "${TMPDIR:-/tmp}/envision-oci-nushell.XXXXXX")
trap 'rm -r "$test_tmp"' EXIT
fake_bin=$test_tmp/bin
host_bin=$test_tmp/host-bin
podman_log=$test_tmp/podman.log
podman_stdin_log=$test_tmp/podman-stdin.log
mkdir -p "$fake_bin" "$host_bin"
export PODMAN_LOG=$podman_log
export PODMAN_STDIN_LOG=$podman_stdin_log

cat > "$fake_bin/podman" <<'EOF'
#!/bin/sh
set -eu

command_name=$1
shift
{
    printf '%s' "$command_name"
    for argument do
        printf '\t%s' "$argument"
    done
    printf '\n'
} >> "$PODMAN_LOG"

case "$command_name" in
    pull)
        if [ "${FAKE_PODMAN_PULL_FAIL:-}" = 1 ]; then
            printf 'mock pull failure\n' >&2
            exit 42
        fi
        printf 'mock pull success\n'
        ;;
    login)
        token=
        if ! IFS= read -r token; then
            :
        fi
        printf '%s' "$token" > "$PODMAN_STDIN_LOG"
        ;;
esac
EOF

cat > "$fake_bin/git" <<'EOF'
#!/bin/sh
set -eu

if [ "$1" = -C ] && [ "$3" = rev-parse ] && [ "$4" = HEAD ]; then
    printf '%s\n' "$EXPECTED_ENVISION_REVISION"
    exit 0
fi

printf 'unexpected mock git invocation\n' >&2
exit 2
EOF

chmod +x "$fake_bin/podman" "$fake_bin/git"

if [[ "$nushell_mode" == docker ]]; then
    cat > "$host_bin/nu" <<'EOF'
#!/bin/sh
set -eu

exec docker run --pull=never --rm --network none -i \
    -v "$NUSHELL_TEST_REPO_ROOT:/work:ro" \
    -v "$NUSHELL_TEST_TMP:/test" \
    -w /work \
    -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    -e PODMAN_LOG=/test/podman.log \
    -e PODMAN_STDIN_LOG=/test/podman-stdin.log \
    -e EXPECTED_ENVISION_REVISION \
    -e GHCR_TOKEN \
    "$NUSHELL_TEST_IMAGE" "$@"
EOF
    chmod +x "$host_bin/nu"
fi

expected_revision=$(git -C vendor/envision rev-parse HEAD)
export EXPECTED_ENVISION_REVISION=$expected_revision

run_nu_cli() {
    if [[ "$nushell_mode" == host ]]; then
        PATH="$fake_bin:$PATH" "$nushell_bin" "$@"
    else
        docker run --pull=never --rm --network none -i \
            -v "$repo_root:/work:ro" \
            -v "$test_tmp:/test" \
            -w /work \
            -e "PATH=/test/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
            -e PODMAN_LOG=/test/podman.log \
            -e PODMAN_STDIN_LOG=/test/podman-stdin.log \
            -e EXPECTED_ENVISION_REVISION \
            -e FAKE_PODMAN_PULL_FAIL \
            -e ENVISION_OCI_IMAGE \
            -e GHCR_USERNAME \
            -e GHCR_TOKEN \
            "$nushell_image" "$@"
    fi
}

run_nu() {
    run_nu_cli --no-config-file "$@"
}

run_build_executable() {
    PATH="$host_bin:$fake_bin:$PATH" \
        NUSHELL_TEST_REPO_ROOT="$repo_root" \
        NUSHELL_TEST_TMP="$test_tmp" \
        NUSHELL_TEST_IMAGE="$nushell_image" \
        ./build-oci.nu "$@"
}

reset_podman() {
    : > "$podman_log"
    : > "$podman_stdin_log"
    unset FAKE_PODMAN_PULL_FAIL ENVISION_OCI_IMAGE GHCR_USERNAME GHCR_TOKEN
}

read_podman_calls() {
    podman_calls=()
    while IFS= read -r podman_call; do
        podman_calls+=("$podman_call")
    done < "$podman_log"
}

nu_help=$(run_nu_cli --help)
if [[ "$nu_help" == *"--check"* ]]; then
    for script in runner.nu build-oci.nu pkg/homebrew/install.nu pkg/homebrew/uninstall.nu; do
        run_nu_cli --check "$script"
    done
fi

for script in runner.nu build-oci.nu pkg/homebrew/install.nu pkg/homebrew/uninstall.nu; do
    reset_podman
    help_output=$(run_nu "$script" --help)
    assert_output_contains "$script help" "$help_output" "Usage:"
    [[ ! -s "$podman_log" ]] || fail "$script --help invoked Podman"
done

default_image=ghcr.io/johnneerdael/envision-oci:latest
reset_podman
if ! run_nu runner.nu -- --first "two words" >/dev/null 2>&1; then
    fail "runner failed with the default image"
fi
read_podman_calls
assert_equal "default runner Podman call count" 2 "${#podman_calls[@]}"
assert_equal "default pull image" $'pull\tghcr.io/johnneerdael/envision-oci:latest' "${podman_calls[0]}"
IFS=$'\t' read -r -a run_call <<< "${podman_calls[1]}"
run_arg_count=${#run_call[@]}
(( run_arg_count >= 4 )) || fail "runner did not forward the expected arguments"
assert_equal "runner command" run "${run_call[0]}"
runner_args=$(printf '%s\n' "${run_call[@]}")
assert_output_contains "runner USB hotplug mount" "$runner_args" "/dev/bus/usb:/dev/bus/usb:rslave"
assert_equal "default run image" "$default_image" "${run_call[run_arg_count - 3]}"
assert_equal "first forwarded argument" --first "${run_call[run_arg_count - 2]}"
assert_equal "second forwarded argument" "two words" "${run_call[run_arg_count - 1]}"

override_image=example.invalid/envision:test
reset_podman
export ENVISION_OCI_IMAGE=$override_image
if ! run_nu runner.nu >/dev/null 2>&1; then
    fail "runner failed with ENVISION_OCI_IMAGE"
fi
read_podman_calls
assert_equal "override runner Podman call count" 2 "${#podman_calls[@]}"
assert_equal "override pull image" $'pull\texample.invalid/envision:test' "${podman_calls[0]}"
IFS=$'\t' read -r -a run_call <<< "${podman_calls[1]}"
run_arg_count=${#run_call[@]}
assert_equal "override run image" "$override_image" "${run_call[run_arg_count - 1]}"

reset_podman
export FAKE_PODMAN_PULL_FAIL=1
set +e
pull_failure_output=$(run_nu runner.nu 2>&1)
pull_failure_status=$?
set -e
[[ $pull_failure_status -ne 0 ]] || fail "runner succeeded after a failed pull"
assert_output_contains "failed pull" "$pull_failure_output" "Failed to download Envision image $default_image"
read_podman_calls
assert_equal "failed pull Podman call count" 1 "${#podman_calls[@]}"
assert_equal "failed pull command" $'pull\tghcr.io/johnneerdael/envision-oci:latest' "${podman_calls[0]}"

reset_podman
build_help=$(run_nu build-oci.nu --help)
if [[ "$build_help" == *"--token"* ]]; then
    fail "build-oci.nu exposes a secret-valued --token option"
fi

export GHCR_USERNAME=test-user
export GHCR_TOKEN=environment-secret
if ! build_output=$(run_nu build-oci.nu 2>&1); then
    fail "build helper failed with GHCR credentials: $build_output"
fi
read_podman_calls
assert_equal "build helper Podman call count" 3 "${#podman_calls[@]}"
assert_equal "login arguments" $'login\tghcr.io\t--username\ttest-user\t--password-stdin' "${podman_calls[0]}"
if [[ "$(< "$podman_log")" == *"$GHCR_TOKEN"* ]]; then
    fail "GHCR token appeared in Podman arguments"
fi
assert_equal "login token on stdin" "$GHCR_TOKEN" "$(< "$podman_stdin_log")"
expected_build_prefix=$'build\t--platform\tlinux/amd64\t--tag\tghcr.io/johnneerdael/envision-oci:latest\t--build-arg\tENVISION_REVISION='"$expected_revision"$'\t'
if [[ "${podman_calls[1]}" != "$expected_build_prefix"* ]]; then
    fail "build invocation does not include amd64, latest, and the Envision revision"
fi
assert_equal "push image" $'push\tghcr.io/johnneerdael/envision-oci:latest' "${podman_calls[2]}"

reset_podman
if ! build_output=$(printf 'prompt-secret\n' | run_build_executable --username test-user 2>&1); then
    fail "build helper failed to read a missing token securely: $build_output"
fi
if [[ "$(< "$podman_log")" == *"prompt-secret"* ]]; then
    fail "prompted GHCR token appeared in Podman arguments"
fi
assert_equal "prompted login token on stdin" prompt-secret "$(< "$podman_stdin_log")"

printf 'Nushell tool checks passed (%s)\n' "$nushell_mode"
