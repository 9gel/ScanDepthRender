//
//  SDRViewController.m
//  ScanDepthRender
//
//  Created by Nigel Choi on 3/6/14.
//  Copyright (c) 2014 Nigel Choi. All rights reserved.
//

#import "SDRViewController.h"
#import "SDRExampleRenderer.h"
#import "SDRPointCloudRenderer.h"
#import "AnimationControl.h"
#import <Structure/StructureSLAM.h>

#define RENDERER_CLASS SDRPointCloudRenderer

//#define SCAN_DO_SYNC 1

#ifdef SCAN_DO_SYNC
#define FRAME_SYNC_CONFIG FRAME_SYNC_DEPTH_AND_RGB
#else
#define FRAME_SYNC_CONFIG FRAME_SYNC_OFF
#endif

#define VGA 1

#ifdef VGA
#define DATA_COLS 640
#define DATA_ROWS 480
#define STREAM_CONFIG CONFIG_VGA_REGISTERED_DEPTH
#define CAMERA_PRESET AVCaptureSessionPreset640x480
#else
#define DATA_COLS 320
#define DATA_ROWS 240
#define STREAM_CONFIG CONFIG_QVGA_REGISTERED_DEPTH
#define CAMERA_PRESET AVCaptureSessionPreset352x288
#endif

@interface SDRViewController () {
    RENDERER_CLASS *_renderer;
    AnimationControl *_animation;
    
    STSensorController *_sensorController;
    STFloatDepthFrame *_depthFrame;
    STDepthToRgba *_depthToRgba;
    
    AVCaptureSession *_avsession;
}
@property (strong, nonatomic) EAGLContext *context;
@property (strong, nonatomic) GLKBaseEffect *effect;
@end

@implementation SDRViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // GL setup
    _renderer = [[RENDERER_CLASS alloc] initWithCols:DATA_COLS rows:DATA_ROWS];
    if (!_renderer) {
        NSLog(@"Failed to create renderer.");
        return;
    }
    self.context = _renderer.context;
    
    GLKView *view = (GLKView *)self.view;
    view.context = self.context;
    view.drawableDepthFormat = _renderer.drawableDepthFormat;
    
    _animation = new AnimationControl(self.view.frame.size.width,
                                      self.view.frame.size.height);
    [self setupGestureRecognizer];
    
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
    if ([EAGLContext currentContext] == self.context) {
        [EAGLContext setCurrentContext:nil];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];

    if ([self isViewLoaded] && ([[self view] window] == nil)) {
        self.view = nil;
        
        _renderer = nil;
        
        if ([EAGLContext currentContext] == self.context) {
            [EAGLContext setCurrentContext:nil];
        }
        self.context = nil;
    }

    // Dispose of any resources that can be recreated.
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

- (void) setupGestureRecognizer
{
    UIPinchGestureRecognizer *pinchScaleGesture = [[UIPinchGestureRecognizer alloc]
                                                   initWithTarget:self
                                                   action:@selector(pinchScaleGesture:)];
    [pinchScaleGesture setDelegate:self];
    [self.view addGestureRecognizer:pinchScaleGesture];
    
    UIPanGestureRecognizer *panRotGesture = [[UIPanGestureRecognizer alloc]
                                             initWithTarget:self
                                             action:@selector(panRotGesture:)];
    [panRotGesture setDelegate:self];
    [panRotGesture setMaximumNumberOfTouches:1];
    [self.view addGestureRecognizer:panRotGesture];
    
    UIPanGestureRecognizer *panTransGesture = [[UIPanGestureRecognizer alloc]
                                               initWithTarget:self
                                               action:@selector(panTransGesture:)];
    [panTransGesture setDelegate:self];
    [panTransGesture setMaximumNumberOfTouches:2];
    [panTransGesture setMinimumNumberOfTouches:2];
    [self.view addGestureRecognizer:panTransGesture];
}

#pragma mark - GLKView and GLKViewController delegate methods

- (void)update
{
    [_renderer updateWithBounds:self.view.bounds timeSinceLastUpdate:self.timeSinceLastUpdate];
}

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
    [_renderer glkView:view drawInRect:rect];
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
    [_renderer updatePointsWithDepth:_depthFrame image:nil];
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
    [_renderer updatePointsWithDepth:_depthFrame image:_cameraImageView.image.CGImage];
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
    NSString* sessionPreset = CAMERA_PRESET;
    
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
    [_renderer updatePointsWithDepth:nil image:_cameraImageView.image.CGImage];
#endif
}

#pragma mark - UI Control

- (void) pinchScaleGesture: (UIPinchGestureRecognizer*) gestureRecognizer
{
    if ([gestureRecognizer state] == UIGestureRecognizerStateBegan)
        _animation->onTouchScaleBegan([gestureRecognizer scale]);
    else if ( [gestureRecognizer state] == UIGestureRecognizerStateChanged)
        _animation->onTouchScaleChanged([gestureRecognizer scale]);
}

- (void) panRotGesture: (UIPanGestureRecognizer*) gestureRecognizer
{
    CGPoint touchPos = [gestureRecognizer locationInView:self.view];
    CGPoint touchVel = [gestureRecognizer velocityInView:self.view];
    GLKVector2 touchPosVec = GLKVector2Make(touchPos.x, touchPos.y);
    GLKVector2 touchVelVec = GLKVector2Make(touchVel.x, touchVel.y);
    
    if([gestureRecognizer state] == UIGestureRecognizerStateBegan)
        _animation->onTouchRotBegan(touchPosVec);
    else if([gestureRecognizer state] == UIGestureRecognizerStateChanged)
        _animation->onTouchRotChanged(touchPosVec);
    else if([gestureRecognizer state] == UIGestureRecognizerStateEnded)
        _animation->onTouchRotEnded (touchVelVec);
}

- (void) panTransGesture: (UIPanGestureRecognizer*) gestureRecognizer
{
    if ([gestureRecognizer numberOfTouches] != 2)
        return;
    
    CGPoint touchPos = [gestureRecognizer locationInView:self.view];
    CGPoint touchVel = [gestureRecognizer velocityInView:self.view];
    GLKVector2 touchPosVec = GLKVector2Make(touchPos.x, touchPos.y);
    GLKVector2 touchVelVec = GLKVector2Make(touchVel.x, touchVel.y);
    
    if([gestureRecognizer state] == UIGestureRecognizerStateBegan)
        _animation->onTouchTransBegan(touchPosVec);
    else if([gestureRecognizer state] == UIGestureRecognizerStateChanged)
        _animation->onTouchTransChanged(touchPosVec);
    else if([gestureRecognizer state] == UIGestureRecognizerStateEnded)
        _animation->onTouchTransEnded (touchVelVec);
}

- (void) touchesBegan: (NSSet*)   touches
            withEvent: (UIEvent*) event
{
    _animation->onTouchStop();
}

@end
