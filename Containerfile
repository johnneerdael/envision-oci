# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2026 MatrixFurry <matrix@matrixfurry.com>

ARG FEDORA_VERSION=44

# Stage 1: Build Envision
FROM fedora:${FEDORA_VERSION} AS builder

RUN dnf -y builddep envision && \
    dnf -y group install development-tools && \
    dnf clean all

WORKDIR /build/envision
COPY vendor/envision /build/envision
RUN meson setup build -Dprefix="/opt/envision"
RUN ninja -C build
RUN ninja -C build install

# Stage 2: Create the distributable image
FROM fedora:${FEDORA_VERSION} AS dist

RUN dnf -y install \
    @development-tools \
    openxr-libs openvr-api \
    libuvc openhmd opencv onnxruntime librealsense opencv-video eigen3-devel \
    bc boost-devel bzip2-devel libepoxy-devel libxkbcommon-devel \
    yaml-cpp-devel ccache mold sqlite-devel \
    envision-monado \
    envision-xrizer \
    onnxruntime-devel \
    fmt-devel git-lfs glew-devel gtest-devel jq lz4-devel tbb-devel && \
    dnf -y builddep opencomposite && \
    dnf clean all

COPY --from=builder /opt/envision /opt/envision

ARG ENVISION_REVISION=unknown

LABEL org.opencontainers.image.title="Envision-OCI Runtime" \
    org.opencontainers.image.description="Envision and XR build dependencies for Fedora Atomic and Bazzite" \
    org.opencontainers.image.source="https://github.com/johnneerdael/envision-oci" \
    org.opencontainers.image.licenses="AGPL-3.0-only" \
    org.opencontainers.image.authors="John Neerdael" \
    io.github.johnneerdael.envision.revision="${ENVISION_REVISION}"

RUN ln -s /home /var/home

ENTRYPOINT ["/opt/envision/bin/envision"]
