//
//  SDRViewController.m
//  ScanDepthRender
//
//  Created by Nigel Choi on 3/6/14.
//  Copyright (c) 2014 Nigel Choi. All rights reserved.
//

#import "SDRViewController.h"
#import <Structure/StructureSLAM.h>

#define BUFFER_OFFSET(i) ((char *)NULL + (i))
#define STREAM_CONFIG CONFIG_VGA_REGISTERED_DEPTH

//#define SCAN_DO_SYNC 1

#ifdef SCAN_DO_SYNC
#define FRAME_SYNC_CONFIG FRAME_SYNC_DEPTH_AND_RGB
#else
#define FRAME_SYNC_CONFIG FRAME_SYNC_OFF
#endif

// Uniform index.
enum
{
    UNIFORM_MODELVIEWPROJECTION_MATRIX,
    UNIFORM_NORMAL_MATRIX,
    NUM_UNIFORMS
};
GLint uniforms[NUM_UNIFORMS];

// Attribute index.
enum
{
    ATTRIB_VERTEX,
    ATTRIB_NORMAL,
    NUM_ATTRIBUTES
};

GLfloat gCubeVertexData[216] = 
{
    // Data layout for each line below is:
    // positionX, positionY, positionZ,     normalX, normalY, normalZ,
    0.5f, -0.5f, -0.5f,        1.0f, 0.0f, 0.0f,
    0.5f, 0.5f, -0.5f,         1.0f, 0.0f, 0.0f,
    0.5f, -0.5f, 0.5f,         1.0f, 0.0f, 0.0f,
    0.5f, -0.5f, 0.5f,         1.0f, 0.0f, 0.0f,
    0.5f, 0.5f, -0.5f,          1.0f, 0.0f, 0.0f,
    0.5f, 0.5f, 0.5f,         1.0f, 0.0f, 0.0f,
    
    0.5f, 0.5f, -0.5f,         0.0f, 1.0f, 0.0f,
    -0.5f, 0.5f, -0.5f,        0.0f, 1.0f, 0.0f,
    0.5f, 0.5f, 0.5f,          0.0f, 1.0f, 0.0f,
    0.5f, 0.5f, 0.5f,          0.0f, 1.0f, 0.0f,
    -0.5f, 0.5f, -0.5f,        0.0f, 1.0f, 0.0f,
    -0.5f, 0.5f, 0.5f,         0.0f, 1.0f, 0.0f,
    
    -0.5f, 0.5f, -0.5f,        -1.0f, 0.0f, 0.0f,
    -0.5f, -0.5f, -0.5f,       -1.0f, 0.0f, 0.0f,
    -0.5f, 0.5f, 0.5f,         -1.0f, 0.0f, 0.0f,
    -0.5f, 0.5f, 0.5f,         -1.0f, 0.0f, 0.0f,
    -0.5f, -0.5f, -0.5f,       -1.0f, 0.0f, 0.0f,
    -0.5f, -0.5f, 0.5f,        -1.0f, 0.0f, 0.0f,
    
    -0.5f, -0.5f, -0.5f,       0.0f, -1.0f, 0.0f,
    0.5f, -0.5f, -0.5f,        0.0f, -1.0f, 0.0f,
    -0.5f, -0.5f, 0.5f,        0.0f, -1.0f, 0.0f,
    -0.5f, -0.5f, 0.5f,        0.0f, -1.0f, 0.0f,
    0.5f, -0.5f, -0.5f,        0.0f, -1.0f, 0.0f,
    0.5f, -0.5f, 0.5f,         0.0f, -1.0f, 0.0f,
    
    0.5f, 0.5f, 0.5f,          0.0f, 0.0f, 1.0f,
    -0.5f, 0.5f, 0.5f,         0.0f, 0.0f, 1.0f,
    0.5f, -0.5f, 0.5f,         0.0f, 0.0f, 1.0f,
    0.5f, -0.5f, 0.5f,         0.0f, 0.0f, 1.0f,
    -0.5f, 0.5f, 0.5f,         0.0f, 0.0f, 1.0f,
    -0.5f, -0.5f, 0.5f,        0.0f, 0.0f, 1.0f,
    
    0.5f, -0.5f, -0.5f,        0.0f, 0.0f, -1.0f,
    -0.5f, -0.5f, -0.5f,       0.0f, 0.0f, -1.0f,
    0.5f, 0.5f, -0.5f,         0.0f, 0.0f, -1.0f,
    0.5f, 0.5f, -0.5f,         0.0f, 0.0f, -1.0f,
    -0.5f, -0.5f, -0.5f,       0.0f, 0.0f, -1.0f,
    -0.5f, 0.5f, -0.5f,        0.0f, 0.0f, -1.0f
};

@interface SDRViewController () {
    GLuint _program;
    
    GLKMatrix4 _modelViewProjectionMatrix;
    GLKMatrix3 _normalMatrix;
    float _rotation;
    
    GLuint _vertexArray;
    GLuint _vertexBuffer;
    
    STSensorController *_sensorController;
    STFloatDepthFrame *_depthFrame;
    STDepthToRgba *_depthToRgba;
    
    AVCaptureSession *_avsession;
}
@property (strong, nonatomic) EAGLContext *context;
@property (strong, nonatomic) GLKBaseEffect *effect;

- (void)setupGL;
- (void)tearDownGL;

- (BOOL)loadShaders;
- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type file:(NSString *)file;
- (BOOL)linkProgram:(GLuint)prog;
- (BOOL)validateProgram:(GLuint)prog;
@end

@implementation SDRViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // GL setup
    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

    if (!self.context) {
        NSLog(@"Failed to create ES context");
    }
    
    GLKView *view = (GLKView *)self.view;
    view.context = self.context;
    view.drawableDepthFormat = GLKViewDrawableDepthFormat24;
    
    [self setupGL];
    
    // Structure setup
    _sensorController = [STSensorController sharedController];
    _sensorController.delegate = self;
    [_sensorController setFrameSyncConfig:FRAME_SYNC_CONFIG];

    _depthFrame = [[STFloatDepthFrame alloc] init];
    
        // When the app enters the foreground, we can choose to restart the stream
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillEnterForeground) name:UIApplicationWillEnterForegroundNotification object:nil];

    // Color camera
#if !TARGET_IPHONE_SIMULATOR
    [self startAVCaptureSession];
#endif
}

- (void)viewDidAppear:(BOOL)animated
{
    static bool fromLaunch = true;
    if (fromLaunch) {
        [self connectAndStartStreaming];
        fromLaunch = false;
    }
}

- (void)dealloc
{    
    [self tearDownGL];
    
    if ([EAGLContext currentContext] == self.context) {
        [EAGLContext setCurrentContext:nil];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];

    if ([self isViewLoaded] && ([[self view] window] == nil)) {
        self.view = nil;
        
        [self tearDownGL];
        
        if ([EAGLContext currentContext] == self.context) {
            [EAGLContext setCurrentContext:nil];
        }
        self.context = nil;
    }

    // Dispose of any resources that can be recreated.
}

- (void)setupGL
{
    [EAGLContext setCurrentContext:self.context];
    
    [self loadShaders];
    
    self.effect = [[GLKBaseEffect alloc] init];
    self.effect.light0.enabled = GL_TRUE;
    self.effect.light0.diffuseColor = GLKVector4Make(1.0f, 0.4f, 0.4f, 1.0f);
    
    glEnable(GL_DEPTH_TEST);
    
    glGenVertexArraysOES(1, &_vertexArray);
    glBindVertexArrayOES(_vertexArray);
    
    glGenBuffers(1, &_vertexBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, _vertexBuffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(gCubeVertexData), gCubeVertexData, GL_STATIC_DRAW);
    
    glEnableVertexAttribArray(GLKVertexAttribPosition);
    glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, 24, BUFFER_OFFSET(0));
    glEnableVertexAttribArray(GLKVertexAttribNormal);
    glVertexAttribPointer(GLKVertexAttribNormal, 3, GL_FLOAT, GL_FALSE, 24, BUFFER_OFFSET(12));
    
    glBindVertexArrayOES(0);
}

- (void)tearDownGL
{
    [EAGLContext setCurrentContext:self.context];
    
    glDeleteBuffers(1, &_vertexBuffer);
    glDeleteVertexArraysOES(1, &_vertexArray);
    
    self.effect = nil;
    
    if (_program) {
        glDeleteProgram(_program);
        _program = 0;
    }
}

- (void)appWillEnterForeground
{
    
    bool success = [self connectAndStartStreaming];
    
    if(!success)
    {
        // Workaround for direct multitasking between two Structure Apps.
        
        // HACK ALERT! Try once more after a delay if we failed to reconnect on foregrounding.
        // 0.75s was not enough, 0.95s was, but this might depend on the other app using the sensor.
        // We need a better solution to this.
        [NSTimer scheduledTimerWithTimeInterval:2.0 target:self
                                       selector:@selector(connectAndStartStreaming) userInfo:nil repeats:NO];
    }
    
}

- (bool)connectAndStartStreaming
{
    STSensorControllerInitStatus result = [_sensorController initializeSensorConnection];
    
    bool didSucceed = (result == STSensorControllerInitStatusSuccess || result == STSensorControllerInitStatusAlreadyInitialized);
    
    self.statusLabel.hidden = NO;
    
    if (didSucceed)
    {
        STSensorInfo *sensorInfo = [_sensorController getSensorInfo:STREAM_CONFIG];
        if (!sensorInfo) {
            self.statusLabel.text = @"Error getting Structure Sensor Info.";
            return false;
        }

        _depthToRgba = [[STDepthToRgba alloc] initWithSensorInfo:sensorInfo];
        
        // After this call, we will start to receive frames through the delegate methods
        [_sensorController startStreamingWithConfig:STREAM_CONFIG];

        // Now that we've started streaming, hide the status label
        self.statusLabel.hidden = YES;
    }
    else
    {
        if (result == STSensorControllerInitStatusSensorNotFound)
            self.statusLabel.text = @"Please connect Structure Sensor.";
        else if (result == STSensorControllerInitStatusOpenFailed)
            self.statusLabel.text = @"Structure Sensor open failed.";
        else if (result == STSensorControllerInitStatusSensorIsWakingUp)
            self.statusLabel.text = @"Structure Sensor is waking from low power.";
        else if (result != STSensorControllerInitStatusSuccess)
            self.statusLabel.text = [NSString stringWithFormat:@"Structure Sensor failed to init with status %d.", (int)result];
        else
            self.statusLabel.text = @"Unknown Structure Sensor state.";
    }
    
    return didSucceed;
}

#pragma mark - GLKView and GLKViewController delegate methods

- (void)update
{
    float aspect = fabsf(self.view.bounds.size.width / self.view.bounds.size.height);
    GLKMatrix4 projectionMatrix = GLKMatrix4MakePerspective(GLKMathDegreesToRadians(65.0f), aspect, 0.1f, 100.0f);
    
    self.effect.transform.projectionMatrix = projectionMatrix;
    
    GLKMatrix4 baseModelViewMatrix = GLKMatrix4MakeTranslation(0.0f, 0.0f, -4.0f);
    baseModelViewMatrix = GLKMatrix4Rotate(baseModelViewMatrix, _rotation, 0.0f, 1.0f, 0.0f);
    
    // Compute the model view matrix for the object rendered with GLKit
    GLKMatrix4 modelViewMatrix = GLKMatrix4MakeTranslation(0.0f, 0.0f, -1.5f);
    modelViewMatrix = GLKMatrix4Rotate(modelViewMatrix, _rotation, 1.0f, 1.0f, 1.0f);
    modelViewMatrix = GLKMatrix4Multiply(baseModelViewMatrix, modelViewMatrix);
    
    self.effect.transform.modelviewMatrix = modelViewMatrix;
    
    // Compute the model view matrix for the object rendered with ES2
    modelViewMatrix = GLKMatrix4MakeTranslation(0.0f, 0.0f, 1.5f);
    modelViewMatrix = GLKMatrix4Rotate(modelViewMatrix, _rotation, 1.0f, 1.0f, 1.0f);
    modelViewMatrix = GLKMatrix4Multiply(baseModelViewMatrix, modelViewMatrix);
    
    _normalMatrix = GLKMatrix3InvertAndTranspose(GLKMatrix4GetMatrix3(modelViewMatrix), NULL);
    
    _modelViewProjectionMatrix = GLKMatrix4Multiply(projectionMatrix, modelViewMatrix);
    
    _rotation += self.timeSinceLastUpdate * 0.5f;
}

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
    glClearColor(0.65f, 0.65f, 0.65f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    glBindVertexArrayOES(_vertexArray);
    
    // Render the object with GLKit
    [self.effect prepareToDraw];
    
    glDrawArrays(GL_TRIANGLES, 0, 36);
    
    // Render the object again with ES2
    glUseProgram(_program);
    
    glUniformMatrix4fv(uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX], 1, 0, _modelViewProjectionMatrix.m);
    glUniformMatrix3fv(uniforms[UNIFORM_NORMAL_MATRIX], 1, 0, _normalMatrix.m);
    
    glDrawArrays(GL_POINTS, 0, 36);
}

#pragma mark - OpenGL ES 2 shader compilation

- (BOOL)loadShaders
{
    GLuint vertShader, fragShader;
    NSString *vertShaderPathname, *fragShaderPathname;
    
    // Create shader program.
    _program = glCreateProgram();
    
    // Create and compile vertex shader.
    vertShaderPathname = [[NSBundle mainBundle] pathForResource:@"Shader" ofType:@"vsh"];
    if (![self compileShader:&vertShader type:GL_VERTEX_SHADER file:vertShaderPathname]) {
        NSLog(@"Failed to compile vertex shader");
        return NO;
    }
    
    // Create and compile fragment shader.
    fragShaderPathname = [[NSBundle mainBundle] pathForResource:@"Shader" ofType:@"fsh"];
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
    glBindAttribLocation(_program, GLKVertexAttribNormal, "normal");
    
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
    uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX] = glGetUniformLocation(_program, "modelViewProjectionMatrix");
    uniforms[UNIFORM_NORMAL_MATRIX] = glGetUniformLocation(_program, "normalMatrix");
    
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

#pragma mark - Structure SDK Delegate Methods

- (void)sensorDidDisconnect
{
    self.statusLabel.hidden = NO;
    self.statusLabel.text = @"Structure Sensor disconnected!";
}

- (void)sensorDidConnect
{
    [self connectAndStartStreaming];
}

- (void)sensorDidEnterLowPowerMode
{
}

- (void)sensorDidLeaveLowPowerMode
{
}

- (void)sensorBatteryNeedsCharging
{
    self.statusLabel.hidden = NO;
    self.statusLabel.text = @"Please charge the Structure Sensor";
}

- (void)sensorDidStopStreaming:(STSensorControllerDidStopStreamingReason)reason
{
    self.statusLabel.hidden = NO;
    self.statusLabel.text = @"Structure Sensor stopped streaming";
}

- (void)sensorDidOutputDepthFrame:(STDepthFrame*)depthFrame
{
    [self renderDepthFrame:depthFrame];
}

// This synchronized API will only be called when two frames match. Typically, timestamps are within 1ms of each other.
// Two important things have to happen for this method to be called:
// Tell the SDK we want framesync: [_ocSensorController setFrameSyncConfig:FRAME_SYNC_DEPTH_AND_RGB];
// Give the SDK color frames as they come in:     [_ocSensorController frameSyncNewColorImage:sampleBuffer];
- (void)sensorDidOutputSynchronizedDepthFrame:(STDepthFrame*)depthFrame
                                 andColorFrame:(CMSampleBufferRef)sampleBuffer
{
    [self renderDepthFrame:depthFrame];
    [self renderColorFrame:sampleBuffer];
}

#pragma mark - Structure Rendering

- (void)renderDepthFrame:(STDepthFrame*)depthFrame
{
    [_depthFrame updateFromDepthFrame:depthFrame];
    uint8_t *rgbaData = [_depthToRgba convertDepthToRgba:_depthFrame];
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    CGBitmapInfo bitmapInfo;
    bitmapInfo = (CGBitmapInfo)kCGImageAlphaPremultipliedLast;
    bitmapInfo |= kCGBitmapByteOrder16Big;
    
    
    NSData *data = [NSData dataWithBytes:rgbaData length:depthFrame->width * depthFrame->height * sizeof(uint32_t)];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    
    CGImageRef cgImage = CGImageCreate(depthFrame->width,
                                       depthFrame->height,
                                       8,
                                       32,
                                       depthFrame->width * sizeof(uint32_t),
                                       colorSpace,
                                       bitmapInfo,
                                       provider,
                                       NULL,
                                       false,
                                       kCGRenderingIntentDefault);
    
    CFRelease(provider);
    CFRelease(colorSpace);
    _depthImageView.image = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
}

- (void)renderColorFrame:(CMSampleBufferRef)sampleBuffer
{
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    
    size_t cols = CVPixelBufferGetWidth(pixelBuffer);
    size_t rows = CVPixelBufferGetHeight(pixelBuffer);
    
    
    unsigned char* ptr = (unsigned char*) CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    
    NSData *data = [[NSData alloc] initWithBytes:ptr length:rows*cols*4];
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    
    
    CGColorSpaceRef colorSpace;
    
    colorSpace = CGColorSpaceCreateDeviceRGB();
    
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)data);
    
    CGImageRef imageRef = CGImageCreate(cols,                                       //width
                                        rows,                                       //height
                                        8,                                          //bits per component
                                        8 * 4,                                      //bits per pixel
                                        cols*4,                                     //bytesPerRow
                                        colorSpace,                                 //colorspace
                                        kCGImageAlphaNoneSkipFirst|kCGBitmapByteOrder32Little,// bitmap info
                                        provider,                                   //CGDataProviderRef
                                        NULL,                                       //decode
                                        false,                                      //should interpolate
                                        kCGRenderingIntentDefault                   //intent
                                        );
    
    
    // Getting UIImage from CGImage
    _cameraImageView.image = [[UIImage alloc] initWithCGImage:imageRef];
    CGImageRelease(imageRef);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(colorSpace);
}

#pragma mark - Camera

- (void)startAVCaptureSession
{
    NSString* sessionPreset = AVCaptureSessionPreset640x480;
    
    //-- Setup Capture Session.
    _avsession = [[AVCaptureSession alloc] init];
    [_avsession beginConfiguration];
    
    //-- Set preset session size.
    [_avsession setSessionPreset:sessionPreset];
    
    //-- Creata a video device and input from that Device.  Add the input to the capture session.
    AVCaptureDevice * videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if(videoDevice == nil)
        assert(0);
    
    NSError *error;
    [videoDevice lockForConfiguration:&error];
    
    // Auto-focus Auto-exposure, auto-white balance
    if ([[[UIDevice currentDevice] systemVersion] compare:@"7.0" options:NSNumericSearch] != NSOrderedAscending)
        [videoDevice setAutoFocusRangeRestriction:AVCaptureAutoFocusRangeRestrictionFar];
    [videoDevice setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
    
    [videoDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
    [videoDevice setWhiteBalanceMode:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance];
    
    [videoDevice unlockForConfiguration];
    
    //-- Add the device to the session.
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
    if(error)
        assert(0);
    
    [_avsession addInput:input]; // After this point, captureSession captureOptions are filled.
    
    //-- Create the output for the capture session.
    AVCaptureVideoDataOutput * dataOutput = [[AVCaptureVideoDataOutput alloc] init];
    
    [dataOutput setAlwaysDiscardsLateVideoFrames:YES];
    
    //-- Set to YUV420.
    [dataOutput setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
                                                             forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
    
    // Set dispatch to be on the main thread so OpenGL can do things with the data
    [dataOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    
    [_avsession addOutput:dataOutput];
    
    if ([[[UIDevice currentDevice] systemVersion] compare:@"7.0" options:NSNumericSearch] != NSOrderedAscending)
    {
        [videoDevice lockForConfiguration:&error];
        [videoDevice setActiveVideoMaxFrameDuration:CMTimeMake(1, 30)];
        [videoDevice setActiveVideoMinFrameDuration:CMTimeMake(1, 30)];
        [videoDevice unlockForConfiguration];
    }
    else
    {
        AVCaptureConnection *conn = [dataOutput connectionWithMediaType:AVMediaTypeVideo];
        
        // Deprecated use is OK here because we're using the correct APIs on iOS 7 above when available
        // If we're running before iOS 7, we still really want 30 fps!
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        conn.videoMinFrameDuration = CMTimeMake(1, 30);
        conn.videoMaxFrameDuration = CMTimeMake(1, 30);
#pragma clang diagnostic pop
        
    }
    [_avsession commitConfiguration];
    
    [_avsession startRunning];
}


- (void) captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
#ifdef SCAN_DO_SYNC
    // Pass into the driver. The sampleBuffer will return later with a synchronized depth pair.
    [_sensorController frameSyncNewColorImage:sampleBuffer];
#else
    [self renderColorFrame:sampleBuffer];
#endif
}

@end
