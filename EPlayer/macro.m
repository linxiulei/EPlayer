//
//  macro.m
//  EPlayer
//
//  Created by 林守磊 on 17/03/2018.
//  Copyright © 2018 林守磊. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "macro.h"
#import "libavutil/error.h"

@implementation FF:NSObject

+ (NSString*)av_err2str:(int)errnum {
    char *str = av_err2str(errnum);
    return [NSString stringWithUTF8String:str];
}

@end
