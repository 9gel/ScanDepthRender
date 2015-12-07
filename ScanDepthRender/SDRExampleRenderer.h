//
//  SDRExampleRenderer.h
//  ScanDepthRender
//
//  Created by Nigel Choi on 3/7/14.
//  Copyright (c) 2014 Nigel Choi. All rights reserved.
//

#import <GLKit/GLKit.h>
#include <OpenGLES/ES2/gl.h>
#include <OpenGLES/ES2/glext.h>

@interface SDRExampleRenderer : NSObject

@property (strong, nonatomic) EAGLContext *context;

- (void)setupGL;
- (void)tearDownGL;
- (GLKViewDrawableDepthFormat)drawableDepthFormat;
- (void)updateWithBounds:(CGRect)bounds timeSinceLastUpdate:(NSTimeInterval)timeSinceLastUpdate;
- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect;

@end
