voxelgameclient - a new voxel shooter client program

notes: the derelict folder contains D bindings to ENet and, in future, SDL. This is not the usual way of using derelict, but DUB is a nightmare to use and I'd rather not rely on such kinds of packaging programs.

To compile finally, you need to add a renderer.d file. The compile script actually doesn't work, it's for stub/dummy renderer.d files.