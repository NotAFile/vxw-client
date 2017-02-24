version(LDC){
	import ldc_stdlib;
}
version(GNU){
	import gdc_stdlib;
}
import derelict.sdl2.sdl;
import derelict.sdl2.image;
import std.math;
import std.format;
import std.algorithm;
import std.range;
import std.conv;
import std.random;
import std.traits;
import std.string;
import main;
import renderer;
import protocol;
import misc;
import world;
import ui;
import vector;
import script;
import core.stdc.stdio;

SDL_Window *scrn_window=null;

RendererTexture_t font_texture=null;
SDL_Surface *font_surface=null;

RendererTexture_t borderless_font_texture=null;
SDL_Surface *borderless_font_surface=null;
uint FontWidth, FontHeight;
ubyte font_index=255;

RendererTexture_t minimap_texture;
SDL_Surface *minimap_srfc;

MenuElement_t *ProtocolBuiltin_ScopePicture;

uint Font_SpecialColor=0xff000000;

uint ScreenXSize, ScreenYSize;
float ScreenSizeRatio=1.0;

//Ignore this
uint WindowXSize, WindowYSize;

Vector3_t CameraRot=Vector3_t(0.0, 0.0, 0.0), CameraPos=Vector3_t(0.0, 0.0, 0.0);
Vector3_t MouseRot=Vector3_t(0.0, -90.0, 0.0);
float X_FOV=90.0, Y_FOV=90.0;

float[3][ParticleSizeTypes] ParticleSizeRatios;

Model_t*[] Mod_Models;
RendererTexture_t[] Mod_Pictures;
SDL_Surface*[] Mod_Picture_Surfaces;
uint[2][] Mod_Picture_Sizes;

uint Enable_Shade_Text=0;
uint LetterPadding=0;
immutable bool Dank_Text=false;

Vector3_t TerrainOverview;
float TerrainOverviewRotation;

bool Do_Sprite_Visibility_Checks=true;

uint FrameCounter=0;

//At the moment, there's at least one "hidden" undiscovered object model modification bug that can cause occassional unexpected crashes
debug{
	immutable bool Enable_Object_Model_Modification=false;
}
else{
	immutable bool Enable_Object_Model_Modification=true;
}

float Current_Blur_Amount=0.0, BlurAmount=0.0, BaseBlurAmount=0.0, BlurAmountDecay=.3;
float Current_Shake_Amount=0.0, ShakeAmount=0.0, BaseShakeAmount=0.0, ShakeAmountDecay=1.5;

ubyte MiniMapZPos=250, InvisibleZPos=0, StartZPos=1;

Model_t *ProtocolBuiltin_BlockBuildWireframe;

float SmokeAmount;

void Init_Gfx(){
	DerelictSDL2.load();
	DerelictSDL2Image.load();
	if(SDL_Init(SDL_INIT_TIMER | SDL_INIT_VIDEO | SDL_INIT_EVENTS))
		writeflnlog("[WARNING] SDL2 didn't initialize properly: %s", SDL_GetError());
	if(IMG_Init(IMG_INIT_PNG)!=IMG_INIT_PNG)
		writeflnlog("[WARNING] IMG for PNG didn't initialize properly: %s", IMG_GetError());
	SDL_SetHintWithPriority(toStringz("SDL_HINT_WINDOWS_NO_CLOSE_ON_ALT_F4"), toStringz("1"), SDL_HINT_OVERRIDE);
	Renderer_Init();
	WindowXSize=Config_Read!uint("resolution_x"); WindowYSize=Config_Read!uint("resolution_y");
	scrn_window=SDL_CreateWindow("Voxelwar", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, WindowXSize, WindowYSize, Renderer_WindowFlags
	| SDL_WINDOW_RESIZABLE | (Config_Read!bool("fullscreen")!=0 ? SDL_WINDOW_FULLSCREEN : 0));
	Change_Resolution(WindowXSize, WindowYSize);
	{
		SDL_Surface *font_surface=SDL_LoadBMP("./Ressources/Default/Font.png");
		if(font_surface){
			Set_Font(font_surface);
			SDL_FreeSurface(font_surface);
		}
	}
	SmokeAmount=Renderer_SmokeRenderSpeed*Config_Read!float("smoke")*10.0;
}

void Change_Resolution(uint newxsize, uint newysize){
	if(Config_Read!float("upscale")>=0){
		float lsize=sqrt(cast(float)(WindowXSize*WindowXSize+WindowYSize*WindowYSize));
		ScreenSizeRatio=1.0f-.99f*(1.0f-1.0f/(lsize/1000.0f))*Config_Read!float("upscale");
	}
	else{
		ScreenSizeRatio=1.0f;
	}
	Config_Write("resolution_x", newxsize); Config_Write("resolution_y", newysize);
	ScreenXSize=WindowXSize=newxsize; ScreenYSize=WindowYSize=newysize;
	newxsize=cast(uint)(WindowXSize*ScreenSizeRatio); newysize=cast(uint)(WindowYSize*ScreenSizeRatio);
	Renderer_SetUp(newxsize, newysize);
	Renderer_SetQuality(Config_Read!float("renderquality"));
	foreach(ref elem; MenuElements){
		ConvertScreenCoords(elem.fxpos, elem.fypos, elem.xpos, elem.ypos);
		ConvertScreenCoords(elem.fxsize, elem.fysize, elem.xsize, elem.ysize);
	}
	ParticleSizeRatios=[
		ParticleSizeTypes.Normal: [.1, .1, .1],
		ParticleSizeTypes.BlockDamageParticle: [.05, .05, .05],
		ParticleSizeTypes.DamagedObjectParticle: [.1, .1, .1],
		ParticleSizeTypes.BlockBreakParticle: [.25, .25, .25]
	];
	foreach(sizetype; EnumMembers!ParticleSizeTypes){
		RendererParticleSize_t[3] pixelsize=Renderer_GetParticleSize(ParticleSizeRatios[sizetype][0], ParticleSizeRatios[sizetype][1], ParticleSizeRatios[sizetype][2]);
		ParticleSizes[sizetype]=ParticleSize_t();
		ParticleSizes[sizetype].w=pixelsize[0]; ParticleSizes[sizetype].h=pixelsize[1]; ParticleSizes[sizetype].l=pixelsize[2];
	}
}

SDL_Surface *MapLoadingSrfc;
RendererTexture_t MapLoadingTex;
void Gfx_MapLoadingStart(uint xsize, uint zsize){
	MapLoadingSrfc=SDL_CreateRGBSurface(0, xsize, zsize, 32, 0, 0, 0, 0);
	(cast(uint*)MapLoadingSrfc.pixels)[0..xsize*zsize]=0;
	MapLoadingTex=Renderer_NewTexture(xsize, zsize, true);
	SDL_SetWindowTitle(scrn_window, toStringz("[VoxelWar] Loading map \""~CurrentMapName~"\" ..."));
}

@save void Gfx_OnMapDataAdd(uint[] loading_map){
	uint[] map_pixels=cast(uint[])(cast(uint*)MapLoadingSrfc.pixels)[0..MapLoadingSrfc.w*MapLoadingSrfc.h];
	uint maxx, maxz;
	SDL_SetWindowTitle(scrn_window, toStringz("[VoxelWar] Loading map \""~CurrentMapName~"\" ... ("~to!string(loading_map.length*400/MapTargetSize)~"%)"));
	try{
		uint map_ind=0;
		for(uint z=0; z<MapLoadingSrfc.h; z++){
			for(uint x=0; x<MapLoadingSrfc.w; x++){
				int y=0;
				uint min_y=uint.max;
				while(1){
					uint header=loading_map[map_ind];
					int datasize=(header)&255, col_start2=(header>>8)&255, col_end2=(header>>16)&255;
					int col_height2=col_end2-col_start2;
					uint color_ind=map_ind-col_start2+1;
					if(col_start2<min_y){
						min_y=col_start2;
						map_pixels[x+z*MapLoadingSrfc.w]=loading_map[color_ind+col_start2];
					}
					if(!datasize){
						map_ind+=col_height2+2;
						break;
					}	
					map_ind+=datasize;
					int airstart=(loading_map[map_ind]>>24)&255;
					color_ind=map_ind-airstart;
				}
			}
		}
	}
	catch(core.exception.RangeError){}
}

void Gfx_OnMapLoadFinish(){
	if(MapLoadingSrfc)
		SDL_FreeSurface(MapLoadingSrfc);
	if(MapLoadingTex)
		Renderer_DestroyTexture(MapLoadingTex);
	SDL_SetWindowTitle(scrn_window, toStringz("VoxelWar"));
}

void Set_ModFile_Font(ubyte index){
	font_index=index;
	Set_Font(Mod_Picture_Surfaces[index]);
}

void Set_Font(SDL_Surface *ffnt){
	uint prev_ck;
	SDL_GetColorKey(ffnt, &prev_ck);
	SDL_SetColorKey(ffnt, SDL_TRUE, 0x00ff00ff);
	FontWidth=ffnt.w; FontHeight=ffnt.h;
	SDL_Surface *fnt=ffnt;
	for(uint i=0; i<Enable_Shade_Text; i++){
		SDL_Surface *s=Shade_Text(fnt);
		if(i)
			SDL_FreeSurface(fnt);
		fnt=s;
	}
	if(font_texture)
		Renderer_DestroyTexture(font_texture);
	font_texture=Renderer_TextureFromSurface(fnt);
	font_surface=fnt;
	if(borderless_font_texture)
		Renderer_DestroyTexture(borderless_font_texture);
	borderless_font_surface=SDL_ConvertSurfaceFormat(ffnt, ffnt.format.format, 0);
	borderless_font_texture=Renderer_TextureFromSurface(borderless_font_surface);
	SDL_SetColorKey(ffnt, SDL_TRUE, prev_ck);
}

void Set_MiniMap_Size(uint xsize, uint ysize){
	if(minimap_srfc){
		if(xsize==minimap_srfc.w && ysize==minimap_srfc.h)
			return;
	}
	if(minimap_srfc)
		SDL_FreeSurface(minimap_srfc);
	if(minimap_texture)
		Renderer_DestroyTexture(minimap_texture);
	SDL_Surface *tmp=SDL_CreateRGBSurface(0, xsize, ysize, 32, 0, 0, 0, 0);
	minimap_srfc=SDL_ConvertSurfaceFormat(tmp, SDL_PIXELFORMAT_ABGR8888, 0);
	SDL_FreeSurface(tmp);
	minimap_texture=Renderer_NewTexture(minimap_srfc.w, minimap_srfc.h, true);
}


bool MiniMap_SurfaceChanged=false;
void Update_MiniMap(){
	uint x, y, z;
	uint *pixel_ptr=cast(uint*)minimap_srfc.pixels;
	for(z=0; z<MapZSize; z++){
		for(x=0; x<MapXSize; x++){
			uint col=Voxel_GetColor(x, Voxel_GetHighestY(x, 0, z), z);
			uint a=(col>>24)&255, r=(col>>16)&255, g=(col>>8)&255, b=col&255;
			r*=a; g*=a; b*=a;
			//r=min(r>>7, 255); g=min(g>>7, 255); b=min(b>>7, 255);
			r>>=7; g>>=7; b>>=7;
			r-=(r>255)*(r-255); g-=(g>255)*(g-255); b-=(b>255)*(b-255);
			col=(r<<16) | (g<<8) | b;
			pixel_ptr[x]=col&0x00ffffff;
		}
		pixel_ptr=cast(uint*)((cast(ubyte*)pixel_ptr)+minimap_srfc.pitch);
	}
	MiniMap_SurfaceChanged=true;
}

uint *Pixel_Pointer(SDL_Surface *s, int x, int y){
	return cast(uint*)((cast(ubyte*)s.pixels)+(x<<2)+(y*s.pitch));
}

//This is very buggy (or at least causes a lot of bugs), but I haven't found anything yet
SDL_Surface *Shade_Text(SDL_Surface *srfc){
	LetterPadding++;
	uint LetterWidth=(srfc.w+LetterPadding*16*2)/16, LetterHeight=(srfc.h+LetterPadding*16*2)/16;
	SDL_Surface *dst=SDL_CreateRGBSurface(0, 16*LetterWidth, 16*LetterHeight, 32, 0, 0, 0, 0);
	//SDL_FillRect crashes here, so we're filling dst manually
	uint ColorKey;
	SDL_GetColorKey(srfc, &ColorKey);
	ColorKey&=0x00ffffff;
	(cast(uint*)dst.pixels)[0..dst.w*dst.h]=ColorKey;
	for(uint lx=0; lx<16; lx++){
		for(uint ly=0; ly<16; ly++){
			uint srcletterxp=lx*FontWidth/16, srcletteryp=ly*FontHeight/16;
			uint dstletterxp=lx*LetterWidth+LetterPadding, dstletteryp=ly*LetterHeight+LetterPadding;
			//TL;DR this could be an SDL_BlitSurface call (if it didn't crash or fuck up)
			for(uint y=0; y<FontHeight/16; y++){
				for(uint x=0; x<FontWidth/16; x++){
					*Pixel_Pointer(dst, dstletterxp+x, dstletteryp+y)=*Pixel_Pointer(srfc, srcletterxp+x, srcletteryp+y)&0x00ffffff;
				}
			}
		}
	}
	//NOTE: srfc passed to the function gets freed somewhere else
	srfc=dst;
	dst=SDL_ConvertSurfaceFormat(srfc, srfc.format.format, 0);
	for(uint lx=0; lx<16; lx++){
		for(uint ly=0; ly<16; ly++){
			uint letterxp=lx*LetterWidth, letteryp=ly*LetterHeight;
			for(uint y=0; y<dst.h/16; y++){
				for(uint x=0; x<dst.w/16; x++){
					if(*Pixel_Pointer(srfc, letterxp+x, letteryp+y)!=ColorKey)
						continue;
					bool upc=y>0 ? ((*Pixel_Pointer(srfc, letterxp+x, letteryp+y-1)&0x00ffffff)!=ColorKey) : false;
					bool lfc=x>0 ? ((*Pixel_Pointer(srfc, letterxp+x-1, letteryp+y)&0x00ffffff)!=ColorKey) : false;
					bool rgc=x<(dst.w/16-1) ? ((*Pixel_Pointer(srfc, letterxp+x+1, letteryp+y)&0x00ffffff)!=ColorKey) : false;
					bool lwc=y<(dst.h/16-1) ? ((*Pixel_Pointer(srfc, letterxp+x, letteryp+y+1)&0x00ffffff)!=ColorKey) : false;
					if(upc || lfc || rgc || lwc){
						*Pixel_Pointer(dst, letterxp+x, letteryp+y)=0xff909090;
					}
				}
			}
		}
	}
	SDL_FreeSurface(srfc);
	SDL_SetColorKey(dst, SDL_TRUE, ColorKey);
	FontWidth=dst.w; FontHeight=dst.h;
	return dst;
}

void Render_Text_Line(uint xpos, uint ypos, uint color, string line, RendererTexture_t font, uint font_w, uint font_h, uint letter_padding, float xsizeratio=1.0, float ysizeratio=1.0){
	SDL_Rect lrect, fontsrcrect;
	if(!font)
		return;
	lrect.x=xpos; lrect.y=ypos;
	uint padding;
	ubyte old_r, old_g, old_b;
	ubyte[3] cmod;
	uint bgcol;
	if(color!=Font_SpecialColor){
		fontsrcrect.w=font_w/16; fontsrcrect.h=font_h/16;
		padding=letter_padding*2;
		cmod=[cast(ubyte)((color>>16)&255),cast(ubyte)((color>>8)&255),cast(ubyte)(color&255)];
	}
	else{
		letter_padding=0;
		fontsrcrect.w=borderless_font_surface.w/16-letter_padding*2; fontsrcrect.h=borderless_font_surface.h/16-letter_padding*2;
		font=borderless_font_texture;
		padding=0;
		bgcol=0xff0000a0;
		cmod=[(bgcol>>16)&255, (bgcol>>8)&255, bgcol&255];
		cmod[]=~cmod[];
	}
	lrect.w=to!int(to!float(fontsrcrect.w)*xsizeratio); lrect.h=to!int(to!float(fontsrcrect.h)*ysizeratio);
	if(Dank_Text){
		lrect.w++; lrect.h++;
	}
	uint[2] texsize=[font_surface.w, font_surface.h];
	foreach(letter; line){
		bool letter_processed=true;
		switch(letter){
			case '\n':lrect.x=xpos; lrect.y+=lrect.h-padding; break;
			case '	':lrect.x+=(lrect.w-padding*xsizeratio)*5; break;
			default:letter_processed=false; break;
		}
		if(letter_processed) continue;
		fontsrcrect.x=(letter%16)*fontsrcrect.w;
		fontsrcrect.y=(letter/16)*fontsrcrect.h;
		if(color==Font_SpecialColor)
			Renderer_FillRect(&lrect, bgcol);
		Renderer_Blit2D(font, &texsize, &lrect, 255, &cmod, &fontsrcrect);
		lrect.x+=lrect.w-padding*xsizeratio;
	}
}

enum ParticleSizeTypes{
	Normal=0, BlockDamageParticle=1, DamagedObjectParticle=2, BlockBreakParticle=3
}

struct ParticleSize_t{
	RendererParticleSize_t w, h, l;
}

ParticleSize_t[ParticleSizeTypes] ParticleSizes;

uint[][] Player_List_Table;

void Render_World(alias UpdateGfx=true)(bool Render_Cursor){
	Renderer_DrawVoxels();
	for(uint p=0; p<Players.length; p++){
		Render_Player(p);
	}
	if(ProtocolBuiltin_BlockBuildWireframe) {
		ItemType_t *type = &ItemTypes[Players[LocalPlayerID].Equipped_Item().type];
		if(type.block_damage_range || (type.is_weapon && !type.Is_Gun())){
			auto rc=RayCast(CameraPos, Players[LocalPlayerID].dir, ItemTypes[Players[LocalPlayerID].Equipped_Item().type].block_damage_range);
			if(rc.colldist<=type.block_damage_range && rc.collside){
				Sprite_t spr;
				spr.rhe=0.0; spr.rti=0.0; spr.rst=0.0;
				Vector3_t wfpos=Vector3_t(rc.x, rc.y, rc.z)-Players[LocalPlayerID].dir.sgn().filter(rc.collside==1, rc.collside==2, rc.collside==3)+.5;
				spr.xpos=wfpos.x; spr.ypos=wfpos.y; spr.zpos=wfpos.z;
				spr.xdensity=1.0/ProtocolBuiltin_BlockBuildWireframe.xsize; spr.ydensity=1.0/ProtocolBuiltin_BlockBuildWireframe.ysize;
				spr.zdensity=1.0/ProtocolBuiltin_BlockBuildWireframe.zsize;
				spr.color_mod=(Players[LocalPlayerID].color&0x00ffffff) | 0xff000000;
				spr.replace_black=spr.color_mod;
				spr.model=ProtocolBuiltin_BlockBuildWireframe;
				Renderer_DrawWireframe(&spr);
			}
		}
	}
	
	RendererParticleSize_t particle_w=ParticleSizes[ParticleSizeTypes.BlockDamageParticle].w, particle_h=ParticleSizes[ParticleSizeTypes.BlockDamageParticle].h,
	particle_l=ParticleSizes[ParticleSizeTypes.BlockDamageParticle].l;
	foreach(ref bdmg; BlockDamage){
		foreach(ref prtcl; bdmg.particles){
			Renderer_Draw3DParticle!(true)(prtcl.x, prtcl.y, prtcl.z, particle_w, particle_h, particle_l, prtcl.col);
		}
	}
	particle_w=ParticleSizes[ParticleSizeTypes.DamagedObjectParticle].w, particle_h=ParticleSizes[ParticleSizeTypes.DamagedObjectParticle].h,
	particle_l=ParticleSizes[ParticleSizeTypes.DamagedObjectParticle].l;
	foreach(ref dmgobj_id; DamagedObjects){
		Object_t *dmgobj=&Objects[dmgobj_id];
		foreach(ref prtcl; dmgobj.particles){
			Renderer_Draw3DParticle!(true)(prtcl.x, prtcl.y, prtcl.z, particle_w, particle_h, particle_l, prtcl.col);
		}
	}
	particle_w=ParticleSizes[ParticleSizeTypes.Normal].w, particle_h=ParticleSizes[ParticleSizeTypes.Normal].h,
	particle_l=ParticleSizes[ParticleSizeTypes.Normal].l;
	foreach(ref p; Particles){
		if(!p.timer)
			continue;
		static if(UpdateGfx){
			if(p.timer)
				p.timer--;
			Vector3_t newpos=p.pos+p.vel;
			bool y_coll=false;
			if(Voxel_IsSolid(toint(newpos.x), toint(newpos.y), toint(newpos.z))){
				bool in_solid=Voxel_IsSolid(toint(p.pos.x), toint(p.pos.y), toint(p.pos.z));
				if(Voxel_IsSolid(toint(newpos.x), toint(p.pos.y), toint(p.pos.z)))
					p.vel.x=-p.vel.x;
				if(Voxel_IsSolid(toint(p.pos.x), toint(p.pos.y), toint(newpos.z)))
					p.vel.z=-p.vel.z;
				if(Voxel_IsSolid(toint(p.pos.x), toint(newpos.y), toint(p.pos.z))){
					y_coll=true;
					p.vel.y=-p.vel.y*.9;
					p.vel*=.5;
				}
				else{
					p.vel*=.5;
				}
				if(in_solid && (p.col&0xff000000)!=0xff000000){
					p.timer=0;
					continue;
				}
			}
			else{
				p.pos+=p.vel;
			}
			p.vel.y+=.005;
		}
		Renderer_Draw3DParticle(p.pos, particle_w, particle_h, particle_l, p.col);
	}
	particle_w=ParticleSizes[ParticleSizeTypes.BlockBreakParticle].w, particle_h=ParticleSizes[ParticleSizeTypes.BlockBreakParticle].h,
	particle_l=ParticleSizes[ParticleSizeTypes.BlockBreakParticle].l;
	foreach(ref p; BlockBreakParticles){
		if(!p.timer)
			continue;
		static if(UpdateGfx){
			if(p.timer)
				p.timer--;
			Vector3_t newpos=p.pos+p.vel;
			bool y_coll=false;
			if(Voxel_IsSolid(toint(newpos.x), toint(newpos.y), toint(newpos.z))){
				if(Voxel_IsSolid(toint(newpos.x), toint(p.pos.y), toint(p.pos.z)))
					p.vel.x=-p.vel.x;
				if(Voxel_IsSolid(toint(p.pos.x), toint(newpos.y), toint(p.pos.z))){
					y_coll=true;
					p.vel.y=-p.vel.y;
				}
				if(Voxel_IsSolid(toint(p.pos.x), toint(p.pos.y), toint(newpos.z)))
					p.vel.z=-p.vel.z;
				p.vel*=.3;
			}
			else{
				p.pos+=p.vel;
			}
			p.vel.y+=.005;
		}
		Renderer_Draw3DParticle(p.pos, particle_w, particle_h, particle_l, p.col);
	}
	foreach(ref effect; ExplosionEffectSprites){
		if(effect.size>=1.0)
			continue;
		Renderer_DrawSprite(&effect.spr);
		static if(UpdateGfx){
			float size=effect.maxsize*effect.size;
			effect.spr.xdensity=size/effect.spr.model.xsize; effect.spr.ydensity=size/effect.spr.model.ysize; effect.spr.zdensity=size/effect.spr.model.zsize;
			effect.size+=WorldSpeed*.5/(1.0+effect.size*10.0);
		}
	}
	while(ExplosionEffectSprites.length){
		if(ExplosionEffectSprites[$-1].size>=1.0)
			ExplosionEffectSprites.length--;
		else
			break;
	}
	while(Particles.length){
		if(!Particles[$-1].timer)
			Particles.length--;
		else
			break;
	}
	while(BlockBreakParticles.length){
		if(!BlockBreakParticles[$-1].timer)
			BlockBreakParticles.length--;
		else
			break;
	}
	{
		Model_t *[] split_models;
		Vector3_t[] split_pos;
		Vector3_t[] split_vel;
		uint[] split_counter;
		foreach(ref debris; Debris_Parts){
			if(debris.timer){
				debris.Update(WorldSpeed);
				if(!debris.timer && debris.obj.spr.model.voxels.length>4){
					split_models~=(*debris.obj.spr.model)/2;
					split_pos~=debris.obj.pos;
					split_pos~=debris.obj.pos;
					split_vel~=debris.obj.vel;
					split_vel~=debris.obj.vel;
					split_counter~=debris.split_counter;
					split_counter~=debris.split_counter;
				}
			}
		}
		while(Debris_Parts.length){
			if(!Debris_Parts[$-1].timer)
				Debris_Parts.length--;
			else
				break;
		}
		foreach(ind, model; split_models){
			auto d=Debris_t(split_pos[ind], model);
			d.obj.vel=split_vel[ind]+RandomVector()*Vector3_t(d.obj.spr.model.size).length*(1.0/(split_counter[ind]+1))*(split_counter[ind] ? 1.0 : 3.0);
			d.split_counter=split_counter[ind]+1;
			Debris_Parts~=d;
		}
	}
	{
		foreach(ref bullet; Bullets){
			if(bullet.item_type_sprite==null)
				continue;
			bullet.dist+=WorldSpeed;
			if(bullet.dist>=bullet.maxdist){
				bullet.item_type_sprite=null;
				continue;
			}
			Vector3_t pos=bullet.startpos+bullet.vel*bullet.dist;
			bullet.item_type_sprite.xpos=pos.x; bullet.item_type_sprite.ypos=pos.y; bullet.item_type_sprite.zpos=pos.z;
			bullet.item_type_sprite.rhe=bullet.sprrot.x; bullet.item_type_sprite.rti=bullet.sprrot.y; bullet.item_type_sprite.rst=bullet.sprrot.z;
			Renderer_DrawSprite(bullet.item_type_sprite);
		}
		while(Bullets.length){
			if(Bullets[$-1].item_type_sprite==null)
				Bullets.length--;
			else
				break;
		}
	}
	foreach(obj; Objects){
		if(!obj.visible)
			continue;
		obj.Render();
	}
	if(SmokeAmount){
		struct DrawSmokeCircleParams{
			float dst;
			uint color, alpha;
			int size;
			float xpos, ypos, zpos;
		}
		DrawSmokeCircleParams[] params;
		float SmokeParticleSizeIncrease=1.0f+WorldSpeed*.03f/SmokeAmount, SmokeParticleAlphaDecay=(1.0f*.99f)/SmokeParticleSizeIncrease;
		float DenseSmokeParticleSizeIncrease=1.0f+WorldSpeed*.01f/SmokeAmount, DenseSmokeParticleAlphaDecay=(1.0f*.99f)/DenseSmokeParticleSizeIncrease;
		foreach(ref p; SmokeParticles){
			if(!p.alpha)
				continue;
			static if(UpdateGfx){
				Vector3_t npos=p.pos+p.vel;
				if(!Voxel_IsSolid(npos.x, npos.y, npos.z)){
					p.pos=npos;
					p.size*=SmokeParticleSizeIncrease; p.alpha*=SmokeParticleAlphaDecay;
				}
				else{
					p.size*=DenseSmokeParticleSizeIncrease; p.alpha*=DenseSmokeParticleAlphaDecay;
				}
				if(p.alpha<1.0f/256.0f)
					p.alpha=0f;
				if(p.size>p.remove_size)
					p.alpha=0f;
				p.vel+=RandomVector()*.00001f*p.size;	
				p.vel.y-=.001;
				p.vel*=.96f;
			}
			float dst;
			int scrx, scry;
			if(!Project2D(p.pos.x, p.pos.y, p.pos.z, scrx, scry, dst))
				continue;
			if(dst<=0.0)
				continue;
			uint size=cast(uint)(p.size*90.0f/X_FOV/dst);
			uint color=p.col;
			uint alpha=cast(uint)(p.alpha*255.0f);
			params~=DrawSmokeCircleParams(dst, color, alpha, size, p.pos.x, p.pos.y, p.pos.z);
		}
		params.sort!("a.dst>b.dst");
		for(uint i=0; i<params.length; i++){
			DrawSmokeCircleParams *p=&params[i];
			Renderer_DrawSmokeCircle(p.xpos, p.ypos, p.zpos, p.size, p.color, p.alpha, p.dst);
		}
		params.length=0;
		while(SmokeParticles.length){
			if(!SmokeParticles[$-1].alpha)
				SmokeParticles.length--;
			else
				break;
		}
	}
	Renderer_UpdateFlashes!UpdateGfx(WorldSpeed);
}

void MenuElement_Draw(MenuElement_t* e){
	return MenuElement_Draw(e, e.xpos, e.ypos, e.xsize, e.ysize);
}

void MenuElement_Draw(MenuElement_t* e, int x, int y, int w, int h) {
	if(e.inactive() || !w || !h) {
		return;
	}
	SDL_Rect r={x, y, w, h};
	if((e.icolor_mod&0x00ffffff)!=0x00ffffff) { //bcolor_mod exists
		ubyte[3] cmod=proper_reverse(e.bcolor_mod);
		Renderer_Blit2D(Mod_Pictures[e.picture_index], &Mod_Picture_Sizes[e.picture_index], &r, e.transparency, &cmod);
	} else {
		Renderer_Blit2D(Mod_Pictures[e.picture_index], &Mod_Picture_Sizes[e.picture_index], &r, e.transparency);
	}
}

void Render_Screen(){
	FrameCounter++;
	bool Render_Local_Player=false;
	if(Joined_Game()){
		Render_Local_Player|=Players[LocalPlayerID].Spawned && Players[LocalPlayerID].InGame;
	}
	if(LoadedCompleteMap){
		Renderer_SetCamera(CameraRot.x, CameraRot.y, CameraRot.z, X_FOV, Y_FOV, CameraPos.x, CameraPos.y, CameraPos.z);
		{
			uint[3] fog=[(Base_Fog_Color>>16)&255, (Base_Fog_Color>>8)&255, Base_Fog_Color&255];
			double fog_sum=1.0;
			float visibility=Base_Visibility_Range;
			float effect_blur=0.0;
			float effect_shake=0.0;
			float brightness=1.0;
			foreach(effect; EnvironmentEffectSlots){
				fog[0]+=effect.fog[0]*effect.fog[3]/255; fog[1]+=effect.fog[1]*effect.fog[3]/255; fog[2]+=effect.fog[2]*effect.fog[3]/255;
				fog_sum+=effect.fog[3]/255.0;
				visibility*=effect.visibility;
				effect_blur+=effect.blur;
				effect_shake+=effect.shake;
				brightness*=effect.brightness;
			}
			fog_sum/=brightness*.5+.5;
			fog[0]/=fog_sum; fog[1]/=fog_sum; fog[2]/=fog_sum;
			uint visrange=to!uint(visibility);
			uint fogcol=(fog[0]<<16) | (fog[1]<<8) | (fog[2]);
			if(Current_Fog_Color!=fogcol || Current_Visibility_Range!=visrange){
				Current_Fog_Color=fogcol; Current_Visibility_Range=visrange;
				Renderer_SetFog(fogcol, visrange);
			}
			if(Current_Blur_Amount!=effect_blur+BlurAmount+BaseBlurAmount){
				Current_Blur_Amount=effect_blur+BlurAmount+BaseBlurAmount;
			}
			Current_Shake_Amount=effect_shake+ShakeAmount+BaseShakeAmount;
			Set_Sun(Sun_Position, brightness);
			BlurAmount/=1.0+BlurAmountDecay*WorldSpeed;
			ShakeAmount/=1.0+ShakeAmountDecay*WorldSpeed;
		}
		
		if(Render_Local_Player){
			float mousexvel=MouseMovedX*Config_Read!float("mouse_accuracy")*X_FOV/90.0, mouseyvel=MouseMovedY*Config_Read!float("mouse_accuracy")*Y_FOV/90.0;
			if(!Menu_Mode){
				if(Players[LocalPlayerID].items.length){
					if(ItemTypes[Players[LocalPlayerID].items[Players[LocalPlayerID].item].type].is_weapon){
						if(MouseRightClick){
							MouseRot.x+=mouseyvel*(uniform01()*2.0-1.0)*.75; MouseRot.y+=mousexvel*(uniform01()*2.0-1.0)*.75;
							mousexvel*=.6; mouseyvel*=.6;
						}
					}
				}
				MouseRot.x+=mousexvel; MouseRot.y+=mouseyvel;
			}
			MouseRot.z=0.0;
			Vector3_t rt;
			rt.x=MouseRot.y;
			rt.y=MouseRot.x;
			rt.z=MouseRot.z;
			if(Render_Local_Player)
				Players[LocalPlayerID].dir=rt.RotationAsDirection;
			if(MouseRot.y<-89.0)
				MouseRot.y=-89.0;
			if(MouseRot.y>89.0)
				MouseRot.y=89.0;
			CameraPos = Players[LocalPlayerID].CameraPos();
			CameraRot=MouseRot;
			MouseMovedX = 0;
			MouseMovedY = 0;
			Renderer_SetBlur(Current_Blur_Amount);
		}
		else{
			MouseRot.x+=MouseMovedX*.7*14.0*Config_Read!float("mouse_accuracy")*X_FOV/90.0; MouseRot.y+=MouseMovedY*.5*14.0*Config_Read!float("mouse_accuracy")*Y_FOV/90.0;
			TerrainOverview.x+=cos(TerrainOverviewRotation*PI/180.0)*.3*WorldSpeed*100.0/3.0;
			TerrainOverview.z+=sin(TerrainOverviewRotation*PI/180.0)*.3*WorldSpeed*100.0/3.0;
			TerrainOverview.y=TerrainOverview.y*.99+(Voxel_GetHighestY(TerrainOverview.x, 0.0, TerrainOverview.z)-48.0)*.01;
			TerrainOverviewRotation=TerrainOverviewRotation*.8+(TerrainOverviewRotation+uniform01()*.1+.9)*.2;
			CameraPos=TerrainOverview;
			Vector3_t crot=MouseRot*Vector3_t(.05, .15, 0.0)+Vector3_t(0.0, 45.0, 0.0);
			CameraRot=crot;
			MouseMovedX = 0;
			MouseMovedY = 0;
			Renderer_SetBlur(0.0);
		}
		if(Current_Shake_Amount>0.0){
			Vector3_t shake_cam=CameraPos;
			shake_cam.x+=(uniform01()*2.0-1.0)*Current_Shake_Amount;
			shake_cam.y+=(uniform01()*2.0-1.0)*Current_Shake_Amount;
			shake_cam.z+=(uniform01()*2.0-1.0)*Current_Shake_Amount;
			Renderer_SetCamera(CameraRot.x, CameraRot.y, CameraRot.z, X_FOV, Y_FOV, shake_cam.x, shake_cam.y, shake_cam.z);
		}
		else{
			Renderer_SetCamera(CameraRot.x, CameraRot.y, CameraRot.z, X_FOV, Y_FOV, CameraPos.x, CameraPos.y, CameraPos.z);
		}
		if(Render_Local_Player)
			Update_Rotation_Data();
		Renderer_StartRendering(true);
		Render_World(false);
	} else {
		Renderer_StartRendering(false);
	}
	Renderer_Start2D();
	{
		if(LoadedCompleteMap){
			Do_Sprite_Visibility_Checks=true;
			{
				if(Render_Local_Player){
					if(LocalPlayerScoping()){
						if(ProtocolBuiltin_ScopePicture){
							auto res=Get_Player_Scope(LocalPlayerID);
							auto scope_pic=Renderer_DrawRoundZoomedIn(&res.pos, &res.rot, ProtocolBuiltin_ScopePicture, 1.8, 1.8);
							MenuElement_t *e=ProtocolBuiltin_ScopePicture;
							uint[2] size=[scope_pic.scope_texture_width, scope_pic.scope_texture_height];
							Renderer_Blit2D(scope_pic.scope_texture, &size, &scope_pic.dstrect, 255, null, &scope_pic.srcrect);
							size=[Mod_Picture_Sizes[e.picture_index][0], Mod_Picture_Sizes[e.picture_index][0]];
							Renderer_Blit2D(Mod_Pictures[e.picture_index], &size, &scope_pic.dstrect);
						}
					}
				}
			}
		}
		else if(MapLoadingSrfc && MapLoadingTex){
			Renderer_UploadToTexture(MapLoadingSrfc, MapLoadingTex);
			uint[2] size=[MapLoadingSrfc.w, MapLoadingSrfc.h];
			Renderer_Blit2D(MapLoadingTex, &size, null);
		}
	}
	foreach(ref elements; Z_MenuElements[StartZPos..MiniMapZPos]) {
		foreach(e_index; elements) {
			MenuElement_Draw(&MenuElements[e_index]);
		}
	}
	Render_HUD();
	immutable ubyte minimap_alpha=210;
	if(Render_MiniMap && Joined_Game()){
		if(MiniMap_SurfaceChanged)
			Renderer_UploadToTexture(minimap_srfc, minimap_texture);
		SDL_Rect minimap_rect;
		minimap_rect.x=0; minimap_rect.y=0; minimap_rect.w=ScreenXSize; minimap_rect.h=ScreenYSize;
		uint[2] minimap_size=[minimap_srfc.w, minimap_srfc.h];
		ubyte[3] colormod;
		{
			ubyte sun_brightness=to!ubyte((Sun_Vector.length*.9f+.1f)*255.0f);
			colormod=[sun_brightness, sun_brightness, sun_brightness];
		}
		Renderer_Blit2D(minimap_texture, &minimap_size, &minimap_rect, 255, &colormod);
		if(Players[LocalPlayerID].Spawned){
			Team_t *team=&Teams[Players[LocalPlayerID].team];
			ubyte[4] col=[team.color[2], team.color[1], team.color[0], 255];
			ubyte[4] plrcol=0xff^col[]; plrcol[3]=255;
			foreach(ref plr; Players){
				if(!plr.Spawned || !plr.InGame || plr.team!=Players[LocalPlayerID].team)
					continue;
				int xpos=cast(int)(plr.pos.x*cast(float)(minimap_rect.w)/cast(float)(MapXSize))+minimap_rect.x;
				int zpos=cast(int)(plr.pos.z*cast(float)(minimap_rect.h)/cast(float)(MapZSize))+minimap_rect.y;
				SDL_Rect prct;
				prct.w=4; prct.h=4;
				prct.x=xpos-prct.w/2; prct.y=zpos-prct.h/2;
				if(plr.player_id!=LocalPlayerID){
					Renderer_FillRect(&prct, &col);
				}
				else{
					prct.w+=2; prct.h+=2;
					prct.x--; prct.y--;
					Renderer_FillRect(&prct, &col);
					prct.w-=2; prct.h-=2;
					prct.x++; prct.y++;
					Renderer_FillRect(&prct, &plrcol);
				}
			}
		}
		foreach(ref obj; Objects){
			if(!obj.visible || obj.minimap_img==255)
				continue;
			SDL_Rect orct;
			ubyte r, g, b;
			bool restore_color_mod=false;
			colormod=[255, 255, 255];
			if(obj.color){
				if(obj.color&0x00ffffff){
					if(!(obj.color&0xff000000)){
						colormod=[(obj.color>>16)&255, (obj.color>>8)&255, (obj.color>>0)&255];
					}
					else{
						int alpha=obj.color>>24;
						int[3] cmarr=[(obj.color>>16)&255, (obj.color>>8)&255, (obj.color>>0)&255];
						cmarr=[255, 255, 255]-cmarr[];
						cmarr=[255, 255, 255]-((cmarr[]*[alpha, alpha, alpha])/[256, 256, 256]);
						colormod=[cast(ubyte)cmarr[0], cast(ubyte)cmarr[1], cast(ubyte)cmarr[2]];
					}
				}
				else{
					colormod=[128, 128, 128];
				}
			}
			orct.w=Mod_Picture_Sizes[obj.minimap_img][0]*minimap_rect.w/MapXSize;
			orct.h=Mod_Picture_Sizes[obj.minimap_img][1]*minimap_rect.h/MapZSize;
			int xpos=cast(int)(obj.pos.x*cast(float)(minimap_rect.w)/cast(float)(MapXSize))+minimap_rect.x;
			int zpos=cast(int)(obj.pos.z*cast(float)(minimap_rect.h)/cast(float)(MapZSize))+minimap_rect.y;
			orct.x=xpos-orct.w/2; orct.y=zpos-orct.h/2;
			Renderer_Blit2D(Mod_Pictures[obj.minimap_img], &Mod_Picture_Sizes[obj.minimap_img], &orct, 255, &colormod);
		}
		Script_OnMiniMapRender();
	}
	foreach(ref elements; Z_MenuElements[MiniMapZPos..$]) {
		foreach(e_index; elements) {
			MenuElement_Draw(&MenuElements[e_index]);
		}
	}
	if(List_Players){
		Renderer_FillRect(null, 0xf0008080);
		//Some random optimization cause I don't want to have to allocate the same stuff on each frame
		uint[] list_player_amount;
		list_player_amount.length=Teams.length;
		if(Player_List_Table.length!=Teams.length)
			Player_List_Table.length=Teams.length;
		foreach(ref arr; Player_List_Table){
			if(arr.length!=Players.length)
				arr.length=Players.length;
		}
		foreach(ref p; Players){
			if(p.team==255 || !p.InGame)
				continue;
			list_player_amount[p.team]++;
			Player_List_Table[p.team][list_player_amount[p.team]-1]=p.player_id;
		}
		immutable uint teamlist_w=cast(uint)(ScreenXSize/Teams.length); //cast for 64 bit systems
		//.6 looks ok-ish
		immutable float letter_xsize=.675;
		float team_xpos=0.0;
		for(uint t=0; t<Teams.length; t++){
			for(uint plist_index=0; plist_index<list_player_amount[t]; plist_index++){
				Player_t *plr=&Players[Player_List_Table[t][plist_index]];
				string plrentry;
				if(Teams[t].playing)
					plrentry=format("%-32s [#%3d] `%d` *%d*", plr.name, plr.player_id, plr.score, plr.gmscore);
				else
					plrentry=format("%-32s [#%3d]", plr.name, plr.player_id);
				Render_Text_Line(cast(uint)team_xpos, (plist_index*2+1)*FontHeight/16,
				Color_ActionPerComponent!("min(a<<1, 255)")(Teams[t].icolor), plrentry, font_texture, FontWidth, FontHeight, LetterPadding, letter_xsize, 1.0);
			}
			if(Teams[t].playing)
				team_xpos+=(32+1+2+3+2+9+2+9+1)*letter_xsize*FontWidth/16;
			else
				team_xpos+=(32+2+3+1)*letter_xsize*FontWidth/16;
		}
	}
	if(!Render_Local_Player)
		Renderer_ShowInfo();
	Renderer_Finish2D();
}

bool LocalPlayerScoping(){
	if(LocalPlayerID<Players.length){
		if(Players[LocalPlayerID].items.length){
			if(ItemTypes[Players[LocalPlayerID].items[Players[LocalPlayerID].item].type].is_weapon
			&& !Players[LocalPlayerID].items[Players[LocalPlayerID].item].Reloading && MouseRightClick && BlurAmount<.2){
				return true;
			}
		}
	}
	return false;
}

void Finish_Render(){
	Renderer_FinishRendering();
}

void UnInit_Gfx(){
	if(font_texture)
		Renderer_DestroyTexture(font_texture);
	if(borderless_font_texture)
		Renderer_DestroyTexture(borderless_font_texture);
	Renderer_UnInit();
	IMG_Quit();
	SDL_Quit();
}

void Render_Player(uint player_id){
	if(!Players[player_id].Spawned)
		return;
	Sprite_t[] sprites=Get_Player_Sprites(player_id);
	sprites~=Get_Player_Attached_Sprites(player_id);
	foreach(ref spr; sprites){
		spr.replace_black=Teams[Players[player_id].team].icolor;
		Renderer_DrawSprite(&spr);
	}
}

Sprite_t[] Get_Player_Sprites(uint player_id){
	Player_t *plr=&Players[player_id];
	Vector3_t rot=Players[player_id].dir.DirectionAsRotation;
	Vector3_t pos=Players[player_id].CameraPos;
	if(player_id==LocalPlayerID)
		pos=CameraPos;
	Sprite_t[] sprarr;
	Sprite_t spr;
	Sprite_t[] attached_sprites=Get_Player_Attached_Sprites(player_id);
	Vector3_t hands_pos;
	if(attached_sprites.length)
		hands_pos=Vector3_t(attached_sprites[0].xpos, attached_sprites[0].ypos, attached_sprites[0].zpos);
	foreach(immutable model; plr.models){
		if(player_id==LocalPlayerID && !model.FirstPersonModel)
			continue;
		Vector3_t mrot=rot;
		spr.rst=model.rotation.z; spr.rti=mrot.y+model.rotation.y; spr.rhe=model.rotation.x;
		if(model.Rotate){
			spr.rst+=mrot.z; spr.rhe+=mrot.x;
		}
		if(model.WalkRotate){
			spr.rhe+=sin(plr.Walk_Forwards_Timer)*model.WalkRotate;
			spr.rst+=sin(plr.Walk_Sidewards_Timer)*model.WalkRotate;
		}
		Model_t *modelfile=Mod_Models[model.model_id];
		spr.xdensity=model.size.x/tofloat(modelfile.xsize);
		spr.ydensity=model.size.y/tofloat(modelfile.ysize); spr.zdensity=model.size.z/tofloat(modelfile.zsize);
		spr.model=modelfile;
		Vector3_t mpos=pos;
		Vector3_t offsetrot=mrot;
		offsetrot.x=0.0; offsetrot.z=0.0; offsetrot.y=-rot.y;
		Vector3_t offset=Vector3_t(model.offset).rotate_raw(offsetrot);
		mpos-=offset;
		if(model.Rotate && model.FirstPersonModel){
			Vector3_t hand_offset=(hands_pos-mpos).abs();
			if(player_id==LocalPlayerID) 					//QUICK HACK TO GET THE HANDS OUT OF THE SCOPE (MAKE THIS CALCULATE STUFF PROPERLY)
				mpos-=hand_offset*.5;
			Vector3_t hand_rot=hand_offset.DirectionAsRotation;
			spr.rst=hand_rot.z; spr.rti=hand_rot.y; spr.rhe=hand_rot.x;
		}
		spr.xpos=mpos.x; spr.ypos=mpos.y; spr.zpos=mpos.z;
		spr.color_mod=0;
		sprarr~=spr;
	}
	return sprarr;
}

auto Get_Player_Scope(uint player_id){
	struct Result_t{
		Vector3_t pos, rot;
	}
	Result_t result;
	Sprite_t spr=Get_Player_Attached_Sprites(player_id)[0];
	result.rot=Vector3_t(spr.rhe-3.0, spr.rti, spr.rst);
	float xoffset=spr.model.xsize/2.0-.5;
	Item_t *item=Players[player_id].Equipped_Item();
	auto current_tick=PreciseClock_ToMSecs(PreciseClock());
	result.pos=Validate_Coord(Get_Absolute_Sprite_Coord(&spr, Vector3_t(xoffset, -.3, spr.model.zpivot)));
	if(Voxel_IsSolid(result.pos.x, result.pos.y, result.pos.z)){
		if(result.pos.y>=63.0)
			result.pos.y=62.99;
	}
	return result;
}

//Note: Sprite number zero has to be the weapon when scoping
Sprite_t[] Get_Player_Attached_Sprites(uint player_id){
	if(!Players[player_id].items.length || !Players[player_id].Spawned)
		return [];
	if(ItemTypes[Players[player_id].items[Players[player_id].item].type].model_id==255)
		return[];
	Vector3_t rot=Players[player_id].dir.DirectionAsRotation;
	Vector3_t pos=Players[player_id].CameraPos;
	Sprite_t[] sprarr;
	Sprite_t spr;
	Vector3_t item_offset;
	Player_t *plr=&Players[player_id];
	if(player_id==LocalPlayerID){
		pos=CameraPos;
	}
	auto current_tick=PreciseClock_ToMSecs(PreciseClock());
	Item_t *item=&plr.items[plr.item];
	bool item_is_weapon=ItemTypes[item.type].is_weapon;
	Vector3_t target_item_offset;
	if(player_id==LocalPlayerID){
		if(LocalPlayerScoping()){
			target_item_offset=Vector3_t(.5, 0.0, .1);
		}
		else
		if(plr.left_click && !item_is_weapon){
			target_item_offset=Vector3_t(1.2, 0.0, .9);
		}
		else{
			target_item_offset=Vector3_t(.7, -.4, .45);
		}
	}
	else{
		target_item_offset=Vector3_t(.7, -.05, .45);
	}
	if(1){
		immutable float animation_length=(1.0-1.0/(ItemTypes[item.type].power+1.0))*.7+.1;
		if(FrameCounter!=plr.item_animation_counter && plr.current_item_offset!=target_item_offset){
			plr.current_item_offset=plr.current_item_offset*animation_length+Vector3_t(target_item_offset)*(1.0-animation_length);
			plr.item_animation_counter=FrameCounter;
		}
		item_offset=plr.current_item_offset;
	}
	if(player_id==LocalPlayerID && item_is_weapon){
		if(current_tick-item.use_timer<ItemTypes[item.type].use_delay){
			item_offset.x-=(1.0-tofloat(current_tick-item.use_timer)/tofloat(ItemTypes[item.type].use_delay))*pow(abs(item.last_recoil), .7)*.1;
		}
	}
	//I have no idea what I'm rotating around which axis or idk, actually I am only supposed to need one single rotation
	//But this works (makes the item appear in front of the player with an offset of item_offset, considering his rotation)
	spr.rst=rot.z*0.0; spr.rhe=rot.x; spr.rti=rot.y;
	Vector3_t itempos=pos+item_offset.rotate_raw(Vector3_t(0.0, 90.0-rot.x, 90.0)).rotate_raw(Vector3_t(0.0, 90.0-rot.y+180.0, 0.0));
	spr.xpos=itempos.x; spr.ypos=itempos.y; spr.zpos=itempos.z;
	spr.xdensity=.04; spr.ydensity=.04; spr.zdensity=.04;
	//BIG WIP
	if(item_is_weapon){
		if(!item.Reloading){
			if(current_tick-item.use_timer<ItemTypes[item.type].use_delay)
				spr.rhe-=(1.0-tofloat(current_tick-item.use_timer)/tofloat(ItemTypes[item.type].use_delay))*pow(abs(item.last_recoil), .7)*sgn(item.last_recoil)*.025;
		}
	}
	else
	if(!item.Reloading){
		if(current_tick-item.use_timer<ItemTypes[item.type].use_delay){
			spr.rhe-=(1.0-tofloat(current_tick-item.use_timer)/tofloat(ItemTypes[item.type].use_delay))*pow(abs(item.last_recoil), .7)*sgn(item.last_recoil)*.025;
		}
	}
	if(ItemTypes[item.type].color_mod==true)
		spr.color_mod=(plr.color&0x00ffffff) | 0xff000000;
	else
		spr.color_mod=0;
	spr.model=Mod_Models[ItemTypes[plr.items[plr.item].type].model_id];
	sprarr~=spr;
	return sprarr;
}

bool SpriteHitScan(in Sprite_t spr, Vector3_t pos, Vector3_t dir, out Vector3_t voxpos, out ModelVoxel_t *outvoxptr, float vox_size=1.0){
	uint x, z;
	const(ModelVoxel_t)* sblk, blk, eblk, voxptr=null;
	float rot_sx, rot_cx, rot_sy, rot_cy, rot_sz, rot_cz;
	rot_sx=sin((spr.rhe)*PI/180.0); rot_cx=cos((spr.rhe)*PI/180.0);
	rot_sy=sin(-(spr.rti+90.0)*PI/180.0); rot_cy=cos(-(spr.rti+90.0)*PI/180.0);
	rot_sz=sin(spr.rst*PI/180.0); rot_cz=cos(-spr.rst*PI/180.0);
	if(!Sprite_BoundHitCheck(spr, pos, dir))
		return false;
	voxpos=Vector3_t(spr.xpos, spr.ypos, spr.zpos);
	float voxxsize=fabs(spr.xdensity)*vox_size, voxysize=fabs(spr.ydensity)*vox_size, voxzsize=fabs(spr.zdensity)*vox_size;
	float minvxdist=10e99;
	for(x=0; x<spr.model.xsize; ++x){
		for(z=0; z<spr.model.zsize; ++z){
			uint index=spr.model.offsets[x+z*spr.model.xsize];
			if(index>=spr.model.voxels.length)
				continue;
			sblk=&spr.model.voxels[index];
			eblk=&sblk[cast(uint)spr.model.column_lengths[x+z*spr.model.xsize]];
			for(blk=sblk; blk<eblk; ++blk){
				float fnx=(x-spr.model.xpivot+.5)*spr.xdensity;
				float fny=(blk.ypos-spr.model.ypivot+.5)*spr.ydensity;
				float fnz=(z-spr.model.zpivot-.5)*spr.zdensity;
				float rot_y=fny, rot_z=fnz, rot_x;
				fny=rot_y*rot_cx - rot_z*rot_sx; fnz=rot_y*rot_sx + rot_z*rot_cx;
				rot_x=fnx; rot_z=fnz;
				fnz=rot_z*rot_cy - rot_x*rot_sy; fnx=rot_z*rot_sy + rot_x*rot_cy;
				rot_x=fnx; rot_y=fny;
				fnx=rot_x*rot_cz - rot_y*rot_sz; fny=rot_x*rot_sz + rot_y*rot_cz;
				fnx+=spr.xpos; fny+=spr.ypos; fnz+=spr.zpos;
				Vector3_t vpos=Vector3_t(fnx, fny, fnz);
				float dist=(vpos-pos).length;
				Vector3_t lookpos=pos+dir*dist;
				Vector3_t cdist=(lookpos-vpos).vecabs;
				if(cdist.x<voxxsize && cdist.y<voxxsize && cdist.z<voxzsize){
					if(dist<minvxdist){
						minvxdist=dist;
						voxpos=vpos;
						voxptr=blk;
					}
				}
			}
		}
	}
	outvoxptr=cast(ModelVoxel_t*)voxptr;
	if(voxptr)
		return true;
	return false;
}

struct Bullet_t{
	Vector3_t startpos, vel;
	Vector3_t sprrot;
	float dist, maxdist;
	Sprite_t *item_type_sprite;
}
Bullet_t[] Bullets;

void Bullet_Shoot(Vector3_t pos, Vector3_t vel, float maxdist, Sprite_t *spr){
	Bullet_t bullet;
	bullet.startpos=pos; bullet.vel=vel; bullet.sprrot=(vel.abs()).DirectionAsRotation; bullet.dist=0.0; bullet.maxdist=maxdist;
	bullet.item_type_sprite=spr;
	Bullets~=bullet;
}

struct Particle_t{
	Vector3_t pos, vel;
	uint col;
	uint timer;
}
Particle_t[] Particles;

immutable float BlockBreakParticleSize=.3;
Particle_t[] BlockBreakParticles;

struct SmokeParticle_t{
	Vector3_t pos, vel;
	float size;
	float alpha;
	float remove_size;
	uint col;
	void Init(Vector3_t ipos, Vector3_t ivel, uint icol, float isize){
		pos=ipos; vel=ivel; size=isize; col=icol; alpha=uniform01()*.1f+.9f; remove_size=size*(uniform01()*1.0f+1.5f);
	}
}
SmokeParticle_t[] SmokeParticles;

struct ExplosionSprite_t{
	Sprite_t spr;
	float size, maxsize;
}
ExplosionSprite_t[] ExplosionEffectSprites;

void Create_Particles(Vector3_t pos, Vector3_t vel, float radius, float spread, uint amount, uint[] col, float timer_ratio=1.0){
	amount=to!uint(amount*Config_Read!float("particles"));
	uint old_size=cast(uint)Particles.length;
	bool use_sent_cols=radius==0;
	Particles.length+=amount;
	uint[] colors;
	pos.y+=.1;
	if(radius){
		for(int x=toint(pos.x-radius); x<toint(pos.x+radius); x++){
			for(int y=toint(pos.y-radius); y<toint(pos.y+radius); y++){
				for(int z=toint(pos.z-radius); z<toint(pos.z+radius); z++){
					if(!Valid_Coord(x, y, z))
						continue;
					if(Voxel_IsSolid(x, y, z)){
						colors~=Voxel_GetColor(x, y, z);
					}
				}
			}
		}
	}
	if(Voxel_IsWater(pos.x, pos.y, pos.z)){
		use_sent_cols=true;
		pos.y-=1.0;
	}
	pos.y-=.1;
	if(!colors.length){
		if(col.length)
			use_sent_cols=true;
		else
			colors~=0x00a0a0a0;
	}
	col[]|=0xff000000;
	colors[]|=0xff000000;
	for(uint i=old_size; i<old_size+amount; i++){
		Vector3_t vspr=Vector3_t(spread*(uniform01()*2.0-1.0), spread*(uniform01()*2.0-1.0), spread*(uniform01()*2.0-1.0));
		Particles[i].pos=pos;
		Particles[i].vel=vel+vspr;
		if((uniform(0, 2) || use_sent_cols) && col.length)
			Particles[i].col=col[uniform(0, col.length)];
		else
			Particles[i].col=colors[uniform(0, colors.length)];
		Particles[i].timer=cast(uint)(uniform(300, 400)*timer_ratio);
	}
}

void Create_Smoke(Vector3_t pos, uint amount, uint col, float size, float speedspread=1.0, float alpha=1.0, Vector3_t cvel=Vector3_t(0)){
	uint old_size=cast(uint)SmokeParticles.length;
	amount=to!uint((amount+1)*SmokeAmount);
	SmokeParticles.length+=amount;
	float sizeratio=pow(size, .2);
	for(uint i=old_size; i<old_size+amount; i++){
		Vector3_t spos=pos+RandomVector()*.12*size;
		Vector3_t vel=(RandomVector()*size*.01+(spos-pos)*(.5+sizeratio*.4))*speedspread+cvel;
		SmokeParticles[i].Init(spos, vel,
		Calculate_Alpha(col, Calculate_Alpha(0, 0xffffffff, uniform!ubyte()), 255-to!ubyte(uniform01()*255.0/(1.0+size)*.8)),
		size*80.0*uniform(50, 150)*.01);
		SmokeParticles[i].alpha*=alpha;
	}
}

//Leaving this as it is here (looks nice, even if far away from being finished), I have other things to do
struct Debris_t{
	PhysicalObject_t obj;
	float timer;
	uint sizefactor;
	uint split_counter;
	this(Vector3_t pos, Model_t *model, uint isizefactor=1){
		sizefactor=isizefactor;
		Vector3_t[] vertices;
		obj.spr.size=Vector3_t(model.size)/sizefactor;
		for(uint z=0; z<model.zsize; z++){
			for(uint x=0; x<model.xsize; x++){
				foreach(blk; model.voxels[model.offsets[x+z*model.xsize]..model.offsets[x+z*model.xsize]+model.column_lengths[x+z*model.xsize]]){
					for(int ex=0; ex<2; ex++){
						for(int ey=0; ey<2; ey++){
							for(int ez=0; ez<2; ez++){
								vertices~=Vector3_t(x, blk.ypos, z)+Vector3_t(ex*2-1, ey*2-1, ez*2-1)*(obj.spr.size/Vector3_t(model.size));
							}
						}
					}
				}
			}
		}
		obj=PhysicalObject_t(vertices);
		obj.spr=SpriteRenderData_t(model);
		obj.pos=pos;
		obj.spr.check_visibility=1;
		obj.vel=RandomVector();
		obj.bouncefactor=Vector3_t(.8);
		timer=sqrt(cast(float)model.voxels.length)*100.0;
		split_counter=0;
	}
	this(Vector3_t pos, Vector_t!(4, uint)[] blocks, uint isizefactor=1){	
		ModelVoxel_t[][] voxels;
		Vector_t!(3, uint) minpos=uint.max, maxpos=uint.min;
		foreach(blk; blocks){
			minpos.x=min(minpos.x, blk.x); maxpos.x=max(maxpos.x, blk.x);
			minpos.y=min(minpos.y, blk.y); maxpos.y=max(maxpos.y, blk.y);
			minpos.z=min(minpos.z, blk.z); maxpos.z=max(maxpos.z, blk.z);
		}
		Vector_t!(3, uint) size=[maxpos.x-minpos.x+1, maxpos.y-minpos.y+1, maxpos.z-minpos.z+1];
		voxels.length=size.x*size.z;
		foreach(blk; blocks)
			voxels[blk.x-minpos.x+(blk.z-minpos.z)*size.x]~=ModelVoxel_t(blk.w, cast(ushort)(blk.y-minpos.y), 15, 0);
		this(pos, (*Model_FromVoxelArray(voxels, size.x, size.z))<<(1+cast(uint)log2(isizefactor)), isizefactor);
	}
	void Update(float dt){
		timer-=dt;
		if(obj.Collision[2] || ((obj.vel.length<.2 || obj.Collision[0] || obj.Collision[1]) && !(uniform!uint()%20)))
			timer=0.0;
		if(timer<=0.0){
			timer=0.0;
		}
		obj.Update(dt);
		obj.vel.y+=Gravity*dt;
		obj.vel/=1.0+dt*.2;
		obj.Render();
	}
}

Debris_t[] Debris_Parts;

Model_t *Debris_BaseModel;

void Create_Explosion(Vector3_t pos, Vector3_t vel, float radius, float spread, uint amount, uint col, uint timer=0){
	static if(Enable_Object_Model_Modification){
		uint explosion_r=(col&255), explosion_g=(col>>8)&255, explosion_b=(col>>16)&255;
		foreach(uint obj_id, obj; Objects){
			if(!obj.modify_model)
				continue;
			//Crappy early out case check; need to fix this and consider pivots
			Vector3_t size=obj.spr.size;
			Vector3_t dist=(obj.pos-pos).vecabs();
			if(dist.x>radius+size.x*2.0 || dist.y>radius+size.y*2.0 || dist.z>radius+size.z*2.0)
				continue;
			Sprite_t spr=Objects[obj_id].toSprite();
			{
				float rot_sx=sin((spr.rhe)*PI/180.0), rot_cx=cos((spr.rhe)*PI/180.0);
				float rot_sy=sin(-(spr.rti+90.0)*PI/180.0), rot_cy=cos(-(spr.rti+90.0)*PI/180.0);
				float rot_sz=sin(spr.rst*PI/180.0), rot_cz=cos(-spr.rst*PI/180.0);
				for(uint blkx=0; blkx<spr.model.xsize; ++blkx){
					for(uint blkz=0; blkz<spr.model.zsize; ++blkz){
						uint index=spr.model.offsets[blkx+blkz*spr.model.xsize];
						if(index>=spr.model.voxels.length)
							continue;
						ModelVoxel_t *sblk=&spr.model.voxels[index];
						ModelVoxel_t *eblk=&sblk[cast(uint)spr.model.column_lengths[blkx+blkz*spr.model.xsize]];
						for(ModelVoxel_t *blk=sblk; blk<eblk; ++blk){
							if(!blk.visiblefaces)
								continue;
							float fnx=(blkx-spr.model.xpivot+.5)*spr.xdensity;
							float fny=(blk.ypos-spr.model.ypivot+.5)*spr.ydensity;
							float fnz=(blkz-spr.model.zpivot-.5)*spr.zdensity;
							float rot_y=fny, rot_z=fnz, rot_x=fnx;
							fny=rot_y*rot_cx - rot_z*rot_sx; fnz=rot_y*rot_sx + rot_z*rot_cx;
							rot_x=fnx; rot_z=fnz;
							fnz=rot_z*rot_cy - rot_x*rot_sy; fnx=rot_z*rot_sy + rot_x*rot_cy;
							rot_x=fnx; rot_y=fny;
							fnx=rot_x*rot_cz - rot_y*rot_sz; fny=rot_x*rot_sz + rot_y*rot_cz;
							fnx+=spr.xpos; fny+=spr.ypos; fnz+=spr.zpos;
							Vector3_t vxpos=Vector3_t(fnx, fny, fnz);
							float vxdist=(vxpos-pos).length*(.8+uniform01()*.2);
							if(vxdist>radius)
								continue;
							uint alpha=touint((vxdist/radius)*255.0), inv_alpha=255-alpha;
							uint r=(blk.color)&255, g=(blk.color>>8)&255, b=(blk.color>>16)&255;
							/*r=(explosion_r*inv_alpha+r*alpha)>>8;
							g=(explosion_g*inv_alpha+g*alpha)>>8;
							b=(explosion_b*inv_alpha+b*alpha)>>8;*/
							r=(r*alpha)>>8; g=(g*alpha)>>8; b=(b*alpha)>>8;
							blk.color=(r) | (g<<8) | (b<<16);
						}
					}
				}
			}
		}
	}
	if(Config_Read!bool("effects")){
		float powrad=radius*radius;
		int miny=cast(int)max(0, -radius+pos.y), maxy=cast(int)min(MapYSize, radius+pos.y);
		uint __rand_factor=(*(cast(uint*)&spread))^(*(cast(uint*)&pos.x))^(*(cast(uint*)&pos.y))^(*(cast(uint*)&pos.z));
		if(!Debris_BaseModel && 0){
			Debris_BaseModel=new Model_t;
			Debris_BaseModel.xsize=Debris_BaseModel.ysize=Debris_BaseModel.zsize=10;
			Debris_BaseModel.xpivot=Debris_BaseModel.ypivot=Debris_BaseModel.zpivot=Debris_BaseModel.xsize/2;
			Debris_BaseModel.voxels.length=Debris_BaseModel.xsize*Debris_BaseModel.ysize*Debris_BaseModel.zsize;
			Debris_BaseModel.offsets.length=Debris_BaseModel.column_lengths.length=Debris_BaseModel.xsize*Debris_BaseModel.zsize;
			for(uint x=1; x<Debris_BaseModel.xsize-1; x++){
				for(uint z=1; z<Debris_BaseModel.zsize-1; z++){
					Debris_BaseModel.offsets[x+z*Debris_BaseModel.xsize]=(x+z*Debris_BaseModel.xsize)*Debris_BaseModel.ysize;
					Debris_BaseModel.column_lengths[x+z*Debris_BaseModel.xsize]=2;
					Debris_BaseModel.voxels[Debris_BaseModel.offsets[x+z*Debris_BaseModel.xsize]]=ModelVoxel_t(0x00040404, 0, 16, 0);
					Debris_BaseModel.voxels[Debris_BaseModel.offsets[x+z*Debris_BaseModel.xsize]+1]=ModelVoxel_t(0x00040404,
					cast(ushort)(Debris_BaseModel.ysize-1), 16, 0);
				}
			}
			for(uint x=0; x<Debris_BaseModel.xsize; x++){
				uint z=0;
				Debris_BaseModel.offsets[x+z*Debris_BaseModel.xsize]=(x+z*Debris_BaseModel.xsize)*Debris_BaseModel.ysize;
				Debris_BaseModel.column_lengths[x+z*Debris_BaseModel.xsize]=cast(ushort)Debris_BaseModel.ysize;
				for(uint y=0; y<Debris_BaseModel.ysize; y++){
					Debris_BaseModel.voxels[Debris_BaseModel.offsets[x+z*Debris_BaseModel.xsize]+y]=ModelVoxel_t(0x00040404, cast(ushort)y, 16, 0);
				}
				z=Debris_BaseModel.zsize-1;
				Debris_BaseModel.offsets[x+z*Debris_BaseModel.xsize]=(x+z*Debris_BaseModel.xsize)*Debris_BaseModel.ysize;
				Debris_BaseModel.column_lengths[x+z*Debris_BaseModel.xsize]=cast(ushort)Debris_BaseModel.ysize;
				for(uint y=0; y<Debris_BaseModel.ysize; y++){
					Debris_BaseModel.voxels[Debris_BaseModel.offsets[x+z*Debris_BaseModel.xsize]+y]=ModelVoxel_t(0x00040404, cast(ushort)y, 16, 0);
				}
			}
			for(uint z=0; z<Debris_BaseModel.zsize; z++){
				uint x=0;
				Debris_BaseModel.offsets[x+z*Debris_BaseModel.xsize]=(x+z*Debris_BaseModel.xsize)*Debris_BaseModel.ysize;
				Debris_BaseModel.column_lengths[x+z*Debris_BaseModel.xsize]=cast(ushort)Debris_BaseModel.ysize;
				for(uint y=0; y<Debris_BaseModel.ysize; y++){
					Debris_BaseModel.voxels[Debris_BaseModel.offsets[x+z*Debris_BaseModel.xsize]+y]=ModelVoxel_t(0x00040404, cast(ushort)y, 16, 0);
				}
				x=Debris_BaseModel.xsize-1;
				Debris_BaseModel.offsets[x+z*Debris_BaseModel.xsize]=(x+z*Debris_BaseModel.xsize)*Debris_BaseModel.ysize;
				Debris_BaseModel.column_lengths[x+z*Debris_BaseModel.xsize]=cast(ushort)Debris_BaseModel.ysize;
				for(uint y=0; y<Debris_BaseModel.ysize; y++){
					Debris_BaseModel.voxels[Debris_BaseModel.offsets[x+z*Debris_BaseModel.xsize]+y]=ModelVoxel_t(0x00040404, cast(ushort)y, 16, 0);
				}
			}
		}
		uint randnum=(__rand_factor<<1)^((*(cast(uint*)&vel.x))<<1);
		Vector_t!(4, uint)[] blocks;
		for(int x=-cast(int)radius; x<radius; x++){
			for(int z=-cast(int)radius; z<radius; z++){
				if(x*x+z*z>powrad)
					continue;
				int mx=cast(int)(x+pos.x), mz=cast(int)(z+pos.z);
				if(mx<0 || mz<0 || mx>MapXSize || mz>MapZSize)
					continue;
				int sy=Voxel_GetHighestY(mx, miny, mz);
				for(int y=sy; y<maxy; y++){
					if(Voxel_IsSolid(mx, y, mz) && ((__rand_factor^(randnum<<2)^((*(cast(uint*)&vel.y))))%30) && 0){
						Debris_t b;
						float msize=.8;
						b.obj=PhysicalObject_t([Vector3_t(-msize*.5, -msize*.5, -msize*.5), Vector3_t(msize*.5, -msize*.5, -msize*.5),
						Vector3_t(-msize*.5, msize*.5, -msize*.5), Vector3_t(msize*.5, msize*.5, -msize*.5),
						Vector3_t(-msize*.5, -msize*.5, msize*.5), Vector3_t(msize*.5, -msize*.5, msize*.5),
						Vector3_t(-msize*.5, msize*.5, msize*.5), Vector3_t(msize*.5, msize*.5, msize*.5)]);
						b.obj.spr=SpriteRenderData_t(Debris_BaseModel);
						b.obj.rot=RandomVector()*360.0*0.0;
						b.obj.pos=Vector3_t(mx, y, mz)+.5;
						b.obj.spr.size=Vector3_t(msize);
						b.obj.spr.replace_black=Voxel_GetColor(mx, y, mz);
						b.obj.spr.check_visibility=1;
						b.obj.vel=(b.obj.pos-pos).abs()*(RandomVector()*.5+.75)*(1.0+(((((__rand_factor<<2)^(x<<1)^(y<<3)^z)))%1000)/1000.0*2.0)*5.0;
						b.obj.bouncefactor=Vector3_t(1.0);
						//Debris_Parts~=b;
						randnum^=(*(cast(uint*)&vel.z))<<3;
					}
					if(Voxel_IsSolid(mx, y, mz)){
						blocks~=Vector_t!(4, uint)(mx, y, mz, Voxel_GetColor(mx, y, mz));
					}
				}
			}
		}
		Debris_t d=Debris_t(pos, blocks);
		d.obj.rot.y=270.0;
		d.timer=.0001;
		d.split_counter=0;
		d.obj.vel=RandomVector();
		Debris_Parts~=d;
	}
	Create_Smoke(Vector3_t(pos.x, pos.y, pos.z), amount/4, 0xff808080, radius);
	Create_Particles(pos, vel, radius, spread, amount*7, [], 1.0/(1.0+amount*.001));
	Create_Particles(pos, vel, 0, spread*3.0, amount*10, [0x00ffff00, 0x00ffa000], .05);
	if(Config_Read!bool("effects"))
		Renderer_AddFlash(pos, radius*1.5, 1.0);
	//WIP (go cham!)
	/*ExplosionSprite_t effect;
	Model_t *model=new Model_t;
	model.xsize=32; model.ysize=32; model.zsize=32;
	model.xpivot=model.xsize/2; model.ypivot=model.ysize/2; model.zpivot=model.zsize/2;
	model.lowermip=null;
	ModelVoxel_t[][] voxels;
	voxels.length=model.xsize*model.zsize;
	Vector3_t hsize=Vector3_t(model.xsize, model.ysize, model.zsize)/2.0;
	for(uint i=0; i<to!uint((uniform01()+.5)*(model.xsize*model.ysize*model.zsize)*.1); i++){
		ModelVoxel_t vox;
		Vector3_t vpos=RandomVector()*hsize;
		vpos=vpos.abs()*uniform01()*uniform01()*hsize+hsize;
		vox.color=0x00ffff00;
		vox.ypos=cast(typeof(vox.ypos))vpos.y;
		vox.normalindex=0;
		vox.visiblefaces=1|2|4|8|16|32;
		voxels[to!uint(vpos.x)+to!uint(vpos.z)*model.xsize]~=vox;
	}
	model.offsets.length=model.xsize*model.zsize; model.column_lengths.length=model.offsets.length;
	for(uint z=0; z<model.zsize; z++){
		for(uint x=0; x<model.xsize; x++){
			model.offsets[x+z*model.xsize]=model.voxels.length;
			model.column_lengths[x+z*model.xsize]=cast(typeof(model.column_lengths[0]))voxels[x+z*model.xsize].length;
			foreach(vox; voxels)
				model.voxels~=vox;
		}
	}
	effect.spr.rhe=0.0; effect.spr.rti=0.0; effect.spr.rst=0.0;
	effect.spr.xpos=pos.x; effect.spr.ypos=pos.y; effect.spr.zpos=pos.z;
	effect.spr.xdensity=1.0/model.xsize; effect.spr.ydensity=1.0/model.ysize; effect.spr.zdensity=1.0/model.zsize;
	effect.spr.color_mod=0; effect.spr.replace_black=0;
	effect.spr.check_visibility=1;
	effect.spr.model=model;
	effect.size=0.0;
	effect.maxsize=radius*8.0;
	ExplosionEffectSprites~=effect;*/
}

struct EnvEffectSlot_t{
	ubyte[4] fog;
	float shake;
	float blur;
	float visibility;
	float brightness;
}
EnvEffectSlot_t[] EnvironmentEffectSlots;

void Set_Sun(Vector3_t newpos, float strength){
	Sun_Position=newpos;
	Sun_Vector=(newpos-Vector3_t(MapXSize, MapYSize, MapZSize)/2.0).abs()*strength;
	try{
		Renderer_SetBrightness(strength);
		Renderer_SetBlockFaceShading(Sun_Vector);
	}catch(Throwable o){
		writeflnlog("ERROR CATCHED %s %s %s (REPORT TO DEVS)", newpos, strength, o);
	}
}

//Be careful: this is evil
Vector3_t Get_Absolute_Sprite_Coord(Sprite_t *spr, Vector3_t coord){
	float rot_sx=sin((spr.rhe)*PI/180.0), rot_cx=cos((spr.rhe)*PI/180.0);
	float rot_sy=sin(-(spr.rti+90.0)*PI/180.0), rot_cy=cos(-(spr.rti+90.0)*PI/180.0);
	float rot_sz=sin(-spr.rst*PI/180.0), rot_cz=cos(-spr.rst*PI/180.0);
	float fnx=(coord.x-spr.model.xpivot+.5)*spr.xdensity;
	float fny=(coord.y-spr.model.ypivot+.5)*spr.ydensity;
	float fnz=(coord.z-spr.model.zpivot-.5)*spr.zdensity;
	float rot_y=fny, rot_z=fnz, rot_x=fnx;
	fny=rot_y*rot_cx - rot_z*rot_sx; fnz=rot_y*rot_sx + rot_z*rot_cx;
	rot_x=fnx; rot_z=fnz;
	fnz=rot_z*rot_cy - rot_x*rot_sy; fnx=rot_z*rot_sy + rot_x*rot_cy;
	rot_x=fnx; rot_y=fny;
	fnx=rot_x*rot_cz - rot_y*rot_sz; fny=rot_x*rot_sz + rot_y*rot_cz;
	fnx+=spr.xpos; fny+=spr.ypos; fnz+=spr.zpos;
	return Vector3_t(fnx, fny, fnz);
}

bool Sprite_Visible(in Sprite_t spr){
	/*if(!Do_Sprite_Visibility_Checks)
		return true;
	float rot_sx=sin((spr.rhe)*PI/180.0), rot_cx=cos((spr.rhe)*PI/180.0);
	float rot_sy=sin(-(spr.rti+90.0)*PI/180.0), rot_cy=cos(-(spr.rti+90.0)*PI/180.0);
	float rot_sz=sin(spr.rst*PI/180.0), rot_cz=cos(-spr.rst*PI/180.0);
	for(uint edgeindex=0; edgeindex<8; edgeindex++){
		float fnx=tofloat(toint(edgeindex%2)*spr.model.xsize);
		float fny=tofloat(toint((edgeindex%4)>1)*spr.model.ysize);
		float fnz=tofloat(toint(edgeindex>3)*spr.model.zsize);
		fnx=(fnx-spr.model.xpivot+.5)*spr.xdensity;
		fny=(fny-spr.model.ypivot+.5)*spr.ydensity;
		fnz=(fnz-spr.model.zpivot-.5)*spr.zdensity;
		float rot_y=fny, rot_z=fnz, rot_x=fnx;
		fny=rot_y*rot_cx - rot_z*rot_sx; fnz=rot_y*rot_sx + rot_z*rot_cx;
		rot_x=fnx; rot_z=fnz;
		fnz=rot_z*rot_cy - rot_x*rot_sy; fnx=rot_z*rot_sy + rot_x*rot_cy;
		rot_x=fnx; rot_y=fny;
		fnx=rot_x*rot_cz - rot_y*rot_sz; fny=rot_x*rot_sz + rot_y*rot_cz;
		fnx+=spr.xpos; fny+=spr.ypos; fnz+=spr.zpos;
		int screenx, screeny;
		float renddist;
		if(!Project2D(fnx, fnz, fny, &renddist, screenx, screeny) && 0)
			continue;
		/*if(renddist<0.0 || renddist>Visibility_Range)
			continue;
		if(screenx<0 || screeny<0 || screenx>=ScreenXSize || ScreenYSize)
			continue;*/
		//Only after I fixed raycasting code
		/*Vector3_t vpos=Vector3_t(fnx, fny, fnz);
		Vector3_t vdist=vpos-CameraPos;
		if(vdist.length>Current_Visibility_Range)
			continue;
		auto result=RayCast(Vector3_t(fnx, fny, fnz), vdist.abs, vdist.length);
		if(!result.collside)
			return true;
		return true;
	}
	return false;*/
	return true;
}

@safe bool Sprite_BoundHitCheck(in Sprite_t spr, Vector3_t pos, Vector3_t dir, immutable real tolerance=3.0){
	real rot_sx=sin((spr.rhe)*PI/180.0), rot_cx=cos((spr.rhe)*PI/180.0);
	real rot_sy=sin(-(spr.rti+90.0)*PI/180.0), rot_cy=cos(-(spr.rti+90.0)*PI/180.0);
	real rot_sz=sin(spr.rst*PI/180.0), rot_cz=cos(-spr.rst*PI/180.0);
	real minx=10e99, maxx=-10e99, miny=10e99, maxy=-10e99, minz=10e99, maxz=-10e99;
	for(uint edgeindex=0; edgeindex<8; edgeindex++){
		real fnx=cast(real)(toint(edgeindex%2)*spr.model.xsize);
		real fny=cast(real)(toint((edgeindex%4)>1)*spr.model.ysize);
		real fnz=cast(real)(toint(edgeindex>3)*spr.model.zsize);
		fnx=(fnx-spr.model.xpivot+.5)*spr.xdensity;
		fny=(fny-spr.model.ypivot+.5)*spr.ydensity;
		fnz=(fnz-spr.model.zpivot-.5)*spr.zdensity;
		real rot_y=fny, rot_z=fnz, rot_x=fnx;
		fny=rot_y*rot_cx - rot_z*rot_sx; fnz=rot_y*rot_sx + rot_z*rot_cx;
		rot_x=fnx; rot_z=fnz;
		fnz=rot_z*rot_cy - rot_x*rot_sy; fnx=rot_z*rot_sy + rot_x*rot_cy;
		rot_x=fnx; rot_y=fny;
		fnx=rot_x*rot_cz - rot_y*rot_sz; fny=rot_x*rot_sz + rot_y*rot_cz;
		fnx+=spr.xpos; fny+=spr.ypos; fnz+=spr.zpos;
		minx=min(fnx, minx); maxx=max(fnx, maxx); miny=min(fny, miny); maxy=max(fny, maxy); minz=min(fnz, minz); maxz=max(fnz, maxz);
	}
	auto start=Vector_t!(3, real)(minx, miny, minz), end=Vector_t!(3, real)(maxx, maxy, maxz);
	auto size=end-start;
	auto mpos=start+size/2.0;
	auto plane=Vector_t!(4, real)(dir.x, dir.y, dir.z, dir.dot(-mpos));
	real slength=-(plane.x*pos.x+plane.y*pos.y+plane.z*pos.z+plane.w);
	real slength_div=(plane.x*dir.x+plane.y*dir.y+plane.z*dir.z);
	auto plane_point=((Vector_t!(3, real)(pos)+Vector_t!(3, real)(dir)*slength/slength_div)-mpos).vecabs-Vector_t!(3, real)(spr.density)*tolerance;
	return (plane_point.x<=size.x && plane_point.y<=size.y && plane_point.z<=size.z);
}

uint Calculate_Alpha(uint c1, uint c2, ushort alpha){
	ushort inv_alpha=255-to!ubyte(alpha);
	return (((((c1>>24)&255)*alpha+((c2>>24)&255)*inv_alpha)>>8)<<24) | (((((c1>>16)&255)*alpha+((c2>>16)&255)*inv_alpha)>>8)<<16) |
	(((((c1>>8)&255)*alpha+((c2>>8)&255)*inv_alpha)>>8)<<8) | (((c1&255)*alpha+(c2&255)*inv_alpha)>>8);
}

uint Color_ActionPerComponent(string action, Args ...)(uint col, Args args){
	uint ret, a;
	a=(col>>24)&255; a=mixin(action); ret=a<<24;
	a=(col>>16)&255; a=mixin(action); ret|=a<<16;
	a=(col>>8)&255; a=mixin(action); ret|=a<<8;
	a=(col>>0)&255; a=mixin(action); ret|=a<<0;
	return ret;
}

//Never change this format
extern(C){
struct ModelVoxel_t{
	uint color;
	ushort ypos;
	char visiblefaces, normalindex;
}

struct CModel_t{
	float xpivot, ypivot, zpivot;
	int xsize, ysize, zsize;
	ModelVoxel_t *voxels;
	size_t voxels_size;
	uint *offsets;
	size_t offsets_size;
	ushort *column_lengths;
	size_t column_lengths_size;
}
}

struct Model_t{
	union{
		struct{
			int xsize, ysize, zsize;
		}
		Vector_t!(3, uint) size;
	}
	union{
		struct{
			float xpivot, ypivot, zpivot;
		}
		Vector3_t pivot;
	}
	static if(is(Renderer_ModelAttachment_t)){
		Renderer_ModelAttachment_t renderer_attachment;
	}
	Model_t *lower_mip_levels;
	ModelVoxel_t[] voxels;
	uint[] offsets;
	ushort[] column_lengths;
	alias copy=dup;
	Model_t *dup(){
		Model_t *newmodel=new Model_t;
		newmodel.xsize=xsize; newmodel.ysize=ysize; newmodel.zsize=zsize;
		newmodel.xpivot=xpivot; newmodel.ypivot=ypivot; newmodel.zpivot=zpivot;
		newmodel.lower_mip_levels=lower_mip_levels;
		newmodel.voxels.length=voxels.length; newmodel.voxels[]=voxels[];
		newmodel.offsets.length=offsets.length; newmodel.offsets[]=offsets[];
		newmodel.column_lengths.length=column_lengths.length; newmodel.column_lengths[]=column_lengths[];
		return newmodel;
	}
	ModelVoxel_t[][] opCast(){
		ModelVoxel_t[][] ret;
		ret.length=xsize*zsize;
		for(uint x=0; x<xsize; x++){
			for(uint z=0; z<zsize; z++){
				ret[x+z*xsize]=voxels[offsets[x+z*xsize]..offsets[x+z*xsize]+column_lengths[x+z*xsize]];
			}
		}
		return ret;
	}
	Model_t *opBinary(string op)(uint sizeincrease) if(op=="<<"){
		if(sizeincrease<2)
			return &this;
		ModelVoxel_t[][] oldvoxels=cast(ModelVoxel_t[][])this;
		ModelVoxel_t[][] retoldvoxels;
		retoldvoxels.length=oldvoxels.length*sizeincrease*sizeincrease;
		for(uint x=0; x<xsize; x++){
			for(uint z=0; z<zsize; z++){
				for(uint x2=0; x2<sizeincrease; x2++){
					for(uint z2=0; z2<sizeincrease; z2++){
						retoldvoxels[x*sizeincrease+x2+(z*sizeincrease+z2)*xsize*sizeincrease].length=oldvoxels[x+z*xsize].length*sizeincrease;
						foreach(ind, vox; oldvoxels[x+z*xsize]){
							vox.ypos*=sizeincrease;
							for(uint y2=0; y2<sizeincrease; y2++){
								vox.ypos++;
								retoldvoxels[x*sizeincrease+x2+(z*sizeincrease+z2)*xsize*sizeincrease][ind*sizeincrease+y2]=vox;
							}
						}
					}
				}
			}
		}
		uint min_y=uint.max;
		foreach(ref voxcol; retoldvoxels){
			foreach(ref vox; voxcol)
				min_y=min(min_y, vox.ypos);
		}
		foreach(ref voxcol; retoldvoxels){
			foreach(ref vox; voxcol)
				vox.ypos-=min_y;
		}
		return Model_FromVoxelArray(retoldvoxels, xsize*sizeincrease, zsize*sizeincrease);
	}
	Model_t*[] opBinary(string op)(uint parts) if(op=="/"){
		if(parts%2)
			return null;
		if(parts>2){
			Model_t *[] ret;
			for(uint i=0; i<cast(uint)(log(parts)/log(2)); i++){
				auto p=this.opBinary!("/")(2);
				ret~=p[0]; ret~=p[1];
			}
			return ret;
		}
		Model_t*[] ret;
		Vector3_t normal=RandomVector(), pos=Vector3_t(size)/2;
		ModelVoxel_t[][] voxels1, voxels2;
		voxels1.length=voxels2.length=xsize*zsize;
		for(uint z=0; z<zsize; z++){
			for(uint x=0; x<xsize; x++){
				foreach(vox; voxels[offsets[x+z*xsize]..offsets[x+z*xsize]+column_lengths[x+z*xsize]]){
					Vector3_t vpos=Vector3_t(x, vox.ypos, z)-size;
					if(vpos.dot(normal)<0.0)
						voxels1[x+z*xsize]~=vox;
					else
						voxels2[x+z*xsize]~=vox;
				}
			}
		}
		ret~=Model_FromVoxelArray(voxels1, xsize, zsize);
		ret~=Model_FromVoxelArray(voxels2, xsize, zsize);
		return ret;
	}
}
Model_t *Model_FromVoxelArray(ModelVoxel_t[][] _voxels, uint xsize, uint zsize){
	ModelVoxel_t[][] voxels=_voxels.dup;
	for(uint zctr=0; zctr<zsize; zctr++){
		bool empty_rows=true;
		for(uint x=0; x<xsize; x++){
			if(voxels[x].length){
				empty_rows=false;
				break;
			}
		}
		if(!empty_rows)
			break;
		for(uint z=0; z<zsize-1; z++){
			for(uint x=0; x<xsize; x++){
				voxels[x+z*xsize]=voxels[x+(z+1)*xsize];
			}
		}
		for(uint x=0; x<xsize; x++)
			voxels[x+(zsize-1)*xsize].length=0;
	}
	for(uint xctr=0; xctr<xsize; xctr++){
		bool empty_rows=true;
		for(uint z=0; z<zsize; z++){
			if(voxels[z*xsize].length){
				empty_rows=false;
				break;
			}
		}
		if(!empty_rows)
			break;
		for(uint z=0; z<zsize; z++){
			for(uint x=0; x<xsize-1; x++){
				voxels[x+z*xsize]=voxels[x+1+z*xsize];
			}
		}
		for(uint z=0; z<zsize; z++)
			voxels[xsize-1+z*xsize].length=0;
	}
	uint origzsize=zsize;
	for(uint zctr=0; zctr<origzsize; zctr++){
		bool empty_rows=true;
		for(uint x=0; x<xsize; x++){
			if(voxels[x+(zsize-1)*xsize].length){
				empty_rows=false;
				break;
			}
		}
		if(!empty_rows)
			break;
		zsize--;
		ModelVoxel_t[][] nvoxels;
		nvoxels.length=xsize*zsize;
		for(uint x=0; x<xsize; x++){
			for(uint z=0; z<zsize; z++){
				nvoxels[x+z*xsize]=voxels[x+z*xsize];
			}
		}
		voxels=nvoxels;
	}
	uint origxsize=xsize;
	for(uint xctr=0; xctr<origxsize; xctr++){
		bool empty_rows=true;
		for(uint z=0; z<zsize; z++){
			if(voxels[xsize-1+z*xsize].length){
				empty_rows=false;
				break;
			}
		}
		if(!empty_rows)
			break;
		xsize--;
		ModelVoxel_t[][] nvoxels;
		nvoxels.length=xsize*zsize;
		for(uint x=0; x<xsize; x++){
			for(uint z=0; z<zsize; z++){
				nvoxels[x+z*xsize]=voxels[x+z*(xsize+1)];
			}
		}
		voxels=nvoxels;
	}
	Model_t *model=new Model_t;
	uint voxelcount=0, min_y=uint.max, max_y=uint.min;
	foreach(ref voxcol; voxels){
		voxelcount+=voxcol.length;
		voxcol.sort!("a.ypos<b.ypos");
		if(voxcol.length){
			min_y=min(voxcol[0].ypos, min_y); max_y=max(voxcol[$-1].ypos, max_y);
		}
	}
	model.voxels.length=voxelcount;
	model.xsize=xsize; model.ysize=max_y-min_y+1; model.zsize=zsize;
	model.pivot=Vector3_t(model.size)*.5;
	model.lower_mip_levels=null;
	model.offsets.length=model.column_lengths.length=xsize*zsize;
	uint offset=0;
	for(uint x=0; x<xsize; x++){
		for(uint z=0; z<zsize; z++){
			ushort col_len=to!ushort(voxels[x+z*xsize].length);
			model.column_lengths[x+z*xsize]=col_len;
			model.voxels[offset..offset+col_len]=voxels[x+z*xsize];
			model.offsets[x+z*xsize]=offset;
			offset+=col_len;
		}
	}
	return model;
	
}

struct SpriteRenderData_t{
	Model_t *model;
	Vector3_t size;
	uint color_mod, replace_black;
	ubyte check_visibility;
	float motion_blur;
	this(Model_t *imodel){
		model=imodel;
		color_mod=0; replace_black=0;
		check_visibility=0;
		size=Vector3_t(model.size);
		motion_blur=0.0;
	}
}

//TODO: DEFAULT INITIALIZER (WHEN COMPILING WITH LDC AND MAX OPTIMIZATION, STRUCTS AREN'T AUTO-INITIALIZED) (UNIMPORTANT)
//NOTE: ACCESSING ROTATION, POSITION OR DENSITY VIA rhe/rti/rst, xpos/ypos/zpos or xdensity/ydensity/zdensity IS DEPRECATED, DON'T DO THAT ANYMORE
struct Sprite_t{
	union{
		//(rhe = height rotation, rti = left/right rotation, rst = tilt)
		struct{
			float rhe, rti, rst;
		}
		Vector3_t rot;
	}
	union{
		struct{
			float xpos, ypos, zpos;
		}
		Vector3_t pos;
	}
	union{
		struct{
			float xdensity, ydensity, zdensity;
		}
		Vector3_t density;
	}
	uint color_mod, replace_black;
	ubyte check_visibility;
	Model_t *model;
	ubyte motion_blur;
	this(Model_t *imodel){
		rot=pos=Vector3_t(0.0);
		density=Vector3_t(1.0);
		color_mod=0; replace_black=0; check_visibility=0;
		model=imodel;
		motion_blur=0;
	}
}
