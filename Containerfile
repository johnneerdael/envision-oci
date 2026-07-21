# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2026 MatrixFurry <matrix@matrixfurry.com>

# Stage 1: Build envision
FROM fedora:latest AS builder

RUN dnf builddep -y envision
RUN dnf group install -y development-tools

WORKDIR /build/envision
COPY vendor/envision /build/envision
RUN meson setup build -Dprefix="/opt/envision"
RUN ninja -C build
RUN ninja -C build install

# Stage 2: Create distributable image
FROM fedora:latest AS dist

LABEL org.opencontainers.image.title="Envision-OCI Runtime" \
    org.opencontainers.image.description="Runtime image for Envision-OCI" \
    org.opencontainers.image.source="https://tangled.org/matrixfurry.com/envision-oci" \
    org.opencontainers.image.licenses="AGPL-3.0-only" \
    org.opencontainers.image.authors="MatrixFurry <matrix@matrixfurry.com>"

COPY --from=builder /opt/envision /opt/envision

RUN dnf install -y \
    @development-tools \
    openxr-libs openvr-api \
    libuvc openhmd opencv onnxruntime librealsense opencv-video eigen3-devel \
    bc boost-devel bzip2-devel bzip2-devel libepoxy-devel libxkbcommon-devel \
    yaml-cpp-devel ccache mold sqlite-devel \
    envision-monado \
    envision-xrizer \
    onnxruntime-devel \
    fmt-devel git-lfs glew-devel gtest-devel jq lz4-devel tbb-devel
RUN dnf builddep -y opencomposite

RUN ln -s /home /var/home

ENTRYPOINT [ "/opt/envision/bin/envision" ]
