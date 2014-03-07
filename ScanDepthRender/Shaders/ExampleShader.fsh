//
//  Shader.fsh
//  ScanDepthRender
//
//  Created by Nigel Choi on 3/6/14.
//  Copyright (c) 2014 Nigel Choi. All rights reserved.
//

varying lowp vec4 colorVarying;

void main()
{
    gl_FragColor = colorVarying;
}
