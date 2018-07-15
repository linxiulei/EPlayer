//
//  EPlayer-Bridging-Header.h
//  EPlayer
//
//  Created by 林守磊 on 16/03/2018.
//  Copyright © 2018 林守磊. All rights reserved.
//

#ifndef EPlayer_Bridging_Header_h
#define EPlayer_Bridging_Header_h

#import "libavcodec/avcodec.h"
#import "libavdevice/avdevice.h"
#import "libavfilter/avfilter.h"
#import "libavformat/avformat.h"
#import "drawutils.h"
#import "libavutil/avutil.h"
#import "libavutil/dict.h"
#import "libavutil/pixdesc.h"
#import "libavutil/imgutils.h"
#import "libavutil/error.h"
#import "libavutil/opt.h"
#import "libavutil/hwcontext.h"
#import "libswresample/swresample.h"
#import "libswscale/swscale.h"
#import "ass/ass.h"
#import "ass/ass_types.h"
#import "uchardet.h"
#import "macro.h"

#import <CommonCrypto/CommonHMAC.h>

struct AVDictionary {
    int count;
    AVDictionaryEntry *elems;
};

#define MAX_LOOKUP_SIZE    32

#define IO_BUFFER_SIZE    32768


/* libass stores an RGBA color in the format RRGGBBTT, where TT is the transparency level */
#define AR(c)  ((c)>>24)
#define AG(c)  (((c)>>16)&0xFF)
#define AB(c)  (((c)>>8) &0xFF)
#define AA(c)  ((0xFF-c) &0xFF)

#define _A(c)  ((c)>>24)
#define _B(c)  (((c)>>16)&0xFF)
#define _G(c)  (((c)>>8)&0xFF)
#define _R(c)  ((c)&0xFF)

#define _r(c)  ((c)>>24)
#define _g(c)  (((c)>>16)&0xFF)
#define _b(c)  (((c)>>8)&0xFF)
#define _a(c)  ((c)&0xFF)

#define rgba2y(c)  ( (( 263*_r(c) + 516*_g(c) + 100*_b(c)) >> 10) + 16  )
#define rgba2u(c)  ( ((-152*_r(c) - 298*_g(c) + 450*_b(c)) >> 10) + 128 )
#define rgba2v(c)  ( (( 450*_r(c) - 376*_g(c) -  73*_b(c)) >> 10) + 128 )

#define abgr2y(c)  ( (( 263*_R(c) + 516*_G(c) + 100*_B(c)) >> 10) + 16  )
#define abgr2u(c)  ( ((-152*_R(c) - 298*_G(c) + 450*_B(c)) >> 10) + 128 )
#define abgr2v(c)  ( (( 450*_R(c) - 376*_G(c) -  73*_B(c)) >> 10) + 128 )

#define MAX_TRANS   255
#define TRANS_BITS 8

void render_subtitle_frame(FFDrawContext *m_draw, AVFrame *frame, int width, int height, ASS_Image* img)
{
    static AVFrame avframe = { 0 };
    /*
    avframe.data[0] = frame->data[0];
    avframe.data[1] = frame->data[0] + width * height;
    avframe.data[2] = avframe.data[1] + (width / 2) * (height / 2);
    avframe.data[3] = NULL;
    avframe.linesize[0] = width;
    avframe.linesize[1] = width / 2;
    avframe.linesize[2] = width / 2;
    avframe.linesize[3] = 0;
     */
    
    avframe.data[0] = frame->data[0];
    avframe.data[1] = frame->data[1];
    avframe.data[2] = frame->data[2];
    avframe.data[3] = NULL;
    avframe.linesize[0] = frame->linesize[0];
    avframe.linesize[1] = frame->linesize[1];
    avframe.linesize[2] = frame->linesize[2];
    avframe.linesize[3] = 0;
    
    int cnt = 0;
    while (img) {
        uint8_t rgba_color[] = {AR(img->color), AG(img->color), AB(img->color), AA(img->color)};
        FFDrawColor color;
        ff_draw_color(m_draw, &color, rgba_color);
        ff_blend_mask(m_draw, &color,
                      avframe.data, avframe.linesize,
                      width, height,
                      img->bitmap, img->stride, img->w, img->h,
                      3, 0, img->dst_x, img->dst_y);
        ++cnt;
        img = img->next;
    }
}

void expandAS(void *dest, int size, int unitSize, int coefficient) {
    char *newCopy = malloc(size+1);
    char *destCast = dest;
    //memcpy(newCopy, dest, size);
    
    int offset = 0;
    
    /*
    for (int i = 0; i < size; i++) {
        printf("%hhx ", destCast[i]);
    }
    printf("\n");
     */

        
    for (int i = 0; i < coefficient; i++) {
        /*
        for (int j = 0; j < unitSize; j ++)
            printf("%hhx ", destCast[size + offset - unitSize + j]);
        printf("\n");
         */
        memcpy(destCast + size + offset, destCast + size  - unitSize, unitSize);
        offset += unitSize;
    }
    /*
    for (int i = 0; i < size / unitSize; i++) {
        memcpy(destCast + 2 * i * unitSize,
               newCopy + i * unitSize,
               unitSize);
    }
     */
}

enum AVPixelFormat get_format (struct AVCodecContext *s, const enum AVPixelFormat * fmt) {
    return AV_PIX_FMT_VIDEOTOOLBOX;
}

#endif /* EPlayer_Bridging_Header_h */
