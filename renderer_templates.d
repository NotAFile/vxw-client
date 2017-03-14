import derelict.sdl2.sdl;
import std.traits;
import std.conv;
import std.algorithm;
import renderer;
import voxlap;
import vector;
import misc;
import gfx;

bool Voxel_IsSolid(T)(T pos) if(__traits(hasMember, T, "x") && __traits(hasMember, T, "y") && __traits(hasMember, T, "z")){
	return cast(bool)isvoxelsolid(cast(uint)pos.x, cast(uint)pos.z, cast(uint)pos.y);
}

bool Voxel_IsSolid(T)(T pos) if(isArray!T){
	return cast(bool)isvoxelsolid(cast(uint)pos[0], cast(uint)pos[0], cast(uint)pos[0]);
}

void Renderer_Draw3DParticle(alias hole_side=false)(immutable in Vector3_t pos, RendererParticleSize_t w, RendererParticleSize_t h, RendererParticleSize_t l, uint col){
	return renderer.Renderer_Draw3DParticle(pos.x, pos.y, pos.z, w, h, l, col);
}

nothrow signed_register_t[2] Project2D(immutable in float xpos, immutable in float ypos, immutable in float zpos, float *dist){
	signed_register_t[2] scrpos;
	float dst=__Project2D(Vector3_t(xpos, ypos, zpos), scrpos[0], scrpos[1]);
	if(dist)
		*dist=dst;
	return scrpos;
}

nothrow signed_register_t[2] Project2D(immutable in float xpos, immutable in float ypos, immutable in float zpos){
	signed_register_t[2] scrpos;
	__Project2D(Vector3_t(xpos, ypos, zpos), scrpos[0], scrpos[1]);
	return scrpos;
}

nothrow signed_register_t[2] Project2D(T)(T coord){
	signed_register_t[2] scrpos;
	__Project2D(Vector3_t(coord.x, coord.y, coord.z), scrpos[0], scrpos[1]);
	return scrpos;
}

nothrow bool Project2D(immutable in float xpos, immutable in float ypos, immutable in float zpos, out signed_register_t scrx, out signed_register_t scry){
	return __Project2D(Vector3_t(xpos, ypos, zpos), scrx, scry)>=0.0;
}

nothrow bool Project2D(immutable in float xpos, immutable in float ypos, immutable in float zpos, out signed_register_t scrx, out signed_register_t scry, out float dist){
	dist=__Project2D(Vector3_t(xpos, ypos, zpos), scrx, scry);
	return dist>=0.0;
}

void Renderer_DrawSprite(Sprite_t *spr){
	return renderer.Renderer_DrawSprite(*spr);
}

void Renderer_FillRect2D(SDL_Rect *rct, uint color){
	color=(color&0xff000000) | ((color&0x00ff0000)>>16) | (color&0x0000ff00) | ((color&0x000000ff)<<16);
	return renderer.Renderer_FillRect2D(rct, cast(ubyte[4]*)&color);
}
