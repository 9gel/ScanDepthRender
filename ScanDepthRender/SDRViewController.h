//
//  SDRViewController.h
//  ScanDepthRender
//
//  Created by Nigel Choi on 3/6/14.
//  Copyright (c) 2014 Nigel Choi. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <GLKit/GLKit.h>
#import <structure/Structure.h>

@interface SDRViewController : GLKViewController <STSensorControllerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>

@property (weak,nonatomic) IBOutlet UILabel* statusLabel;
@property (weak,nonatomic) IBOutlet UIImageView* depthImageView;
@property (weak,nonatomic) IBOutlet UIImageView* cameraImageView;

@end
