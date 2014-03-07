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

uniform mat4 modelViewProjectionMatrix;

void main()
{
    colorVarying = color;
    
    gl_Position = modelViewProjectionMatrix * position;
    gl_PointSize = 400.0 / gl_Position.z;
}
