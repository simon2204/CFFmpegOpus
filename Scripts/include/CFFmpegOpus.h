#ifndef CFFMPEGOPUS_SHIM_H
#define CFFMPEGOPUS_SHIM_H

#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libavutil/channel_layout.h>
#include <libavutil/frame.h>
#include <libavutil/mem.h>
#include <libavutil/samplefmt.h>
#include <libswresample/swresample.h>
#include <opus/opus.h>
#include <errno.h>
#include <stdint.h>

static inline int32_t Swift_AVERROR_EOF(void) {
    return AVERROR_EOF;
}

static inline int32_t Swift_AVERROR_EAGAIN(void) {
    return AVERROR(EAGAIN);
}

int SwiftOpusSetBitrate(OpusEncoder *encoder, int bitrate);

#endif /* CFFMPEGOPUS_SHIM_H */
