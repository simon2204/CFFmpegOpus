#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ARTIFACT_DIR="$REPO_ROOT/Artifacts/CFFmpegOpus.artifactbundle"
INCLUDE_SRC="$REPO_ROOT/Sources/CFFmpegOpus/include"
SHIM_SRC="$REPO_ROOT/Sources/CFFmpegOpus/src/shim.c"

OPUS_VERSION="${OPUS_VERSION:-1.5.2}"
FFMPEG_VERSION="${FFMPEG_VERSION:-n7.1}"
ARTIFACT_VERSION="${ARTIFACT_VERSION:-0.1.0}"

if command -v getconf >/dev/null 2>&1; then
    BUILD_JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN)}"
elif command -v sysctl >/dev/null 2>&1; then
    BUILD_JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"
else
    BUILD_JOBS="${JOBS:-1}"
fi

usage() {
    cat <<'EOF'
Usage: build_cffmpeg_opus.sh [TRIPLE]

Builds libopus and FFmpeg statically, bundles them together with the shim code
and updates Artifacts/CFFmpegOpus.artifactbundle for the specified target triple.

If TRIPLE is omitted the script tries to infer a sensible default for the host.
EOF
}

detect_triple() {
    local uname_s uname_m
    uname_s="$(uname -s)"
    uname_m="$(uname -m)"
    case "${uname_s}" in
        Darwin)
            if [[ "${uname_m}" == "arm64" ]]; then
                echo "arm64-apple-macosx"
            else
                echo "x86_64-apple-macosx"
            fi
            ;;
        Linux)
            case "${uname_m}" in
                x86_64) echo "x86_64-unknown-linux-gnu" ;;
                aarch64|arm64) echo "aarch64-unknown-linux-gnu" ;;
                *) echo "Unsupported architecture ${uname_m}" >&2; exit 1 ;;
            esac
            ;;
        *)
            echo "Unsupported platform ${uname_s}" >&2
            exit 1
            ;;
    esac
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

TRIPLE="${1:-$(detect_triple)}"

WORK_ROOT="$REPO_ROOT/.cffmpeg-build/${TRIPLE}"
SRC_DIR="$WORK_ROOT/src"
INSTALL_PREFIX="$WORK_ROOT/install"
mkdir -p "$SRC_DIR"
rm -rf "$INSTALL_PREFIX"
mkdir -p "$INSTALL_PREFIX"

download() {
    local url="$1"
    local dest="$2"
    curl -L --fail "$url" -o "$dest"
}

echo "==> Building Opus ${OPUS_VERSION} for ${TRIPLE}"
OPUS_TARBALL="$SRC_DIR/opus-${OPUS_VERSION}.tar.gz"
download "https://github.com/xiph/opus/releases/download/v${OPUS_VERSION}/opus-${OPUS_VERSION}.tar.gz" "$OPUS_TARBALL"
tar xf "$OPUS_TARBALL" -C "$SRC_DIR"
pushd "$SRC_DIR/opus-${OPUS_VERSION}" >/dev/null
./configure --prefix="$INSTALL_PREFIX" --disable-shared --enable-static >"$WORK_ROOT/opus-config.log"
make -j"$BUILD_JOBS" >/dev/null
make install >/dev/null
popd >/dev/null

echo "==> Building FFmpeg ${FFMPEG_VERSION} for ${TRIPLE}"
FFMPEG_TARBALL="$SRC_DIR/ffmpeg-${FFMPEG_VERSION}.tar.gz"
download "https://github.com/FFmpeg/FFmpeg/archive/refs/tags/${FFMPEG_VERSION}.tar.gz" "$FFMPEG_TARBALL"
tar xf "$FFMPEG_TARBALL" -C "$SRC_DIR"
pushd "$SRC_DIR/FFmpeg-${FFMPEG_VERSION}" >/dev/null
export PKG_CONFIG_PATH="$INSTALL_PREFIX/lib/pkgconfig"
COMMON_FLAGS="-I$INSTALL_PREFIX/include"
COMMON_LDFLAGS="-L$INSTALL_PREFIX/lib"
./configure \
    --prefix="$INSTALL_PREFIX" \
    --disable-shared --enable-static \
    --disable-doc --disable-programs --disable-ffplay --disable-ffprobe \
    --disable-debug --disable-autodetect --enable-small \
    --pkg-config-flags=--static \
    --extra-cflags="$COMMON_FLAGS" \
    --extra-ldflags="$COMMON_LDFLAGS" \
    --extra-libs="-lpthread -lm" \
    --enable-libopus \
    --enable-decoder=libopus --enable-encoder=libopus \
    --enable-decoder=aac --enable-decoder=mp3 --enable-decoder=vorbis --enable-decoder=flac \
    --enable-demuxer=matroska --enable-demuxer=matroska_audio --enable-demuxer=mov \
    --enable-demuxer=ogg --enable-demuxer=wav --enable-demuxer=mp3 \
    --enable-parser=opus --enable-parser=mpegaudio \
    --enable-swresample --enable-avfilter --enable-avdevice --enable-avcodec --enable-avformat --enable-swscale \
    >"$WORK_ROOT/ffmpeg-config.log"
make -j"$BUILD_JOBS" >/dev/null
make install >/dev/null
popd >/dev/null

echo "==> Building shim"
SHIM_OBJ="$WORK_ROOT/CFFmpegOpusShim.o"
${CC:-cc} -c "$SHIM_SRC" -I"$INCLUDE_SRC" -I"$INSTALL_PREFIX/include" -o "$SHIM_OBJ"

mkdir -p "$ARTIFACT_DIR/lib"
if [[ "$TRIPLE" == "arm64-apple-macosx" ]]; then
    LIB_OUTPUT="$ARTIFACT_DIR/lib/libCFFmpegOpus.a"
else
    mkdir -p "$ARTIFACT_DIR/lib/$TRIPLE"
    LIB_OUTPUT="$ARTIFACT_DIR/lib/$TRIPLE/libCFFmpegOpus.a"
fi

echo "==> Creating combined static library at ${LIB_OUTPUT}"
LIBS=(
    "$INSTALL_PREFIX/lib/libavformat.a"
    "$INSTALL_PREFIX/lib/libavcodec.a"
    "$INSTALL_PREFIX/lib/libavutil.a"
    "$INSTALL_PREFIX/lib/libswresample.a"
    "$INSTALL_PREFIX/lib/libswscale.a"
    "$INSTALL_PREFIX/lib/libavfilter.a"
    "$INSTALL_PREFIX/lib/libavdevice.a"
    "$INSTALL_PREFIX/lib/libopus.a"
)

UNAME_S="$(uname -s)"
if [[ "$UNAME_S" == "Darwin" ]]; then
    /usr/bin/libtool -static -o "$LIB_OUTPUT" "$SHIM_OBJ" "${LIBS[@]}"
else
    SHIM_LIB="$WORK_ROOT/libShim.a"
    ${AR:-ar} rcs "$SHIM_LIB" "$SHIM_OBJ"
    cat <<EOF | ${AR:-ar} -M
CREATE $LIB_OUTPUT
ADDLIB $SHIM_LIB
ADDLIB ${LIBS[0]}
ADDLIB ${LIBS[1]}
ADDLIB ${LIBS[2]}
ADDLIB ${LIBS[3]}
ADDLIB ${LIBS[4]}
ADDLIB ${LIBS[5]}
ADDLIB ${LIBS[6]}
ADDLIB ${LIBS[7]}
SAVE
END
EOF
    ${RANLIB:-ranlib} "$LIB_OUTPUT"
fi

if command -v strip >/dev/null 2>&1; then
    if [[ "$UNAME_S" == "Darwin" ]]; then
        strip -S -x "$LIB_OUTPUT"
    else
        strip --strip-debug "$LIB_OUTPUT" || true
    fi
fi

echo "==> Refreshing headers inside artifact bundle"
rm -rf "$ARTIFACT_DIR/include"
mkdir -p "$ARTIFACT_DIR/include"
cp -R "$INSTALL_PREFIX/include/." "$ARTIFACT_DIR/include/"
cp -R "$INCLUDE_SRC/." "$ARTIFACT_DIR/include/"

LIB_REL_PATH="${LIB_OUTPUT#$ARTIFACT_DIR/}"
python3 - "$ARTIFACT_DIR/info.json" "$TRIPLE" "$LIB_REL_PATH" "$ARTIFACT_VERSION" <<'PY'
import json
import pathlib
import sys

info_path = pathlib.Path(sys.argv[1])
triple = sys.argv[2]
lib_path = sys.argv[3]
version = sys.argv[4]

if info_path.exists():
    data = json.loads(info_path.read_text())
else:
    data = {"schemaVersion": "1.0", "artifacts": {}}

artifacts = data.setdefault("artifacts", {})
artifact = artifacts.setdefault("CFFmpegOpus", {"type": "staticLibrary", "version": version, "variants": []})
artifact["version"] = version
variants = [v for v in artifact.get("variants", []) if triple not in v.get("supportedTriples", [])]
variants.append({
    "path": lib_path,
    "supportedTriples": [triple],
    "staticLibraryMetadata": {
        "headerPaths": ["include"],
        "moduleMapPath": "include/module.modulemap"
    }
})
artifact["variants"] = variants
info_path.write_text(json.dumps(data, indent=2) + "\n")
PY

echo "==> Done. Artifact updated for ${TRIPLE}"
rm -rf "$WORK_ROOT"
