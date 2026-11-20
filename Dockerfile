# Prebuilt toolchain image for flutter-arm64-artifacts CI.
# Publish to GHCR with:
#   docker build -t ghcr.io/ani1nonly/flutter-arm64-artifacts:latest .
#   echo "$TOKEN" | docker login ghcr.io -u ani1nonly --password-stdin
#   docker push ghcr.io/ani1nonly/flutter-arm64-artifacts:latest
#
# Then in .github/workflows/build.yml set on both build jobs:
#   container:
#     image: ghcr.io/ani1nonly/flutter-arm64-artifacts:latest
# and remove the "Install host dependencies" step.

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl ca-certificates python3 python3-pip python3-setuptools \
      ninja-build pkg-config wget xz-utils unzip zip \
      openjdk-21-jdk-headless build-essential clang lld \
      libglib2.0-dev libgtk-3-dev libgl1-mesa-dev \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir -r requirements.txt

# depot_tools is baked in so gclient is ready immediately.
RUN git clone --depth 1 \
      https://chromium.googlesource.com/chromium/tools/depot_tools.git \
      /opt/depot_tools
ENV PATH="/opt/depot_tools:${PATH}"

WORKDIR /workspace
