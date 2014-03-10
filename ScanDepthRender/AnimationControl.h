/*
  This file is part of the Structure SDK.
  Copyright © 2013 Occipital, Inc. All rights reserved.
  http://structure.io
*/

#ifndef __ScannerApp__AnimationControl__
#define __ScannerApp__AnimationControl__

#import <GLKit/GLKit.h>
#import <mach/mach_time.h>

inline double now_seconds ()
{
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    
    uint64_t newTime = mach_absolute_time();

    return ((double)newTime*timebase.numer)/((double)timebase.denom *1e9);
}

class AnimationControl
{
public:
    
    AnimationControl(float screenSizeX, float screenSizeY) {
        _screenSize = GLKVector2Make(screenSizeX, screenSizeY);
        reset();
    }
    
    void reset()
    {
        _previousScale = 1.0;
        _currentScale = 1.0;
        _screenCenter = GLKVector2MultiplyScalar(_screenSize, 0.5);
        _modelOri = GLKVector2MultiplyScalar(_screenSize, 0.5);
        _prevRotMatrix = GLKMatrix4Identity;
        _rotMatrix = GLKMatrix4Identity;
        _dampRatio = GLKVector2Make(0.95, 0.95);
        _rotVelocity = GLKVector2Make(0, 0);
    }
    
    void setInitProjectionRt(GLKMatrix4 projRt)
    {
        _projectionRt = projRt;
    }
    
    void setMeshCenter(GLKVector3 center)
    {
        _meshCenter = center;
    }
    
    // Scale Gesture Control
    void onTouchScaleBegan(float scale)
    {
        _previousScale = _currentScale / scale;
    }
    
    void onTouchScaleChanged(float scale)
    {
        _currentScale = scale * _previousScale;
    }
    
    // Rotation Gesture Control
    void onTouchRotBegan (GLKVector2 &touch)
    {
        _prevRotMatrix = _rotMatrix;
        _touchBegan = touch;
    }
    
    void onTouchRotChanged (GLKVector2 &touch)
    {
        GLKVector2 distMoved = GLKVector2Subtract(touch, _touchBegan);
        GLKVector2 spinDegree = GLKVector2Negate(GLKVector2DivideScalar(distMoved, 300));
        
        GLKMatrix4 rotX = GLKMatrix4MakeYRotation(-spinDegree.x);
        GLKMatrix4 rotY = GLKMatrix4MakeXRotation(-spinDegree.y);
        
        _rotMatrix = GLKMatrix4Multiply(GLKMatrix4Multiply(rotX, rotY), _prevRotMatrix);
    }
    
    void onTouchRotEnded (GLKVector2 vel)
    {
        _rotVelocity = vel;
        _rotStartSeconds = now_seconds();
    }
    
    // Translation Gesture Control
    void onTouchTransBegan (GLKVector2 &touch)
    {
        _panLastPos = touch;
        _prevModelOri = _modelOri;
    }
    
    void onTouchTransChanged(GLKVector2 &touch)
    {
        _modelOri = GLKVector2Add(GLKVector2Subtract(touch, _panLastPos), _prevModelOri);
    }

    void onTouchTransEnded (GLKVector2 vel)
    {
    }
    
    void onTouchStop ()
    {
        _rotVelocity = GLKVector2Make(0, 0);
    }
    
    // Current Scale of the Model
    float currentScale()
    {
        return _currentScale;
    }
    
    // ModelView Matrix in OpenGL Space
    GLKMatrix4 currentModelView()
    {
        GLKMatrix4 trans = GLKMatrix4MakeTranslation(-_meshCenter.x, -_meshCenter.y, -_meshCenter.z);
        GLKMatrix4 viewOri = GLKMatrix4MakeTranslation(0, 0, 4*_meshCenter.z);
        GLKMatrix4 rot = currentRotation();
        GLKMatrix4 scaleProj = GLKMatrix4MakeScale(_currentScale, _currentScale, _currentScale);
        
        GLKMatrix4 modelView = viewOri;
        modelView = GLKMatrix4Multiply(modelView, rot);
        modelView = GLKMatrix4Multiply(modelView, scaleProj);
        modelView = GLKMatrix4Multiply(modelView, trans);
        return modelView;
    }
    
    // Projection Matrix in OpenGL Space
    GLKMatrix4 currentProjRt()
    {
        GLKMatrix4 trans = currentTranslation();
        return GLKMatrix4Multiply(trans, _projectionRt);
    }

    // Rotation animation
    void animate ()
    {
        if(GLKVector2Length(_rotVelocity) > 0)
        {
            double nowSec = now_seconds ();
            double elapsedSec = nowSec - _rotStartSeconds;
            _rotStartSeconds = nowSec;
            
            GLKVector2 distMoved = GLKVector2MultiplyScalar(_rotVelocity, elapsedSec);
            GLKVector2 spinDegree = GLKVector2Negate(GLKVector2DivideScalar(distMoved, 300));
            
            GLKMatrix4 rotX = GLKMatrix4MakeYRotation(-spinDegree.x);
            GLKMatrix4 rotY = GLKMatrix4MakeXRotation(-spinDegree.y);
            _rotMatrix = GLKMatrix4Multiply(GLKMatrix4Multiply(rotX, rotY), _rotMatrix);
            
            _rotVelocity.x *= _dampRatio.x;
            _rotVelocity.y *= _dampRatio.y;
        }
    }
    
private:
    
    GLKMatrix4 currentTranslation()
    {
        GLKVector2 screeDiff = GLKVector2Subtract(_screenCenter, _modelOri);
        GLKMatrix4 trans = GLKMatrix4MakeTranslation(-screeDiff.x/_screenCenter.x,  screeDiff.y/_screenCenter.y, 0);
        
        return trans;
    }
    
    GLKMatrix4 currentRotation ()
    {
        return _rotMatrix;
    }
    
    double _rotStartSeconds;
    
    float _previousScale;
    float _currentScale;
    
    GLKMatrix4 _projectionRt;
    GLKVector3 _meshCenter;
    
    GLKMatrix4 _prevRotMatrix;
    GLKMatrix4 _rotMatrix;
    GLKVector2 _rotVelocity;
    GLKVector2 _dampRatio;
    GLKVector2 _panLastPos;
    GLKVector2 _prevModelOri;
    GLKVector2 _modelOri;
    GLKVector2 _screenCenter;
    GLKVector2 _screenSize;
    GLKVector2 _touchBegan;
};

#endif
