# VoxelWar
*a new voxel first person shooter*

This is the client software for a game called "VoxelWar". You can play this game by connecting to a server with this client.

History:
Ever since the originally free-to-play voxel FPS "Ace Of Spades" was bought by a company with the purpose of commercial distribution, the leftovers of the community have been trying to make a new game. VoxelWar is one of those games, initially started as an alternative AoS client written in C by lecom. At some point, it became clear that 1. maintenance and development of the client in C was too much work with a too big code base 2. the existing AoS server, PySnip, was too complex and the code was written in a bad way, hence the VxW client was rewritten in D and got a new server written in Python. Because Python was too slow and not very suitable for game development, it was rewritten in S-Lang. Right now, the developers are working towards a first release.

Gameplay:
- Bring back the old AoS feeling from anything before 0.54:
	- No free headhunting, if you want to kill someone, you should have to aim your weapon
	- Proper weapon balancing, make the rifle king of long-ranged combat again and SMG short-ranged to middle-ranged
	- Slow-paced gameplay, take your time to think of a good way to defeat the enemy
	- More focus on engineering different buildings
	- More genmaps with a special API for easy map generation
	- Implied classes, mostly equal equipment and abilities for all players, determine your class based on the way you play the game
	- Make fulfilling the game mode's target worth it (e.g. intel/flag "ESP", game mode points)
- Introduction of artillery weapons (mortars atm) as a balancing measure, new "class" and a general feature of the game
- Proper airstrikes (compared to AoS classic) with planes dropping bombs, wich can be shot down (both the planes and the bombs \o/)
- "Reasonable" level of realism (make things feel somewhat relatable to rl, but not exagerate with realism)
- AI players to assist you

What VxW is not and never going to be:
- CoD/CS (don't even think about it, guys)
- AoS classic (not before 0.60, at least)
- BF1
- ArmA (but can serve as a source of "inspiration" for content creators)

Coming soon:
- A broad variety of game modes
- Player-controllable planes, dogfights
- Release of VxW 1.0

# Compiling

If you haven't already installed either DMD or GDC/LDC (improve your framerate) or any other Dlang compiler, you can download the latest version here:

http://dlang.org/download.html

#### On Linux/any POSIX-compliant OSes
1. If you are using Debian or Ubuntu and don't have these installed already:
	```
	sudo apt-get install libsdl2-dev libsdl2-image-dev libpng-dev libjpeg-dev libtiff-dev libenet-dev zlib1g-dev libvorbis-dev libopenal-dev libslang2-dev git -y
	```
    If not, install the dev libraries of SDL2, SDL2_image, libpng, libjpeg, libtiff, ENet (http://enet.bespin.org/), zlib, vorbis, OpenAL, S-Lang (jedsoft.org/slang) and git the way you would do it on your OS.
	
2. A renderer is needed. The default renderer is Voxlap, which you can get with:
	```
	./setup_voxlap_renderer
	```
There's also http://github.com/xtreme8000/aof-opengl, but might not work anymore and it needs to be set up manually

3. To set up all the dependencies, do:

	```
	./configure
	```

4. To finally make the project, do:

	```
	make
	```

	to compile the source into a binary (will be output into the file "main")
	(btw the make script supports the ldc and gdc compilers; "make ll" will compile with LLVM's LTO stuff, which produces the fastest code of all)


#### On Windows

1. Put required DLLs into the directory (libenet.dll, libpng16-16.dll, pthreadGC2.dll, vorbis.dll, zlib1.dll, libgcc_s_dw2-1.dll, libslang.dll, SDL2.dll, vorbisenc.dll, libjpeg-9.dll, 
libtiff-5.dll, SDL2_image.dll, vorbisfile.dll)

2. Create a directory called "derelict" here.

3. Paste the contents of the derelict directories from the repositories from 2.

	(net, openal, vorbis, ogg, util)

4. Run:
	```
	git clone https://github.com/LeComm/SDLang2
	```

5. Run compile.bat

# CREDITS:

lecom - main programming, all the half-assed assets (yea I'm not very good with paint as you see)

Chameleon - contributed assets to the server

bytebit - his own (outdated but possibly still working) OpenGL renderer, a small amount of physics code (player physics, AABB code)

longbyte - for helping out with stuff (convincing the S-Lang creator)

iCherry - helping me porting Voxlap to 64 bit


## Notes

The "derelict/" folder, when set up, contains D bindings to ENet, libogg and Vorbis. This is not the usual way of using derelict, but *DUB* is a nightmare to use and We would rather not rely on such kinds of packaging programs. I actually made my own bindings for SDL2 because derelict breaks all of my stuff on a regular basis (due to API changes) and I couldn't stand having to fix the SDL2 part all the time.
If you somehow acquired this software by means other than `git clone`, you also need DerelictENet, DerelictAL, DerelictUtil, Derelictvorbis and DerelictOgg from github (or somehow get them via Dlang's DUB package manager).

Official compiled versions of this software run way faster on other systems than on windows because of compiler issues arising from stubborn D devs who keep insisting on using microsoft development software above all (and some crappy 30 years old MS-DOS linker written in ASM).
If you want to contribute, we actually mostly manage to get the job done, but improvements of the physics code and Voxlap renderer are always welcome.

## Licensing

VoxelWar uses the S-Lang library under an exception of its GPL license, allowing VoxelWar to use it under the LGPL license.
VoxelWar uses the original S-Lang library, as offered at http://jedsoft.org/slang/

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.