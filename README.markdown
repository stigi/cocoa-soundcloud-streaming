Cocoa SoundCloud stream player
==============================

This is the extracted stream player I created for an iPhone project.  
It's very basic in it's functionality and you're invited to add all the features that you might need.


Basic Usage
-----------

### Including the lib into your project
You can either include the source files into your project or open the project and build the 'SCAudioStream' target to get you a compiled version of the lib.
The latter will result in a static lib as a fat binary (build for the device and the simulator) in a directory called 'Dist'. Here you'll also find the header files for the lib (in fact it's just one header file 'SCAudioStream.h').
Link the library and also link the AudioToolbox framework.

### Using the lib
For every stream you want to play you create an instance of SCAudioStream.

    SCAudioStream *stream = [[SCAudioStream alloc] initWithURL:streamURL delegate:self];

Don't forget to implement the delegate protocol 'SCAudioStreamDelegate'. This protocol only specifies one method which is used to sign requests if you're about to play oauth protected streams.


License
-------

Copyright 2009 Ullrich Schäfer for SoundCloud Ltd.

Licensed under the Apache License, Version 2.0 (the "License"); you may not
use this file except in compliance with the License. You may obtain a copy of
the License at

 [http://www.apache.org/licenses/LICENSE-2.0][]

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations under
the License.

