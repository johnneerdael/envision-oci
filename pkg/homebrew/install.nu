#!/usr/bin/env nu
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2026 MatrixFurry <matrix@matrixfurry.com>

use std log

def main [staged_path: string] {
    cd $staged_path
    log info $"Installing from (pwd)"

    mkdir ~/.local/share/applications
    mkdir ~/.local/share/icons/hicolor/scalable/apps
    cp -f org.gabmus.envision.desktop ~/.local/share/applications/org.gabmus.envision.desktop
    cp -f org.gabmus.envision.Devel.desktop ~/.local/share/applications/org.gabmus.envision.Devel.desktop
    cp -f org.gabmus.envision.svg ~/.local/share/icons/hicolor/scalable/apps/org.gabmus.envision.svg

    update-desktop-database ~/.local/share/applications
    gtk4-update-icon-cache -t ~/.local/share/icons/hicolor
}
