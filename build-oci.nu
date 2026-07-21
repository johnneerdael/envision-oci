#!/usr/bin/env nu
# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightText: MatrixFurry <matrix@matrixfurry.com>

const name = "envision-oci"
const registry = "registry.gitlab.com"
const project = "matrixfurry/xr-packages"

const root = path self .
const registry_path = [$registry $project $name] | str join '/'

def main [
    --username (-u): string
    --token (-t): string
    --no-login (-l) # Use this if the machine is already authenticated with the container registry
] {
    let username = $username | default $env.CI_REGISTRY_USERNAME?
    let token = $token | default $env.CI_REGISTRY_PASSWORD?

    if ($username | is-empty) and not $no_login {
        error make {
            msg: "Username not provided"
            help: "Please provide a username with --username or $env.CI_REGISTRY_USERNAME"
        }
    }
    if ($token | is-empty) and not $no_login {
        error make {
            msg: "Token not provided"
            help: "Please provide a deployment token with --token or $env.CI_REGISTRY_PASSWORD"
        }
    }

    if not $no_login {podman login $registry -u $username -p $token}
    podman build -t $registry_path $root
    podman push $registry_path
}
