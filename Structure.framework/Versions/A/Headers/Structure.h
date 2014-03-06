/*
    This file is part of the Structure SDK.
    Copyright © 2013 Occipital, Inc. All rights reserved.
    http://structure.io
*/

# pragma once

# include <stdint.h>
# include <stdlib.h>
# import <Foundation/Foundation.h>
# import <AVFoundation/AVFoundation.h>

# define ST_API __attribute__((visibility("default")))

//------------------------------------------------------------------------------
# pragma mark - Sensor Controller Types

/// Sensor Initialization Status
typedef NS_ENUM(NSInteger, STSensorControllerInitStatus)
{
    STSensorControllerInitStatusSuccess             = 0,
    STSensorControllerInitStatusAlreadyInitialized  = 1,
    STSensorControllerInitStatusSensorNotFound		= 2,
    STSensorControllerInitStatusSensorIsWakingUp    = 3,
    STSensorControllerInitStatusOpenFailed          = 4,
};

/// Streaming Interruption Reason
typedef NS_ENUM(NSInteger, STSensorControllerDidStopStreamingReason)
{
    STSensorControllerDidStopStreamingReasonAppBackgrounded = 0
};

/// Stream Configuration
typedef NS_ENUM(NSInteger, StructureStreamConfig)
{
    CONFIG_QVGA_DEPTH = 0,
    CONFIG_QVGA_REGISTERED_DEPTH,
    CONFIG_QVGA_DEPTH_AND_IR,
    CONFIG_QVGA_IR,
    CONFIG_VGA_DEPTH,
    CONFIG_VGA_IR,
    CONFIG_VGA_DEPTH_AND_IR,
    CONFIG_VGA_REGISTERED_DEPTH,
    CONFIG_QVGA_DEPTH_60_FPS,
    CONFIG_NUMS
};

/// Frame Sync Configuration
typedef NS_ENUM(NSInteger, FrameSyncConfig)
{
    FRAME_SYNC_OFF = 0, //Default operation
    FRAME_SYNC_DEPTH_AND_RGB,
    FRAME_SYNC_IR_AND_RGB
};

/// Frame
typedef struct
STFrame
{
    uint16_t* data;
    double    timestamp;
    int       width;
    int       height;
}
STFrame;

/// Depth Frame
typedef STFrame STDepthFrame;

/// Infrared Frame
typedef STFrame STIRFrame;

/** Sensor Info

@note
    This is an opaque type, for now.
*/
struct STSensorInfo;

//------------------------------------------------------------------------------
# pragma mark - Sensor Controller Delegate

/** Sensor Controller Delegate

The interface that your application-specific class must implement in order to receive sensor controller callbacks.

@note Delegate Registration Example

    [ STSensorController sharedController ].delegate = self;

See also:

- STSensorController
*/

# if !defined(__cplusplus) && !defined (HAS_STDCXX)
#   error "Structure requires the C++ runtime."
# endif

@protocol STSensorControllerDelegate  <NSObject>

/// @name Connection Status

/// Notifies the delegate that the controller established a successful connection to the sensor.
- (void) sensorDidConnect;

/// Notifies the delegate that the sensor was disconnected from the controller.
- (void) sensorDidDisconnect;

/** Notifies the delegate that the sensor stopped streaming frames to the controller.

@param reason The reason why the stream was stopped. See: STSensorControllerDidStopStreamingReason.
*/
- (void) sensorDidStopStreaming: (STSensorControllerDidStopStreamingReason) reason;

/// @name Power Management
- (void) sensorDidEnterLowPowerMode;
- (void) sensorDidLeaveLowPowerMode;
- (void) sensorBatteryNeedsCharging; // Will be called on main thread.

@optional

/// @name Colorless Frames

/** Notifies the delegate that the sensor made a new depth frame available to the controller.

@param depthFrame The new depth frame.
*/
- (void) sensorDidOutputDepthFrame: (STDepthFrame*) depthFrame;

/** Notifies the delegate that the sensor made a new IR frame available to the controller.

@param irFrame The new IR frame.
*/
- (void) sensorDidOutputIRFrame: (STIRFrame*) irFrame;

/** @name Color-synchronized Frames

    Frame sync methods will only be used if setFrameSyncConfig: has been configured to sync frames.
    Also, Data will only be delivered if frameSyncNewColorImage: is called every time a new sample buffer is available. The
    driver needs the CMSampleBuffers in order to return them through these methods.
*/

/** Notifies the delegate that the sensor made a new pair of depth and color frames available to the controller.

See also:

- <[STSensorController setFrameSyncConfig:]>
- <[STSensorController frameSyncNewColorImage:]>

@param depthFrame The new depth frame
@param sampleBuffer The new color buffer

*/
- (void) sensorDidOutputSynchronizedDepthFrame: (STDepthFrame*)     depthFrame
                                 andColorFrame: (CMSampleBufferRef) sampleBuffer;

/** Notifies the delegate that the sensor made a new pair of synchronized IR and color frames available to the controller.

See also:

- <[STSensorController setFrameSyncConfig:]>
- <[STSensorController frameSyncNewColorImage:]>

@param irFrame The new IR frame
@param sampleBuffer The new color buffer
*/
- (void) sensorDidOutputSynchronizedIRFrame: (STIRFrame*)        irFrame
                              andColorFrame: (CMSampleBufferRef) sampleBuffer;

@end

//------------------------------------------------------------------------------
# pragma mark - Sensor Controller

/** The sensor controller is the central point that manages all the interactions between the sensor and your application-specific delegate class.

Its only instance is available through the sharedController method.

Your custom delegate object can be registered using its delegate property.

See also:

- <STSensorControllerDelegate>
*/
ST_API
@interface STSensorController : NSObject

/// @name Controller Setup

/**
The STSensorController singleton.

Use it to register your application-specific STSensorControllerDelegate delegate.
*/
+ (STSensorController*) sharedController;

/**
The STSensorControllerDelegate delegate.

It will receive all notifications from the sensor, as well as raw stream data.
*/
@property(nonatomic, assign) id<STSensorControllerDelegate> delegate;

/**
Attempt to connect to the Structure Sensor.

@return Connection has succeeded only if the STSensorControllerInitStatus return value is either one of:

- STSensorControllerInitStatusSuccess
- STSensorControllerInitStatusAlreadyInitialized

@note Many methods (including startStreamingWithConfig:) will have no effect until this method succeeds at initializing the sensor.
*/
- (STSensorControllerInitStatus) initializeSensorConnection;

/**
This will begin streaming data from the sensor and delivering data using the delegate methods

@param config The stream configuration to use. See: StructureStreamConfig.
*/
- (void) startStreamingWithConfig: (StructureStreamConfig) config;

/**
Stop streaming data from the sensor.

After this method is called, there may still be several pending frames delivered to the delegate.
*/
- (void) stopStreaming;

/** Request that the driver should attempt to synchronize depth or IR frames with color frames from AVFoundation.

When frame sync is active, one of the following methods is used in lieu of [STSensorControllerDelegate sensorDidOutputDepthFrame:], depending on the selected configuration:

- [STSensorControllerDelegate sensorDidOutputSynchronizedDepthFrame:andColorFrame:]
- [STSensorControllerDelegate sensorDidOutputSynchronizedIRFrame:andColorFrame:]

You must then repeatedly call frameSyncNewColorImage: from the AVFoundation video capture delegate methods. Otherwise, the sensor controller delegate methods  will never deliver any frames. This is simply because synchronized frames cannot be delivered if there are no color frames to synchronize.

@param config  When **not** equal to FRAME_SYNC_OFF, the driver will use the optional synchronized delegate methods to deliver frames. See: FrameSyncConfig.

@note Frame sync of depth+IR+RGB and 60 FPS depth are not currently supported.
@note For frame sync to be effective, the AVCaptureDevice must be configured to have a min and max framerate of 30fps.
*/
- (void) setFrameSyncConfig: (FrameSyncConfig) config;

/** Give the driver a color frame that will be used to synchronize shutters between the iOS camera and the IR camera.

When receiving the CMSampleBufferRef from AVFoundation, you should only call this one method and do no other processing.
When a synchronized frame is found, one of the optional synchronized STSensorController delegate methods will be called, at which point you can then process/render the sampleBuffer.
*/
- (void) frameSyncNewColorImage: (CMSampleBufferRef) sampleBuffer;

/// @name Sensor Status

/// Checks whether the controlled sensor is connected.
- (bool) isConnected;

/// Checks whether the controlled sensor is in low-power mode.
- (bool) isLowPower;

/// Returns an integer in 0..100 representing the battery charge.
- (int) getBatteryChargePercentage;

/// @name Sensor Information

/// Returns the name of the controlled sensor.
- (NSString*) getName;

/// Returns the serial number of the controlled sensor.
- (NSString*) getSerialNumber;

/// Returns the firmware revision of the controlled sensor.
- (NSString*) getFirmwareRevision;

/// Returns the hardware revision of the controlled sensor.
- (NSString*) getHardwareRevision;

/** Returns the controlled sensor info as a pointer to an opaque type.

See also:

- [STScene initWithContext:frameBufferSize:sensorInfo:freeGLTextureUnit:]
- [STDepthToRgba initWithSensorInfo:]
- [STCubePlacementInitializer initWithCameraInfo:volumeSizeInMeters:]
*/
- (struct STSensorInfo*) getSensorInfo: (StructureStreamConfig) config;

/// @name Advanced Setup

/** Enable or disable an optional dilation of depth values that has the effect of filling holes.

If the streaming mode is changed with startStreamingWithConfig:, this method will need to be called again for it to take effect.

@param enabled Whether hole filtering is enabled.

@note The hole filter is enabled by default.
*/
- (void) setHoleFilterEnabled: (bool) enabled;

/** Enable or disable high sensor gain.

@param enabled When set to YES, the sensor gain will be increased, causing better performance in dark or far away objects at the expense of some bright nearby objects.

@note High gain is disabled by default.
*/
- (void) setHighGain: (bool) enabled;

/**
Specify a new rigid body transformation between the iOS camera and IR camera.

Since each device will have a slightly different RBT, this will improve the quality of registered depth.
A stream stop and restart with registration will be required for this to take effect.
The RBT represents the world motion of the IR camera w.r.t. the RGB camera. The coordinate frame is right handed: X right, Y down, Z out.

@param newRbt This parameter is expected as a pointer to 16 floating point values in _column_ major order. This is the default ordering of Eigen.

@note  Currently the intrinsics assumed in the registration are fixed and set as follows:

    K_RGB_QVGA       = [305.73, 0, 159.69; 0, 305.62, 119.86; 0, 0, 1]
    K_RGB_DISTORTION = [0.2073, -0.5398, 0, 0, 0] --> k1 k2 p1 p2 k3
    K_IR_QVGA        = [288.28,  0, 159.26; 0, 288.24, 120.47; 0, 0, 1]
    K_IR_DISTORTION  = [0, 0, 0, 0, 0] --> k1 k2 p1 p2 k3

@note The following is an example call of this method using the Eigen C++ library (not required).
Eigen is already column major, so we can just take the address of an Isometry3f, which is internally represented by 16 floats.

    - (void) updateRegistration
    {
        [ [STSensorController sharedController] stopStreaming ];

        Eigen::Isometry3f sampleIsometry = Eigen::Isometry3f::Identity();
        Eigen::Vector3f translation = Eigen::Vector3f(0.034, 0, 0.017);

        sampleIsometry.translate(translation);
        sampleIsometry.rotate((Eigen::Matrix3f() << 0.99977, -0.0210634, -0.00412405,
                                                   0.0210795, 0.99977, 0.00391278,
                                                   0.00404069, -0.00399881, 0.999984).finished());

        [ [STSensorController sharedController] setRegistrationRBT: (float*) &sampleIsometry ];

        [ [STSensorController sharedController] startStreamingWithConfig: CONFIG_QVGA_REGISTERED_DEPTH ];
    }
*/
- (void) setRegistrationRBT: (float*) newRbt;

@end
