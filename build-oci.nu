#!/usr/bin/env -S nu --stdin
# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightText: MatrixFurry <matrix@matrixfurry.com>

const name = "envision-oci"
const registry = "ghcr.io"
const project = "johnneerdael"

const root = path self .
const registry_path = [$registry $project $name] | str join '/'

def main [
    --username (-u): string
    --no-login (-l) # Use this if the machine is already authenticated with GHCR
] {
    let stdin_token = $in
    let username = $username | default $env.GHCR_USERNAME?
    let token = if $no_login {
        null
    } else if ($env.GHCR_TOKEN? | is-empty) {
        if (is-terminal --stdin) {
            input --suppress-output "GHCR token: "
        } else {
            $stdin_token | str trim
        }
    } else {
        $env.GHCR_TOKEN
    }

    if ($username | is-empty) and not $no_login {
        error make {
            msg: "Username not provided"
            help: "Provide --username or set $env.GHCR_USERNAME"
        }
    }
    if ($token | is-empty) and not $no_login {
        error make {
            msg: "Token not provided"
            help: "Set $env.GHCR_TOKEN or enter it at the prompt"
        }
    }

    if not $no_login {
        $token | podman login $registry --username $username --password-stdin
    }

    let image = $"($registry_path):latest"
    let envision_revision = do --capture-errors {
        git -C ($root | path join vendor envision) rev-parse HEAD
    } | str trim
    podman build --platform linux/amd64 --tag $image --build-arg $"ENVISION_REVISION=($envision_revision)" $root
    podman push $image
}
