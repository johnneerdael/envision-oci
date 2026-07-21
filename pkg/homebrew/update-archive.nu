#!/usr/bin/env nu
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2026 MatrixFurry <matrix@matrixfurry.com>

const runner = path self ../../runner.nu
const assets = path self ../../assets/
const scripts = path self .

# Upload envision-oci package to GitLab for AtomicXR Homebrew
def main [
    --version (-v): string # envision-oci package version
    --token (-t): string # GitLab deploy token
] {
    let token = $token | default $env.DEPLOY_TOKEN?
    if ($token | is-empty) {
        error make {
            msg: "Either --token or $env.DEPLOY_TOKEN is required"
        }
    }

    if ($version | is-empty) and ($env.TANGLED_REF_NAME? | is-empty) {
        error make {
            msg: "Either --version or $env.TANGLED_REF_NAME is required"
        }
    }
    let version = if ($version | is-empty) {
        $env.TANGLED_REF_NAME | str substring 1..
    } else {$version}

    # Setup
    cd (mktemp -dt)
    mkdir pkg

    # Scripts
    install -m 755 $"($scripts)/install.nu" pkg/install.nu
    install -m 755 $"($scripts)/uninstall.nu" pkg/uninstall.nu
    install -m 755 $runner pkg/runner.nu

    # Assets
    open ($assets | path join "org.gabmus.envision.desktop")
    | str replace "@RUNNER_PATH@" $"/home/linuxbrew/.linuxbrew/bin/envision"
    | save pkg/org.gabmus.envision.desktop

    open ($assets | path join "org.gabmus.envision.Devel.desktop")
    | str replace "@RUNNER_PATH@" $"/home/linuxbrew/.linuxbrew/bin/envision"
    | save pkg/org.gabmus.envision.Devel.desktop

    cp ($assets | path join "org.gabmus.envision.svg") pkg/org.gabmus.envision.svg

    # Archive
    tar -C pkg -zcvf envision-oci.tar.gz .

    # Upload
    open --raw "envision-oci.tar.gz"
    | into binary
    | http put --content-type application/gzip $"https://gitlab.com/api/v4/projects/75293878/packages/generic/envision-oci/($version)/envision-oci.tar.gz" -H {DEPLOY-TOKEN: $token}
}
