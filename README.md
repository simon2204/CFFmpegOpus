# CFFmpegOpus Binary Bundle

This repository is intended to host the prebuilt FFmpeg/Opus bundle that the Discord music bot consumes.  
The bundle ships as a SwiftPM binary target (`CFFmpegOpus.artifactbundle`) with the following variants:

| Triple | Notes |
|--------|-------|
| `arm64-apple-macosx` | Built on macOS 15 with Xcode 16 toolchains. |
| `x86_64-unknown-linux-gnu` | Built inside the official `swift:6.2.1` Docker image. |
| `aarch64-unknown-linux-gnu` | Built inside the official `swift:6.2.1` Docker image. |

## Repository Layout

```
.
├── Artifacts/
│   ├── CFFmpegOpus.artifactbundle/        # unpacked bundle (headers + libraries + module map)
│   └── CFFmpegOpus.artifactbundle.zip     # zipped bundle for distribution
├── Scripts/
│   ├── build_cffmpeg_opus.sh              # builds for the host machine
│   └── build_cffmpeg_opus_docker.sh       # builds inside swift:6.2.1 (handy for Linux variants)
└── README.md                              # this file
```

## Publishing Workflow

1. Run one (or both) scripts to refresh the bundle:
   ```bash
   # macOS arm64 (host build)
   Scripts/build_cffmpeg_opus.sh

   # Linux x86_64 via Docker
   Scripts/build_cffmpeg_opus_docker.sh x86_64-unknown-linux-gnu

   # Linux aarch64 via Docker
   Scripts/build_cffmpeg_opus_docker.sh aarch64-unknown-linux-gnu
   ```
2. Zip the bundle and compute the checksum:
   ```bash
   (cd Artifacts && rm -f CFFmpegOpus.artifactbundle.zip && \
        zip -r CFFmpegOpus.artifactbundle.zip CFFmpegOpus.artifactbundle)
   swift package compute-checksum Artifacts/CFFmpegOpus.artifactbundle.zip
   ```
3. Commit the updated `Artifacts/` directory.
4. Optionally create a GitHub release that attaches the ZIP; re-use the computed checksum in the manifest snippets below.

## Consuming from another Package

Reference the binary target directly in your `Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ExampleApp",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .binaryTarget(
            name: "CFFmpegOpus",
            url: "https://github.com/simon2204/CFFmpegOpus/releases/download/v0.1.0/CFFmpegOpus.artifactbundle.zip",
            checksum: "d3ff2ee140698c0de808b14aabbfe553751eff244add635e71cf0906c6584ca4"
        ),
        .executableTarget(
            name: "ExampleApp",
            dependencies: [
                .target(name: "CFFmpegOpus")
            ]
        )
    ]
)
```

If you consume the bundle directly from a git checkout (without a release ZIP), you can reference it via `path:`:

```swift
.binaryTarget(
    name: "CFFmpegOpus",
    path: "Artifacts/CFFmpegOpus.artifactbundle"
)
```

> **Note:** Update the `url` and `checksum` values to match the release asset you publish.  
> The latest checksum for the provided ZIP is:
>
> ```
> d3ff2ee140698c0de808b14aabbfe553751eff244add635e71cf0906c6584ca4
> ```

## Updating FFmpeg / Opus Versions

1. Override the versions when invoking the script:
   ```bash
   OPUS_VERSION=1.5.3 FFMPEG_VERSION=n8.0 Scripts/build_cffmpeg_opus_docker.sh x86_64-unknown-linux-gnu
   ```
2. Regenerate the ZIP + checksum and release a new tag.
3. Update the README with the new checksum.
