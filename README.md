# VoxelWar
*a new voxel shooter client*

# Compiling

If you haven't already installed DMD, you can download the latest version here:

http://dlang.org/download.html

You need at least one renderer module.
There are two right now, first the software based voxlap renderer and a much newer OpenGL renderer which is faster on new and **OLD** hardware.
- *Voxlap*: http://github.com/LeComm/aofclient-voxlap-renderer
- *OpenGL*: http://github.com/xtreme8000/aof-opengl

Follow the compile steps for your choosen renderer module and procede here after you've copied the renderer's ```renderer.d``` file here as well as other required library files.

#### On Linux
1. If you are using Debian or Ubuntu and don't have these installed already:

sudo apt-get install libsdl2-dev

sudo apt-get install libenet-dev

sudo apt-get install git

If not, install SDL2, ENet and git the way you would do it on your distribution.

2. Open a terminal in this directory and write

```./configure```

to download derelict files

```./compile-derelict```

to compile the derelict files into a compact .a file

```./compile```

to compile the source


#### On Windows

1. Put SDL2.dll and ENet.dll into the directory

2. Download the contents of:

```http://github.com/DerelictOrg/DerelictSDL2```

```http://github.com/DerelictOrg/DerelictENet```

```http://github.com/DerelictOrg/DerelictUtil```

3. Create a directory called "derelict" here.

4. Paste the contents of the derelict directories from the repositories from 2.

(sdl2, enet, util)

5. Run compile.bat


#### Notes

The "derelict/" folder contains D bindings to both ENet and SDL. This is not the usual way of using derelict, but *DUB* is a nightmare to use and We would rather not rely on such kinds of packaging programs.