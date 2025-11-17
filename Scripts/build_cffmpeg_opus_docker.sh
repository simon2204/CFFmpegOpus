#!/usr/bin/env bash

set -euo pipefail

SWIFT_IMAGE="${SWIFT_IMAGE:-swift:6.2.1}"
TRIPLE="${1:-x86_64-unknown-linux-gnu}"
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINER_WORKDIR="/work"

cat <<EOF
==> Building CFFmpegOpus artifact inside Docker
    Swift image : ${SWIFT_IMAGE}
    Target triple: ${TRIPLE}
    Repository   : ${REPO_ROOT}
EOF

docker run --rm \
    -v "${REPO_ROOT}:${CONTAINER_WORKDIR}" \
    -w "${CONTAINER_WORKDIR}" \
    --env TRIPLE="${TRIPLE}" \
    --env OPUS_VERSION \
    --env FFMPEG_VERSION \
    --env ARTIFACT_VERSION \
    --env JOBS \
    "${SWIFT_IMAGE}" \
    bash -lc "
        set -euo pipefail && \
        apt-get update >/dev/null && \
        DEBIAN_FRONTEND=noninteractive apt-get install -y \
            build-essential pkg-config yasm nasm autoconf automake libtool curl git python3 >/dev/null && \
        ./Scripts/build_cffmpeg_opus.sh \"\${TRIPLE}\" \
    "

echo "==> Completed. Updated artifacts should now exist under Artifacts/CFFmpegOpus.artifactbundle."
