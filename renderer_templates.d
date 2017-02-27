import std.traits;
import std.conv;
import renderer;
import voxlap;
import vector;
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

nothrow int[2] Project2D(immutable in float xpos, immutable in float ypos, immutable in float zpos, float *dist){
	int[2] scrpos;
	float dst=__Project2D(xpos, ypos, zpos, scrpos[0], scrpos[1]);
	if(dist)
		*dist=dst;
	return scrpos;
}

nothrow int[2] Project2D(immutable in float xpos, immutable in float ypos, immutable in float zpos){
	int[2] scrpos;
	__Project2D(xpos, ypos, zpos, scrpos[0], scrpos[1]);
	return scrpos;
}

nothrow int[2] Project2D(T)(immutable in T coord) if(__traits(hasMember, coord, "x") && __traits(hasMember, coord, "y") && __traits(hasMember, coord, "z")){
	int[2] scrpos;
	__Project2D(coord.x, coord.y, coord.z, scrpos[0], scrpos[1]);
	return scrpos;
}

nothrow bool Project2D(immutable in float xpos, immutable in float ypos, immutable in float zpos, out int scrx, out int scry){
	return __Project2D(xpos, ypos, zpos, scrx, scry)>=0.0;
}

nothrow bool Project2D(immutable in float xpos, immutable in float ypos, immutable in float zpos, out int scrx, out int scry, out float dist){
	dist=__Project2D(xpos, ypos, zpos, scrx, scry);
	return dist>=0.0;
}

void Renderer_DrawSprite(Sprite_t *spr){
	return renderer.Renderer_DrawSprite(*spr);
}

void Renderer_DrawSprite(SpriteRenderData_t *sprrend, Vector3_t pos, Vector3_t rotation){
	Sprite_t spr;
	spr.model=sprrend.model;
	spr.pos=pos; spr.rot=rotation; spr.density=sprrend.size/Vector3_t(spr.model.size);
	spr.color_mod=sprrend.color_mod; spr.replace_black=sprrend.replace_black;
	spr.check_visibility=sprrend.check_visibility; spr.motion_blur=to!ubyte(sprrend.motion_blur*255.0);
	return renderer.Renderer_DrawSprite(spr);
}
