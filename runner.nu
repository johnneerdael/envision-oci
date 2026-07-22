#!/home/linuxbrew/.linuxbrew/bin/nu
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2026 MatrixFurry <matrix@matrixfurry.com>

# Run Envision in a container with pre-installed build and runtime dependencies

use std/log

const default_image = "ghcr.io/johnneerdael/envision-oci:latest"

def main --wrapped [--help (-h), ...args] {
    let image = $env.ENVISION_OCI_IMAGE? | default $default_image
    let envision_args = if ($args | is-empty) {
        $args
    } else if ($args | first) == "--" {
        $args | skip 1
    } else {
        $args
    }

    try {
        do --capture-errors { podman pull $image } | tee {try {zenity --progress ...[
            --pulsate
            --auto-close
            --no-cancel
            "--title=Updating Envision"
            "--text=Downloading container image..."
        ]} catch {|e|
            log warning "Failed to launch Zenity, dialog will not be displayed."
            log debug $e.rendered
        }}
    } catch {|e|
        zerr $e.rendered $"Failed to download Envision image ($image)"
    }

    let uid = id -u
    let container_home = "/home" | path join ($env.HOME | path basename)
    let home = $env.HOME

    # I don't think we need `--device /dev/dri` since we already have `--volume /dev:/dev:rslave` and `run.oci.keep_original_groups`
    # We might still need `--gpus all` even if `--privileged` is enabled
    # Add `--privileged` if there are permission or perfomance issues that you cannot figure out
    # TODO: hardening
    #   remove `--privileged`
    #   --security-opt label=disable
    #   --security-opt apparmor=unconfined
    #   --volume /dev:/dev:rslave
    #   --volume /sys:/sys:rslave
    #   --gpus all
    #   maybe --device /dev/dri (see above)
    #   use dbus proxy for system and user sockets (xdg-dbus-proxy)
    try {
        podman run ...[
            --privileged
            --ipc host
            --pid host
            --ulimit host
            --network host
            --cap-add SYS_NICE
            --label "manager=envision-oci"
            --env "SHELL=bash"
            --env PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=($env.PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES? | default 1)
            --env $"HOME=($home)"
            --env DESKTOP_SESSION=($env.DESKTOP_SESSION? | default gnome)
            --env XDG_SESSION_DESKTOP=($env.XDG_SESSION_DESKTOP? | default gnome)
            --env XDG_SESSION_TYPE=($env.XDG_SESSION_TYPE? | default wayland)
            --env XAUTHORITY=($env.XAUTHORITY? | default "")
            --env XDG_CURRENT_DESKTOP=($env.XDG_CURRENT_DESKTOP? | default gnome)
            --env WAYLAND_DISPLAY=($env.WAYLAND_DISPLAY? | default wayland-0)
            --env GNOME_SETUP_DISPLAY=($env.GNOME_SETUP_DISPLAY? | default "")
            --env DISPLAY=($env.DISPLAY? | default :0)
            --env XDG_RUNTIME_DIR=($env.XDG_RUNTIME_DIR? | default /run/user/($uid))
            --env XDG_DATA_DIRS=($env.XDG_DATA_DIRS? | default "/usr/local/share:/usr/share")
            --env GDMSESSION=($env.GDMSESSION? | default "")
            --volume /tmp:/tmp:rslave
            --volume $"($home):($container_home):rslave"
            --volume $"/home/linuxbrew:/home/linuxbrew:rslave"
            --volume $"/run/user/($uid):/run/user/($uid):rslave"
            --volume $"/run/dbus/system_bus_socket:/run/dbus/system_bus_socket:rslave"
            --volume /etc/hosts:/etc/hosts:ro
            --volume /etc/resolv.conf:/etc/resolv.conf:ro
            --volume /etc/hostname:/etc/hostname:ro
            --runtime crun
            --annotation run.oci.keep_original_groups=1
            --userns keep-id
            --workdir $home
            --tty
            --rm
        ] $image ...$envision_args
    } catch {|e|
        zerr $e.rendered $"Envision-OCI failed using ($image)"
    }
}

def zerr [
    rendered_error: string
    message: string
] {
    log critical $message
    print $rendered_error

    try {
        let err = $'<span font_family="monospace">($rendered_error | ansi strip)</span>'
        zenity --error --no-wrap --title $message --text $"($err)\n\nSee log for more information."
    } catch {|e|
        log warning "Failed to launch Zenity, dialog will not be displayed."
        log debug $e.rendered
    }

    exit 1
}
