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

#define SCAN_DO_SYNC 1

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

struct AppStatus {
    NSString* const pleaseConnectSensorMessage = @"Please connect Structure Sensor.";
    NSString* const pleaseChargeSensorMessage = @"Please charge Structure Sensor.";
    NSString* const needColorCameraAccessMessage = @"This app requires camera access to capture color.\nAllow access by going to Settings → Privacy → Camera.";
    
    enum SensorStatus
    {
        SensorStatusOk,
        SensorStatusNeedsUserToConnect,
        SensorStatusNeedsUserToCharge,
    };
    
    // Structure Sensor status.
    SensorStatus sensorStatus = SensorStatusOk;
    
    // Whether iOS camera access was granted by the user.
    bool colorCameraIsAuthorized = true;
    
    // Whether there is currently a message to show.
    bool needsDisplayOfStatusMessage = false;
    
    // Flag to disable entirely status message display.
    bool statusMessageDisabled = false;
};

struct Options {
    // The initial scanning volume size will be 0.5 x 0.5 x 0.5 meters
    // (X is left-right, Y is up-down, Z is forward-back)
    GLKVector3 initialVolumeSizeInMeters = GLKVector3Make (0.5f, 0.5f, 0.5f);
    
    // Volume resolution in meters
    float initialVolumeResolutionInMeters = 0.004; // 4 mm per voxel
    
    // The maximum number of keyframes saved in keyFrameManager
    int maxNumKeyFrames = 48;
    
    // Colorizer quality
    STColorizerQuality colorizerQuality = STColorizerHighQuality;
    
    // Take a new keyframe in the rotation difference is higher than 20 degrees.
    float maxKeyFrameRotation = 20.0f * (M_PI / 180.f); // 20 degrees
    
    // Take a new keyframe if the translation difference is higher than 30 cm.
    float maxKeyFrameTranslation = 0.3; // 30cm
    
    // Threshold to consider that the rotation motion was small enough for a frame to be accepted
    // as a keyframe. This avoids capturing keyframes with strong motion blur / rolling shutter.
    float maxKeyframeRotationSpeedInDegreesPerSecond = 1.f;
    
    // Whether we should use depth aligned to the color viewpoint when Structure Sensor was calibrated.
    // This setting may get overwritten to false if no color camera can be used.
    bool useHardwareRegisteredDepth = true;
    
    // Whether the colorizer should try harder to preserve appearance of the first keyframe.
    // Recommended for face scans.
    bool prioritizeFirstFrameColor = true;
    
    // Target number of faces of the final textured mesh.
    int colorizerTargetNumFaces = 50000;
    
    // Focus position for the color camera (between 0 and 1). Must remain fixed one depth streaming
    // has started when using hardware registered depth.
    const float lensPosition = 0.75f;
};

@interface SDRViewController () {
    RENDERER_CLASS *_renderer;
    AnimationControl *_animation;
    
    STSensorController *_sensorController;
    STDepthFrame *_depthFrame;
    STDepthToRgba *_depthToRgba;
    
    AVCaptureSession *_avsession;
    AVCaptureDevice *_videoDevice;
    
    AppStatus _appStatus;
    Options _options;
}
@property (strong, nonatomic) EAGLContext *context;
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
    //[_sensorController setFrameSyncConfig:FRAME_SYNC_CONFIG];

    _depthFrame = [[STDepthFrame alloc] init];
    
        // When the app enters the foreground, we can choose to restart the stream
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillEnterForeground) name:UIApplicationWillEnterForegroundNotification object:nil];

    // Color camera
#if !TARGET_IPHONE_SIMULATOR
    [self setupColorCamera];
#endif
}

- (void)viewDidAppear:(BOOL)animated
{
    static bool fromLaunch = true;
    if (fromLaunch) {
        [self connectAndStartStreaming];
        fromLaunch = false;
    }
    
    float aspect = std::abs(self.view.bounds.size.width / self.view.bounds.size.height);
    GLKMatrix4 projectionMatrix = GLKMatrix4MakePerspective(GLKMathDegreesToRadians(42.87436f), aspect, 0.1f, 100.0f);
    _animation->setInitProjectionRt(projectionMatrix);
    _animation->setMeshCenter(GLKVector3Make(0.0f, 0.0f, -0.6666f));
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
        
        // There's no status about the sensor that we need to display anymore
        _appStatus.sensorStatus = AppStatus::SensorStatusOk;
        [self updateAppStatusMessage];
        
        // Start the color camera, setup if needed
        [self startColorCamera];
        
        // Set sensor stream quality
        STStreamConfig streamConfig   = _options.useHardwareRegisteredDepth ? STStreamConfigRegisteredDepth640x480 : STStreamConfigDepth640x480;
        
        
        // Request that we receive depth frames with synchronized color pairs
        // After this call, we will start to receive frames through the delegate methods
        NSError* error = nil;
        BOOL optionsAreValid = [_sensorController startStreamingWithOptions:@{kSTStreamConfigKey : @(streamConfig),
                                                                              kSTFrameSyncConfigKey : @(STFrameSyncDepthAndRgb),
                                                                              kSTColorCameraFixedLensPositionKey: @(_options.lensPosition),
                                                                              }
                                                                      error:&error];

        _depthToRgba = [[STDepthToRgba alloc] init];

        if (!optionsAreValid)
        {
            NSLog(@"Error during streaming start: %s", [[error localizedDescription] UTF8String]);
            self.statusLabel.text = @"Error during streaming start.";
            return false;
        }

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

////////////////////////////////////////////////////

- (void)showAppStatusMessage:(NSString *)msg {
    _appStatus.needsDisplayOfStatusMessage = true;
    [self.view.layer removeAllAnimations];
    
    [_statusLabel setText:msg];
    [_statusLabel setHidden:NO];
    
    // Progressively show the message label.
    [self.view setUserInteractionEnabled:false];
    [UIView animateWithDuration:0.5f animations:^{
        _statusLabel.alpha = 1.0f;
    }completion:nil];
}

- (void)hideAppStatusMessage {
    
    _appStatus.needsDisplayOfStatusMessage = false;
    [self.view.layer removeAllAnimations];
    
    [UIView animateWithDuration:0.5f
                     animations:^{
                         _statusLabel.alpha = 0.0f;
                     }
                     completion:^(BOOL finished) {
                         // If nobody called showAppStatusMessage before the end of the animation, do not hide it.
                         if (!_appStatus.needsDisplayOfStatusMessage)
                         {
                             [_statusLabel setHidden:YES];
                             [self.view setUserInteractionEnabled:true];
                         }
                     }];
}

- (void)updateAppStatusMessage {
    // Skip everything if we should not show app status messages (e.g. in viewing state).
    if (_appStatus.statusMessageDisabled)
    {
        [self hideAppStatusMessage];
        return;
    }
    
    // First show sensor issues, if any.
    switch (_appStatus.sensorStatus)
    {
        case AppStatus::SensorStatusOk:
        {
            break;
        }
            
        case AppStatus::SensorStatusNeedsUserToConnect:
        {
            [self showAppStatusMessage:_appStatus.pleaseConnectSensorMessage];
            return;
        }
            
        case AppStatus::SensorStatusNeedsUserToCharge:
        {
            [self showAppStatusMessage:_appStatus.pleaseChargeSensorMessage];
            return;
        }
    }
    
    // Then show color camera permission issues, if any.
    if (!_appStatus.colorCameraIsAuthorized)
    {
        [self showAppStatusMessage:_appStatus.needColorCameraAccessMessage];
        return;
    }
    
    // If we reach this point, no status to show.
    [self hideAppStatusMessage];
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
    [_renderer updateWithBounds:self.view.bounds
                     projection:_animation->currentProjRt()
                      modelView:_animation->currentModelView()
                       invScale:1.0f / _animation->currentScale()];
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
    
    // Stop the color camera when there isn't a connected Structure Sensor
    [self stopColorCamera];
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
    
    // Stop the color camera when there isn't a connected Structure Sensor
    [self stopColorCamera];
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
                                 andColorFrame:(STColorFrame *)colorFrame
{
    [self renderDepthFrame:depthFrame];
    [self renderColorFrame:colorFrame.sampleBuffer];
    [_renderer updatePointsWithDepth:_depthFrame image:_cameraImageView.image.CGImage];
}

#pragma mark - Structure Rendering

- (void)renderDepthFrame:(STDepthFrame*)depthFrame
{
    _depthFrame=depthFrame;
    uint8_t *rgbaData = [_depthToRgba convertDepthFrameToRgba:_depthFrame];
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    CGBitmapInfo bitmapInfo;
    bitmapInfo = (CGBitmapInfo)kCGImageAlphaPremultipliedLast;
    bitmapInfo |= kCGBitmapByteOrder16Big;
    
    
    NSData *data = [NSData dataWithBytes:rgbaData length:depthFrame.width * depthFrame.height * sizeof(uint32_t)];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    
    CGImageRef cgImage = CGImageCreate(depthFrame.width,
                                       depthFrame.height,
                                       8,
                                       32,
                                       depthFrame.width * sizeof(uint32_t),
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

#pragma mark -  AVFoundation

- (BOOL)queryCameraAuthorizationStatusAndNotifyUserIfNotGranted {
    // This API was introduced in iOS 7, but in iOS 8 it's actually enforced.
    if ([AVCaptureDevice respondsToSelector:@selector(authorizationStatusForMediaType:)])
    {
        AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
        
        if (authStatus != AVAuthorizationStatusAuthorized)
        {
            NSLog(@"Not authorized to use the camera!");
            
            [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                                     completionHandler:^(BOOL granted)
             {
                 // This block fires on a separate thread, so we need to ensure any actions here
                 // are sent to the right place.
                 
                 // If the request is granted, let's try again to start an AVFoundation session. Otherwise, alert
                 // the user that things won't go well.
                 if (granted)
                 {
                     
                     dispatch_async(dispatch_get_main_queue(), ^(void) {
                         
                         [self startColorCamera];
                         
                         _appStatus.colorCameraIsAuthorized = true;
                         [self updateAppStatusMessage];
                         
                     });
                     
                 }
                 
             }];
            
            return false;
        }
        
    }
    
    return true;
    
}

- (void)setupColorCamera
{
    // If already setup, skip it
    if (_avsession)
        return;
    
    bool cameraAccessAuthorized = [self queryCameraAuthorizationStatusAndNotifyUserIfNotGranted];
    
    if (!cameraAccessAuthorized)
    {
        _appStatus.colorCameraIsAuthorized = false;
        [self updateAppStatusMessage];
        return;
    }
    
    // Use VGA color.
    NSString *sessionPreset = AVCaptureSessionPreset640x480;
    
    // Set up Capture Session.
    _avsession = [[AVCaptureSession alloc] init];
    [_avsession beginConfiguration];
    
    // Set preset session size.
    [_avsession setSessionPreset:sessionPreset];
    
    // Create a video device and input from that Device.  Add the input to the capture session.
    _videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (_videoDevice == nil)
        assert(0);
    
    // Configure Focus, Exposure, and White Balance
    NSError *error;
    
    // Use auto-exposure, and auto-white balance and set the focus to infinity.
    if([_videoDevice lockForConfiguration:&error])
    {
        // Allow exposure to change
        if ([_videoDevice isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure])
            [_videoDevice setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
        
        // Allow white balance to change
        if ([_videoDevice isWhiteBalanceModeSupported:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance])
            [_videoDevice setWhiteBalanceMode:AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance];
        
        // Set focus at the maximum position allowable (e.g. "near-infinity") to get the
        // best color/depth alignment.
        [_videoDevice setFocusModeLockedWithLensPosition:1.0f completionHandler:nil];
        
        [_videoDevice unlockForConfiguration];
    }
    
    //  Add the device to the session.
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:_videoDevice error:&error];
    if (error)
    {
        NSLog(@"Cannot initialize AVCaptureDeviceInput");
        assert(0);
    }
    
    [_avsession addInput:input]; // After this point, captureSession captureOptions are filled.
    
    //  Create the output for the capture session.
    AVCaptureVideoDataOutput* dataOutput = [[AVCaptureVideoDataOutput alloc] init];
    
    // We don't want to process late frames.
    [dataOutput setAlwaysDiscardsLateVideoFrames:YES];
    
    // Use BGRA pixel format.
    [dataOutput setVideoSettings:[NSDictionary
                                  dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
                                  forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
    
    // Set dispatch to be on the main thread so OpenGL can do things with the data
    [dataOutput setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    
    [_avsession addOutput:dataOutput];
    
    if([_videoDevice lockForConfiguration:&error])
    {
        [_videoDevice setActiveVideoMaxFrameDuration:CMTimeMake(1, 30)];
        [_videoDevice setActiveVideoMinFrameDuration:CMTimeMake(1, 30)];
        [_videoDevice unlockForConfiguration];
    }
    
    [_avsession commitConfiguration];
}


- (void)startColorCamera {
    if (_avsession && [_avsession isRunning])
        return;
    
    // Re-setup so focus is lock even when back from background
    if (_avsession == nil)
        [self setupColorCamera];
    
    // Start streaming color images.
    [_avsession startRunning];
}

- (void)stopColorCamera
{
    if ([_avsession isRunning])
    {
        // Stop the session
        [_avsession stopRunning];
    }
    
    _avsession = nil;
    _videoDevice = nil;
}

- (void) captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
#ifdef SCAN_DO_SYNC
    // Pass into the driver. The sampleBuffer will return later with a synchronized depth pair.
    [_sensorController frameSyncNewColorBuffer:sampleBuffer];
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
