//
//  SDRPointCloudRenderer.m
//  ScanDepthRender
//
//  Created by Nigel Choi on 3/7/14.
//  Copyright (c) 2014 Nigel Choi. All rights reserved.
//

#import "SDRPointCloudRenderer.h"

#define POINT_CLOUD_DATA_SIZE (640 * 480 * sizeof(GLfloat))

// Angle of view 2 * arctan(7.5/9.5/2) in degrees
#define ANGLE_OF_VIEW_VERTICAL 43.082

// Uniform index.
enum
{
    UNIFORM_MODELVIEWPROJECTION_MATRIX,
    NUM_UNIFORMS
};

GLfloat gTestPointData[3*8] =
{
    // Data layout for each line below is:
    // positionX, positionY, positionZ,
    5.0f, 5.0f, 5.0f,
    -5.0f, 5.0f, 5.0f,
    5.0f, -5.0f, 5.0f,
    5.0f, 5.0f, -5.0f,
    5.0f, -5.0f, -5.0f,
    -5.0f, 5.0f, -5.0f,
    -5.0f, -5.0f, 5.0f,
    -5.0f, -5.0f, -5.0f,
};

@interface SDRPointCloudRenderer () {
    size_t _cols;
    size_t _rows;
    NSMutableData *_pointsData;
    NSMutableData *_imageData;
    
    GLint _uniforms[NUM_UNIFORMS];
    GLuint _program;
    GLKMatrix4 _modelViewProjectionMatrix;
    float _rotation;
    
    GLuint _pointArray;
    GLuint _pointBuffer;
    GLuint _colorBuffer;
}

- (BOOL)loadShaders;
- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type file:(NSString *)file;
- (BOOL)linkProgram:(GLuint)prog;
- (BOOL)validateProgram:(GLuint)prog;

@end

@implementation SDRPointCloudRenderer

- (SDRPointCloudRenderer *)initWithCols:(size_t)cols rows:(size_t)rows
{
    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if (!self.context) {
        NSLog(@"Failed to create ES context");
        return nil;
    }

    _cols = cols;
    _rows = rows;
    _pointsData = [[NSMutableData alloc] initWithCapacity:cols * rows * 3 * sizeof(float)];
    _imageData = [[NSMutableData alloc] initWithCapacity:cols * rows * 4 * sizeof(char)];

    [self setupGL];
    return self;
}

- (void)dealloc
{
    [self tearDownGL];
}

- (void)setupGL
{
    [EAGLContext setCurrentContext:self.context];
    
    [self loadShaders];
    
    glEnable(GL_DEPTH_TEST);

    glGenVertexArraysOES(1, &_pointArray);
    glBindVertexArrayOES(_pointArray);
    
    glGenBuffers(1, &_pointBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, _pointBuffer);
    glBufferData(GL_ARRAY_BUFFER, _cols*_rows*3*sizeof(GLfloat), _pointsData.bytes, GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(GLKVertexAttribPosition);
    glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, 3*sizeof(GLfloat), NULL);

    glGenBuffers(1, &_colorBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, _colorBuffer);
    glBufferData(GL_ARRAY_BUFFER, _cols*_rows*4*sizeof(GLbyte), NULL, GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(GLKVertexAttribColor);
    glVertexAttribPointer(GLKVertexAttribColor, 4, GL_UNSIGNED_BYTE, GL_TRUE, 4, NULL);

    glBindVertexArrayOES(0);

}

- (void)tearDownGL
{
    [EAGLContext setCurrentContext:self.context];
    
    glDeleteBuffers(1, &_colorBuffer);
    glDeleteBuffers(1, &_pointBuffer);
    glDeleteVertexArraysOES(1, &_pointArray);
    
    if (_program) {
        glDeleteProgram(_program);
        _program = 0;
    }
}

- (GLKViewDrawableDepthFormat)drawableDepthFormat
{
    return GLKViewDrawableDepthFormat24;
}

- (void)updateWithBounds:(CGRect)bounds timeSinceLastUpdate:(NSTimeInterval)timeSinceLastUpdate
{
    // Points update
    for (int i = 0; i < 24; i++)
    {
        ((float*)_pointsData.mutableBytes)[i] = gTestPointData[i] + 0.1 * rand()/(float)RAND_MAX - 0.05;
    }
    glBindBuffer(GL_ARRAY_BUFFER, _pointBuffer);
    glBufferSubData(GL_ARRAY_BUFFER, 0, sizeof(gTestPointData), _pointsData.bytes);
    
    // Rotation and Projection
    float aspect = fabsf(bounds.size.width / bounds.size.height);
    GLKMatrix4 projectionMatrix = GLKMatrix4MakePerspective(GLKMathDegreesToRadians(65.0f), aspect, 0.1f, 100.0f);
    
    GLKMatrix4 modelViewMatrix = GLKMatrix4MakeTranslation(0.0f, 0.0f, -20.0f);
    modelViewMatrix = GLKMatrix4Rotate(modelViewMatrix, GLKMathDegreesToRadians(40.0f), 1.0, 0.0, 0);
    float r = _rotation;
    modelViewMatrix = GLKMatrix4Rotate(modelViewMatrix, r, 0.0, 1.0, 0);
    _modelViewProjectionMatrix = GLKMatrix4Multiply(projectionMatrix, modelViewMatrix);
    
    _rotation += timeSinceLastUpdate * 0.5f;
}

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
    glClearColor(0.65f, 0.65f, 0.65f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    glBindVertexArrayOES(_pointArray);
    
    glUseProgram(_program);
    
    glUniformMatrix4fv(_uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX], 1, 0, _modelViewProjectionMatrix.m);
    
    glDrawArrays(GL_POINTS, 0, (GLsizei)(_cols*_rows));
}

- (void)updatePointsWithDepth:(STFloatDepthFrame*)depthFrame image:(CGImageRef)imageRef;
{
    if (imageRef)
    {
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(_imageData.mutableBytes,
                                                     _cols, _rows,
                                                     8,         // bits per component
                                                     4 * _cols, // bytes per row
                                                     colorSpace,
                                                     kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGColorSpaceRelease(colorSpace);
        
        CGContextDrawImage(context, CGRectMake(0, 0, _cols, _rows), imageRef);
        CGContextRelease(context);
        
        char *p = (char*)_imageData.mutableBytes;
        p[0] = 255;
        p[1] = 0;
        p[2] = 0;
        p[3] = 255;

        p[4] = 0;
        p[5] = 255;
        p[6] = 0;
        p[7] = 255;
        
        p[8] = 0;
        p[9] = 0;
        p[10] = 255;
        p[11] = 255;
        
        glBindBuffer(GL_ARRAY_BUFFER, _colorBuffer);
        glBufferSubData(GL_ARRAY_BUFFER, 0, _cols*_rows*4*sizeof(GLbyte), _imageData.bytes);
    }
    if (depthFrame)
    {
        float *data = (float *)_pointsData.mutableBytes;
        const float *depths = [depthFrame depthAsMeters];
        float xcenter = _cols/2.0;
        float ycenter = _rows/2.0;
        float pixelAngle = ANGLE_OF_VIEW_VERTICAL/_rows;
        
        for (int r = 0; r < _rows; r++)
        {
            for (int c = 0; c < _cols; c++)
            {
                float depth = depths[r * _cols + c];
                float * point = data + (r*_cols+c)*3;
//                point[0] = depth * sinf((r - xcenter)*pixelAngle);
//                point[1] = depth * sinf((c - ycenter)*pixelAngle);
                point[0] = 0.016 * (c-xcenter);
                point[1] = 0.016 * (ycenter-r);
                point[2] = -depth/1000.0;
            }
        }
        glBindBuffer(GL_ARRAY_BUFFER, _pointBuffer);
        glBufferSubData(GL_ARRAY_BUFFER, 0, _cols*_rows*3*sizeof(GLfloat), _pointsData.bytes);
    }
}

#pragma mark - OpenGL ES 2 shader compilation

- (BOOL)loadShaders
{
    GLuint vertShader, fragShader;
    NSString *vertShaderPathname, *fragShaderPathname;
    
    // Create shader program.
    _program = glCreateProgram();
    
    // Create and compile vertex shader.
    vertShaderPathname = [[NSBundle mainBundle] pathForResource:@"PointCloudShader" ofType:@"vsh"];
    if (![self compileShader:&vertShader type:GL_VERTEX_SHADER file:vertShaderPathname]) {
        NSLog(@"Failed to compile vertex shader");
        return NO;
    }
    
    // Create and compile fragment shader.
    fragShaderPathname = [[NSBundle mainBundle] pathForResource:@"PointCloudShader" ofType:@"fsh"];
    if (![self compileShader:&fragShader type:GL_FRAGMENT_SHADER file:fragShaderPathname]) {
        NSLog(@"Failed to compile fragment shader");
        return NO;
    }
    
    // Attach vertex shader to program.
    glAttachShader(_program, vertShader);
    
    // Attach fragment shader to program.
    glAttachShader(_program, fragShader);
    
    // Bind attribute locations.
    // This needs to be done prior to linking.
    glBindAttribLocation(_program, GLKVertexAttribPosition, "position");
    glBindAttribLocation(_program, GLKVertexAttribColor, "color");
    
    // Link program.
    if (![self linkProgram:_program]) {
        NSLog(@"Failed to link program: %d", _program);
        
        if (vertShader) {
            glDeleteShader(vertShader);
            vertShader = 0;
        }
        if (fragShader) {
            glDeleteShader(fragShader);
            fragShader = 0;
        }
        if (_program) {
            glDeleteProgram(_program);
            _program = 0;
        }
        
        return NO;
    }
    
    // Get uniform locations.
    _uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX] = glGetUniformLocation(_program, "modelViewProjectionMatrix");
    
    // Release vertex and fragment shaders.
    if (vertShader) {
        glDetachShader(_program, vertShader);
        glDeleteShader(vertShader);
    }
    if (fragShader) {
        glDetachShader(_program, fragShader);
        glDeleteShader(fragShader);
    }
    
    return YES;
}

- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type file:(NSString *)file
{
    GLint status;
    const GLchar *source;
    
    source = (GLchar *)[[NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil] UTF8String];
    if (!source) {
        NSLog(@"Failed to load vertex shader");
        return NO;
    }
    
    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &source, NULL);
    glCompileShader(*shader);
    
#if defined(DEBUG)
    GLint logLength;
    glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderInfoLog(*shader, logLength, &logLength, log);
        NSLog(@"Shader compile log:\n%s", log);
        free(log);
    }
#endif
    
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
    if (status == 0) {
        glDeleteShader(*shader);
        return NO;
    }
    
    return YES;
}

- (BOOL)linkProgram:(GLuint)prog
{
    GLint status;
    glLinkProgram(prog);
    
#if defined(DEBUG)
    GLint logLength;
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program link log:\n%s", log);
        free(log);
    }
#endif
    
    glGetProgramiv(prog, GL_LINK_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

- (BOOL)validateProgram:(GLuint)prog
{
    GLint logLength, status;
    
    glValidateProgram(prog);
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program validate log:\n%s", log);
        free(log);
    }
    
    glGetProgramiv(prog, GL_VALIDATE_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

@end
