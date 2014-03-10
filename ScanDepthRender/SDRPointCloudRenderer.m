//
//  SDRPointCloudRenderer.m
//  ScanDepthRender
//
//  Created by Nigel Choi on 3/7/14.
//  Copyright (c) 2014 Nigel Choi. All rights reserved.
//

#import "SDRPointCloudRenderer.h"

// Assume the following intrinsics, from the Structure SDK docs
// K_RGB_QVGA       = [305.73, 0, 159.69; 0, 305.62, 119.86; 0, 0, 1]
#define QVGA_COLS 320
#define QVGA_ROWS 240
#define QVGA_F_X 305.73
#define QVGA_F_Y 305.62
#define QVGA_C_X 159.69
#define QVGA_C_Y 119.86

#define NUM_TEST_POINTS 8
GLfloat gTestPoints[NUM_TEST_POINTS * 3] =
{
    // Data layout for each line below is:
    // positionX, positionY, positionZ,
    2.0f, 1.0f, 2.0f,
    -2.0f, 1.0f, 2.0f,
    -2.0f, -1.0f, 2.0f,
    2.0f, -1.0f, 2.0f,
    
    2.0f, 1.0f, -2.0f,
    -2.0f, 1.0f, -2.0f,
    -2.0f, -1.0f, -2.0f,
    2.0f, -1.0f, -2.0f,
};

GLubyte gTestPointColors[NUM_TEST_POINTS * 4] =
{
    // Data layout for each line below is:
    // R, G, B, A,
    255, 0, 0, 255,     // red
    0, 255, 0, 255,     // green
    0, 0, 255, 255,     // blue
    255, 255, 0, 255,   // yellow

    255, 0, 255, 255,   // magenta
    0, 255, 255, 255,   // cyan
    255, 255, 255, 0,   // white
    0, 0, 0, 0          // black
};

@interface SDRPointCloudRenderer () {
    size_t _cols;
    size_t _rows;
    float _fx, _fy, _cx, _cy;
    NSMutableData *_pointsData;
    NSMutableData *_imageData;
    
    GLuint _program;

    GLint _modelViewUniform;
    GLint _projectionUniform;
    GLint _inverseScaleUniform;
    GLKMatrix4 _modelViewMatrix;
    GLKMatrix4 _projectionMatrix;
    GLfloat _inverseScale;
    
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
    
    _fx = QVGA_F_X/QVGA_COLS*cols;
    _fy = QVGA_F_X/QVGA_ROWS*rows;
    _cx = QVGA_C_X/QVGA_COLS*cols;
    _cy = QVGA_C_Y/QVGA_ROWS*rows;
    
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
    glBufferData(GL_ARRAY_BUFFER, _cols * _rows * 3 * sizeof(GLfloat) + sizeof(gTestPoints), NULL, GL_DYNAMIC_DRAW);
    glBufferSubData(GL_ARRAY_BUFFER, 0, sizeof(gTestPoints), gTestPoints);
    glEnableVertexAttribArray(GLKVertexAttribPosition);
    glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, 3 * sizeof(GLfloat), NULL);

    glGenBuffers(1, &_colorBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, _colorBuffer);
    glBufferData(GL_ARRAY_BUFFER, _cols * _rows * 4 * sizeof(GLbyte) + sizeof(gTestPointColors), NULL, GL_DYNAMIC_DRAW);
    glBufferSubData(GL_ARRAY_BUFFER, 0, sizeof(gTestPointColors), gTestPointColors);
    glEnableVertexAttribArray(GLKVertexAttribColor);
    glVertexAttribPointer(GLKVertexAttribColor, 4, GL_UNSIGNED_BYTE, GL_TRUE, 4 * sizeof(GLubyte), NULL);

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

- (void)updateWithBounds:(CGRect)bounds
              projection:(GLKMatrix4)projection
               modelView:(GLKMatrix4)modelView
                invScale:(float)invScale;
{
    _modelViewMatrix = modelView;
    _projectionMatrix = projection;
    _inverseScale = invScale;
}

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
    glClearColor(0.65f, 0.65f, 0.65f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    glBindVertexArrayOES(_pointArray);
    
    glUseProgram(_program);
    
    glUniformMatrix4fv(_modelViewUniform, 1, GL_FALSE, _modelViewMatrix.m);
    glUniformMatrix4fv(_projectionUniform, 1, GL_FALSE, _projectionMatrix.m);
    glUniform1f(_inverseScaleUniform, _inverseScale);
    
    glDrawArrays(GL_POINTS, 0, NUM_TEST_POINTS);
    glDrawArrays(GL_POINTS, NUM_TEST_POINTS, (GLsizei)(_cols*_rows));
}

- (void)updatePointsWithDepth:(STFloatDepthFrame*)depthFrame image:(CGImageRef)imageRef;
{
    if (imageRef)
    {
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate((GLubyte *)_imageData.mutableBytes,
                                                     _cols, _rows,
                                                     8,         // bits per component
                                                     4 * _cols, // bytes per row
                                                     colorSpace,
                                                     kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGColorSpaceRelease(colorSpace);
        
        CGContextDrawImage(context, CGRectMake(0, 0, _cols, _rows), imageRef);
        CGContextRelease(context);
        
        glBindBuffer(GL_ARRAY_BUFFER, _colorBuffer);
        glBufferSubData(GL_ARRAY_BUFFER, sizeof(gTestPointColors), _cols*_rows*4*sizeof(GLbyte), _imageData.bytes);
    }
    if (depthFrame)
    {
        float *data = (GLfloat *)_pointsData.mutableBytes;
        const float *depths = [depthFrame depthAsMeters];
        
        for (int r = 0; r < _rows; r++)
        {
            for (int c = 0; c < _cols; c++)
            {
                float depth = depths[r * _cols + c]/1000.0;
                float * point = data + (r*_cols+c)*3;
                point[0] = depth * (c - _cx) / _fx;
                point[1] = depth * (_cy - r) / _fy;
                point[2] = 2.0f - depth;
            }
        }
        glBindBuffer(GL_ARRAY_BUFFER, _pointBuffer);
        glBufferSubData(GL_ARRAY_BUFFER, sizeof(gTestPoints), _cols*_rows*3*sizeof(GLfloat), _pointsData.bytes);
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
    _modelViewUniform = glGetUniformLocation(_program, "modelViewMatrix");
    _projectionUniform = glGetUniformLocation(_program, "projectionMatrix");
    _inverseScaleUniform = glGetUniformLocation(_program, "inverseScale");
    
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
