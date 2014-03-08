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
    0.5f, 0.5f, 0.5f,
    0.5f, 0.5f, -0.5f,
    0.5f, -0.5f, 0.5f,
    -0.5f, 0.5f, 0.5f,
    0.5f, -0.5f, -0.5f,
    -0.5f, -0.5f, 0.5f,
    -0.5f, 0.5f, -0.5f,
    -0.5f, -0.5f, -0.5f,
};

GLubyte gTestColorData[4*8] =
{
    0,   0,   0,   255,
    255, 0,   0,   255,
    0,   255, 0,   255,
    0,   0,   255, 255,
    255, 255, 0,   255,
    255, 0,   255, 255,
    0,   255, 255, 255,
    255, 255, 255, 255,
};

@interface SDRPointCloudRenderer () {
    size_t _cols;
    size_t _rows;
    NSMutableData *_pointsData;
    unsigned char *_imageBuffer;
    
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
    _pointsData = [[NSMutableData alloc] initWithCapacity:cols * rows * sizeof(float)];
    _imageBuffer = NULL;

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
    glBufferData(GL_ARRAY_BUFFER, sizeof(gTestPointData), gTestPointData, GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(GLKVertexAttribPosition);
    glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, 3*sizeof(GLfloat), NULL);

    glGenBuffers(1, &_colorBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, _colorBuffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(gTestColorData), gTestColorData, GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(GLKVertexAttribColor);
    glVertexAttribPointer(GLKVertexAttribColor, 4, GL_UNSIGNED_BYTE, GL_FALSE, 4, NULL);

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
    float aspect = fabsf(bounds.size.width / bounds.size.height);
    GLKMatrix4 projectionMatrix = GLKMatrix4MakePerspective(GLKMathDegreesToRadians(65.0f), aspect, 0.1f, 100.0f);
    
    GLKMatrix4 baseModelViewMatrix = GLKMatrix4MakeTranslation(0.0f, 0.0f, -4.0f);
    baseModelViewMatrix = GLKMatrix4Rotate(baseModelViewMatrix, _rotation, 0.0f, 1.0f, 0.0f);
    
    // Compute the model view matrix for the object rendered with GLKit
    GLKMatrix4 modelViewMatrix = GLKMatrix4MakeTranslation(0.0f, 0.0f, -1.5f);
    modelViewMatrix = GLKMatrix4Rotate(modelViewMatrix, _rotation, 1.0f, 1.0f, 1.0f);
    modelViewMatrix = GLKMatrix4Multiply(baseModelViewMatrix, modelViewMatrix);
    
    // Compute the model view matrix for the object rendered with ES2
    modelViewMatrix = GLKMatrix4MakeTranslation(0.0f, 0.0f, 1.5f);
    modelViewMatrix = GLKMatrix4Rotate(modelViewMatrix, _rotation, 1.0f, 1.0f, 1.0f);
    modelViewMatrix = GLKMatrix4Multiply(baseModelViewMatrix, modelViewMatrix);
    
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
    
    glDrawArrays(GL_POINTS, 0, 8);
}

- (void)updateImageDataBuffer:(unsigned char*)buffer
{
    
}

- (void)updatePointsWithDepth:(STFloatDepthFrame*)depthFrame
{
    
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
