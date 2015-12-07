//
//  SDRPointCloudRenderer.h
//  ScanDepthRender
//
//  Created by Nigel Choi on 3/7/14.
//  Copyright (c) 2014 Nigel Choi. All rights reserved.
//

#import <GLKit/GLKit.h>
#include <OpenGLES/ES2/gl.h>
#include <OpenGLES/ES2/glext.h>
#import <Structure/StructureSLAM.h>

@interface SDRPointCloudRenderer : NSObject

@property (strong, nonatomic) EAGLContext *context;

- (SDRPointCloudRenderer *)initWithCols:(size_t)cols rows:(size_t)rows;
- (void)setupGL;
- (void)tearDownGL;
- (GLKViewDrawableDepthFormat)drawableDepthFormat;
- (void)updateWithBounds:(CGRect)bounds
              projection:(GLKMatrix4)projection
               modelView:(GLKMatrix4)modelView
                invScale:(float)invScale;
- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect;
- (void)updatePointsWithDepth:(STDepthFrame*)depthFrame image:(CGImageRef)image;

@end
