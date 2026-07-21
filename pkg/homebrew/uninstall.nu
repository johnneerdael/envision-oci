#!/home/linuxbrew/.linuxbrew/bin/nu
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2026 MatrixFurry <matrix@matrixfurry.com>

def main [] {
    rm -f ~/.local/share/icons/hicolor/scalable/apps/org.gabmus.envision.svg
    rm -f ~/.local/share/applications/org.gabmus.envision.desktop
    rm -f ~/.local/share/applications/org.gabmus.envision.Devel.desktop
    update-desktop-database ~/.local/share/applications
    gtk4-update-icon-cache -t ~/.local/share/icons/hicolor
}
