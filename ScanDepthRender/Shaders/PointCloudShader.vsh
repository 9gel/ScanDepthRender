//
//  Shader.vsh
//  ScanDepthRender
//
//  Created by Nigel Choi on 3/6/14.
//  Copyright (c) 2014 Nigel Choi. All rights reserved.
//

attribute vec4 position;
attribute vec4 color;

varying lowp vec4 colorVarying;

uniform mat4 projectionMatrix;
uniform mat4 modelViewMatrix;
uniform float inverseScale;

void main()
{
    colorVarying = color;
    
    gl_Position = projectionMatrix * modelViewMatrix * position;
    gl_PointSize = 10.0;
//    gl_PointSize = 80.0 / gl_Position.z;
}
