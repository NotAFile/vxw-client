version(LDC){
	import ldc_stdlib;
}
version(GNU){
	import gdc_stdlib;
}
import sdl2;
import std.math;
import std.format;
import std.algorithm;
import std.range;
import std.conv;
import std.random;
import std.traits;
import std.string;
import std.variant;
import main;
import renderer;
import renderer_templates;
import protocol;
import packettypes;
import modlib;
import misc;
import world;
import snd;
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

auto CameraRot=Vector_t!(3, real)(0.0, 0.0, 0.0), CameraPos=Vector3_t(0.0, 0.0, 0.0);
auto MouseRot=Vector_t!(3, real)(0.0, -90.0, 0.0);
float X_FOV=90.0, Y_FOV=90.0;

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
	if(SDL_Init(SDL_INIT_TIMER | SDL_INIT_VIDEO | SDL_INIT_EVENTS))
		writeflnlog("[WARNING] SDL2 didn't initialize properly: %s", fromStringz(SDL_GetError()));
	if(IMG_Init(IMG_INIT_PNG)!=IMG_INIT_PNG)
		writeflnerr("SDL2 IMG doesn't support PNG: %s", IMG_GetError());
	SDL_SetHintWithPriority(toStringz("SDL_HINT_WINDOWS_NO_CLOSE_ON_ALT_F4"), toStringz("1"), SDL_HINT_OVERRIDE);
	Renderer_Init();
	WindowXSize=Config_Read!uint("resolution_x"); WindowYSize=Config_Read!uint("resolution_y");
	SDL_WindowFlags window_flags=cast(SDL_WindowFlags)
	(Renderer_WindowFlags | SDL_WINDOW_RESIZABLE | (Config_Read!bool("fullscreen")!=0 ? SDL_WINDOW_FULLSCREEN : 0));
	scrn_window=SDL_CreateWindow("Voxelwar", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, WindowXSize, WindowYSize, window_flags);
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
	Renderer_SetLOD(Config_Read!float("render_lod"));
	foreach(ref elem; MenuElements){elem.AdjustToScreen();}
	foreach (ref tbox; TextBoxes){tbox.AdjustToScreen();}
	if(ProtocolBuiltin_AmmoCounterBG)
		ProtocolBuiltin_AmmoCounterBG.AdjustToScreen();
	if(ProtocolBuiltin_AmmoCounterBullet)
		ProtocolBuiltin_AmmoCounterBullet.AdjustToScreen();
	enum ParticleSizeRatios=[
		ParticleSizeTypes.BlockDamageParticle: fVector3_t(.05, .05, .05),
		ParticleSizeTypes.DamagedObjectParticle: fVector3_t(.1, .1, .1),
	];
	foreach(sizetype; EnumMembers!ParticleSizeTypes){
		ParticleSizes[sizetype]=Vector_t!(3, RendererParticleSize_t)(Renderer_GetParticleSize(ParticleSizeRatios[sizetype]));
	}
	foreach(ref ptcls; ParticleCategories)
		ptcls.size=Renderer_GetParticleSize(ptcls.ParticleType.size);
}

enum ParticleSizeTypes{
	BlockDamageParticle, DamagedObjectParticle
}

alias ParticleSize_t=Vector_t!(3, RendererParticleSize_t);

ParticleSize_t[ParticleSizeTypes] ParticleSizes;

SDL_Surface *MapLoadingSrfc;
RendererTexture_t MapLoadingTex;
void Gfx_MapLoadingStart(uint xsize, uint zsize){
	MapLoadingSrfc=SDL_CreateRGBSurface(0, xsize, zsize, 32, 0, 0, 0, 0);
	(cast(uint*)MapLoadingSrfc.pixels)[0..xsize*zsize]=0;
	MapLoadingTex=Renderer_NewTexture(xsize, zsize, true);
	SDL_SetWindowTitle(scrn_window, toStringz("[VoxelWar] Loading map \""~CurrentMapName~"\" ..."));
}

void Gfx_OnMapDataAdd(uint[] loading_map){
	uint[] map_pixels=cast(uint[])((cast(uint*)MapLoadingSrfc.pixels)[0..MapLoadingSrfc.w*MapLoadingSrfc.h]);
	SDL_SetWindowTitle(scrn_window, toStringz("[VoxelWar] Loading map \""~CurrentMapName~"\" ... ("~to!string(loading_map.length*400/MapTargetSize)~"%)"));
	try{
		_sGfx_OnMapDataAdd(loading_map, map_pixels);
	}
	catch(core.exception.RangeError){}
}

@safe void _sGfx_OnMapDataAdd(uint[] loading_map, uint[] map_pixels){
	uint maxx, maxz;
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

void Render_Text_Line(TC, TL)(uint xpos, uint ypos, TC coloring, TL text, RendererTexture_t font, uint font_w, uint font_h, uint letter_padding){
	return Render_Text_Line(xpos, ypos, coloring, text, font, font_w, font_h, letter_padding, null);
}

void Render_Text_Line(TC, TL, TS)(uint xpos, uint ypos, TC coloring, TL text, RendererTexture_t font, uint font_w, uint font_h, uint letter_padding, TS args){
	if(!font)
		return;
	SDL_Rect lrect, fontsrcrect;
	lrect.x=xpos; lrect.y=ypos;
	fontsrcrect.w=font_w/16; fontsrcrect.h=font_h/16;
	uint padding=letter_padding*2;
	immutable char tab_char='	';
	string[] lines;
	static if(is(TL==string[]))
		lines=text;
	else
		lines=[text];
	uint[] cols;
	static if(is(TC==uint[]))
		cols=coloring;
	else
		cols=[coloring];
	real xsizeratio, ysizeratio;
	static if(is(TS==typeof(null))){
		xsizeratio=1.0; ysizeratio=1.0;
	}
	else
	static if(isArray!TS){
		static if(isFloatingPoint!(typeof(args[0]))){
			xsizeratio=args[0]; ysizeratio=args[1];
		}
		else{
			size_t maxlinelength=size_t.min;
			foreach(l; lines)
				maxlinelength=max(l.length+count!"a==b"(l, tab_char), maxlinelength);
			if(!maxlinelength)
				return;
			xsizeratio=(args[0]-xpos)/cast(real)maxlinelength/cast(real)fontsrcrect.w;
			ysizeratio=(args[1]-ypos)/cast(real)lines.length/cast(real)fontsrcrect.h;
		}
	}
	else
	static assert(0); //Unknown type of argument passed
	lrect.w=to!int(to!float(fontsrcrect.w)*xsizeratio); lrect.h=to!int(to!float(fontsrcrect.h)*ysizeratio);
	if(Dank_Text){
		lrect.w++; lrect.h++;
	}
	uint[2] texsize=[font_surface.w, font_surface.h];
	foreach(immutable ind, immutable line; lines){
		uint col;
		static if(is(TC==uint[]))
			col=cols[ind];
		else
			col=coloring;
		ubyte[3] cmod;
		immutable auto bgcol=0xff0000a0;
		if(col==Font_SpecialColor){
			cmod=[(bgcol>>16)&255, (bgcol>>8)&255, bgcol&255];
			cmod[]=~cmod[];
		}
		else{
			cmod=[cast(ubyte)((col>>16)&255),cast(ubyte)((col>>8)&255),cast(ubyte)(col&255)];
		}
		foreach(immutable letter; line){
			bool letter_processed=true;
			switch(letter){
				case '\n':lrect.x=xpos; lrect.y+=lrect.h-padding; break;
				case tab_char:lrect.x+=(lrect.w-padding*xsizeratio)*5; break;
				default:letter_processed=false; break;
			}
			if(letter_processed) continue;
			fontsrcrect.x=(letter%16)*fontsrcrect.w;
			fontsrcrect.y=(letter/16)*fontsrcrect.h;
			if(col==Font_SpecialColor)
				Renderer_FillRect2D(&lrect, bgcol);
			Renderer_Blit2D(font, &texsize, &lrect, col>>24, &cmod, &fontsrcrect);
			lrect.x+=lrect.w-padding*xsizeratio;
		}
		lrect.x=xpos; lrect.y+=lrect.h-padding;
	}
}

auto Render_Text(uint x, uint y, string text, Variant[string] opt_args=null){
	return Render_Text(SDL_Rect(x, y, ScreenXSize-x, ScreenYSize-y), text, opt_args);
}

uint[2] Render_Text(SDL_Rect dstrect, string text, Variant[string] opt_args=null){
	auto font=OptionalArguments_Read!RendererTexture_t(opt_args, "font", font_texture);
	auto texsize=Renderer_TextureSize(font);
	SDL_Rect letter_src_rect=SDL_Rect(0, 0, OptionalArguments_Read!uint(opt_args, "src_w", FontWidth/16),
	OptionalArguments_Read!uint(opt_args, "src_h", FontHeight/16));
	SDL_Rect letter_dst_rect=SDL_Rect(dstrect.x, dstrect.y, 
	OptionalArguments_Read!uint(opt_args, "dst_w", letter_src_rect.w), OptionalArguments_Read!uint(opt_args, "dst_h", letter_src_rect.h));
	immutable src_y_padding=OptionalArguments_Read!uint(opt_args, "src_y_padding", 0);
	immutable src_x_padding=OptionalArguments_Read!uint(opt_args, "src_x_padding", 0);
	immutable coloring=OptionalArguments_Read!Variant(opt_args, "color", Variant(Font_SpecialColor));
	immutable auto_line_break=OptionalArguments_Read!bool(opt_args, "auto_line_break", true);
	foreach(immutable letter_ind, immutable letter; text){
		uint col;
		if(coloring.type==typeid(uint)){
			col=coloring.get!(uint);
		}
		else{
			col=coloring[letter_ind].get!(uint);
		}
		ubyte[3] cmod;
		immutable bgcol=0xff0000a0;
		if(col==Font_SpecialColor){
			cmod=[(bgcol>>16)&255, (bgcol>>8)&255, bgcol&255];
			cmod[]=~cmod[];
		}
		else{
			cmod=[cast(ubyte)((col>>16)&255),cast(ubyte)((col>>8)&255),cast(ubyte)(col&255)];
		}
		bool letter_processed=false;
		switch(letter){
			case '\n':letter_dst_rect.x=dstrect.x; letter_dst_rect.y+=letter_dst_rect.h-src_y_padding; letter_processed=true; break;
			case '\t':letter_dst_rect.x+=letter_dst_rect.w*5; letter_processed=true; break;
			default:break;
		}
		if(letter_processed)
			continue;
		letter_src_rect.x=(letter%16)*letter_src_rect.w;
		letter_src_rect.y=(letter/16)*letter_src_rect.h;
		if(col==Font_SpecialColor)
			Renderer_FillRect2D(&letter_dst_rect, bgcol);
		Renderer_Blit2D(font, &texsize, &letter_dst_rect, cast(ubyte)(col>>24), &cmod, &letter_src_rect);
		letter_dst_rect.x+=letter_dst_rect.w-src_x_padding;
		if(letter_dst_rect.x>=dstrect.w){
			if(auto_line_break){
				letter_dst_rect.x=dstrect.x;
				letter_dst_rect.y+=letter_dst_rect.h-src_y_padding;
			}
			else{
				break;
			}
				
		}
	}
	return [cast(uint)letter_dst_rect.x, cast(uint)letter_dst_rect.y];
}

void Render_World(alias UpdateGfx=true)(bool Render_Cursor){
	Renderer_DrawVoxels();
	for(uint p=0; p<Players.length; p++){
		Render_Player(p);
	}
	if(ProtocolBuiltin_BlockBuildWireframe && Joined_Game()){
		if(Players[LocalPlayerID].equipped_item && Players[LocalPlayerID].Spawned){
			ItemType_t *type = &ItemTypes[Players[LocalPlayerID].equipped_item.type];
			if(type.use_range){
				auto rc=RayCast(CameraPos, Players[LocalPlayerID].dir, ItemTypes[Players[LocalPlayerID].equipped_item.type].use_range);
				auto collside=rc.collside;
				if(collside==2 && Players[LocalPlayerID].dir.y>0.0 && rc.y<=0)
					collside=0;
				if(rc.colldist<=type.use_range && collside){
					Sprite_t spr;
					spr.rhe=0.0; spr.rti=0.0; spr.rst=0.0;
					Vector3_t wfpos=Vector3_t(rc.x, rc.y, rc.z)-Players[LocalPlayerID].dir.sgn().filter(collside==1, collside==2, collside==3)+.5;
					spr.xpos=wfpos.x; spr.ypos=wfpos.y; spr.zpos=wfpos.z;
					spr.xdensity=1.0/ProtocolBuiltin_BlockBuildWireframe.xsize; spr.ydensity=1.0/ProtocolBuiltin_BlockBuildWireframe.ysize;
					spr.zdensity=1.0/ProtocolBuiltin_BlockBuildWireframe.zsize;
					spr.color_mod=(Players[LocalPlayerID].color&0x00ffffff) | 0xff000000;
					spr.replace_black=spr.color_mod;
					spr.model=ProtocolBuiltin_BlockBuildWireframe;
					Renderer_DrawWireframe(spr);
				}
			}
		}
	}
	
	{
		immutable particle_size=ParticleSizes[ParticleSizeTypes.BlockDamageParticle];
		foreach(ref bdmg; BlockDamage){
			foreach(ref prtcl; bdmg.particles){
				Renderer_Draw3DParticle!(true)(prtcl.x, prtcl.y, prtcl.z, particle_size.x, particle_size.y, particle_size.z, prtcl.col);
			}
		}
	}
	{
		immutable particle_size=ParticleSizes[ParticleSizeTypes.DamagedObjectParticle];
		foreach(ref dmgobj_id; DamagedObjects){
			Object_t *dmgobj=&Objects[dmgobj_id];
			foreach(ref prtcl; dmgobj.particles){
				Renderer_Draw3DParticle!(true)(prtcl.x, prtcl.y, prtcl.z, particle_size.x, particle_size.y, particle_size.z, prtcl.col);
			}
		}
	}
	foreach(ref ptcls; ParticleCategories){
		static if(UpdateGfx){
			ptcls.RenderUpdate();
		}
		else{
			ptcls.Render();
		}
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
		immutable SmokeParticleSizeIncrease=1.0f+WorldSpeed*.03f/SmokeAmount*Renderer_SmokeRenderSpeed*3.7;
		immutable SmokeParticleAlphaDecay=(1.0f*.99f)/SmokeParticleSizeIncrease;
		immutable DenseSmokeParticleSizeIncrease=1.0f+WorldSpeed*.01f/SmokeAmount*Renderer_SmokeRenderSpeed*3.7;
		immutable DenseSmokeParticleAlphaDecay=(1.0f*.99f)/DenseSmokeParticleSizeIncrease;
		immutable SmokeRiseSpeed=.001f*WorldSpeed*30.0f, SmokeWiggleSpeed=.0000001f*WorldSpeed*30.0f;
		immutable SmokeFriction=1.0f/(1.0f/.96f+WorldSpeed*30.0/10000.0f);
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
				if(p.alpha<5.0f/256.0f)
					p.alpha=0.0f;
				if(p.size>p.remove_size)
					p.alpha=0.0f;
				p.vel+=RandomVector()*SmokeWiggleSpeed*p.size;	
				p.vel.y-=SmokeRiseSpeed;
				p.vel*=SmokeFriction;
			}
			float dst;
			signed_register_t scrx, scry;
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
			Renderer_DrawSmokeCircle(p.xpos, p.ypos, p.zpos, p.size, p.color, to!ubyte(p.alpha), (Vector_t!(3, real)(p.xpos, p.ypos, p.zpos)-CameraPos).length);
		}
		params.length=0;
		while(SmokeParticles.length){
			if(!SmokeParticles[$-1].alpha)
				SmokeParticles.length--;
			else
				break;
		}
	}
	if(Config_Read!bool("explosion_flashes") || Config_Read!bool("gun_flashes"))
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
			real mousexvel=MouseMovedX*Config_Read!real("mouse_accuracy")*X_FOV/90.0, mouseyvel=MouseMovedY*Config_Read!real("mouse_accuracy")*Y_FOV/90.0;
			MouseMovedX = 0;
			MouseMovedY = 0;
			if(!Menu_Mode){
				if(LocalPlayerScoping()){
					MouseRot.x+=mouseyvel*(uniform01()*2.0-1.0); MouseRot.y+=mousexvel*(uniform01()*2.0-1.0);
					mousexvel*=.6; mouseyvel*=.6;
				}
				MouseRot.x+=mousexvel; MouseRot.y+=mouseyvel;
			}
			if(MouseRot.y<-89.0)
				MouseRot.y=-89.0;
			if(MouseRot.y>89.0)
				MouseRot.y=89.0;
			MouseRot.z=0.0;
			Vector3_t rt;
			rt.x=MouseRot.y;
			rt.y=MouseRot.x;
			rt.z=MouseRot.z;
			if(Render_Local_Player)
				Players[LocalPlayerID].dir=rt.RotationAsDirection;
			CameraPos=Players[LocalPlayerID].CameraPos();
			Sound_SetListenerPos(CameraPos);
			Sound_SetListenerVel(Players[LocalPlayerID].vel);
			CameraRot=MouseRot;
			Sound_SetListenerOri(CameraRot);
			Renderer_SetBlur(Current_Blur_Amount);
			Renderer_SetLOD(Config_Read!float("render_lod")+LocalPlayerScoping()*5.0);
		}
		else{
			MouseRot.x+=MouseMovedX*.7*14.0*Config_Read!float("mouse_accuracy")*X_FOV/90.0; MouseRot.y+=MouseMovedY*.5*14.0*Config_Read!float("mouse_accuracy")*Y_FOV/90.0;
			TerrainOverview.x+=cos(TerrainOverviewRotation*PI/180.0)*.3*WorldSpeed*100.0/3.0;
			TerrainOverview.z+=sin(TerrainOverviewRotation*PI/180.0)*.3*WorldSpeed*100.0/3.0;
			TerrainOverview.y=TerrainOverview.y*.99+(Voxel_GetHighestY(TerrainOverview.x, 0.0, TerrainOverview.z)-48.0)*.01;
			TerrainOverviewRotation=TerrainOverviewRotation*.8+(TerrainOverviewRotation+uniform01()*.1+.9)*.2;
			CameraPos=TerrainOverview;
			Sound_SetListenerPos(CameraPos);
			Sound_SetListenerVel(Vector3_t(0.0));
			CameraRot=MouseRot*Vector_t!(3, real)(.05, .15, 0.0)+Vector_t!(3, real)(0.0, 45.0, 0.0);
			Sound_SetListenerOri(CameraRot);
			MouseMovedX = 0;
			MouseMovedY = 0;
			Renderer_SetBlur(0.0);
			Renderer_SetLOD(Config_Read!float("render_lod"));
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
							Renderer_SetLOD(Config_Read!float("render_lod"));
							auto scope_pic=Renderer_DrawRoundZoomedIn(&res.pos, &res.rot, ProtocolBuiltin_ScopePicture, 1.5, 1.5);
							Renderer_SetLOD(Config_Read!float("render_lod")+5.0);
							MenuElement_t *e=ProtocolBuiltin_ScopePicture;
							if(Config_Read!bool("render_zoomed_scopes")){
								uint[2] size=[scope_pic.scope_texture_width, scope_pic.scope_texture_height];
								Renderer_Blit2D(scope_pic.scope_texture, &size, &scope_pic.dstrect, 255, null, &scope_pic.srcrect);
							}
							uint[2] size=[Mod_Picture_Sizes[e.picture_index][0], Mod_Picture_Sizes[e.picture_index][0]];
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
	if(!LocalPlayerScoping && Joined_Game()){
		foreach(plr; Players){
			if(plr.Spawned && plr.team==Players[LocalPlayerID].team && plr.player_id!=LocalPlayerID){
				auto dist=plr.CameraPos-Players[LocalPlayerID].CameraPos;
				if(dist.dot(Players[LocalPlayerID].dir)/dist.length>1.0-0.004/pow(dist.length, 0.5)){
					auto scrpos=Project2D(plr.CameraPos+Vector3_t(0.0, -.5, 0.0));
					Render_Text_Line(to!uint(scrpos[0]-plr.name.length*FontWidth/16/2), to!uint(scrpos[1]-FontHeight/16),
					Teams[plr.team].icolor|0xff000000, plr.name, font_texture, FontWidth, FontHeight, LetterPadding);
				}
			}
		}
	}
	foreach(ref elements; Z_MenuElements[StartZPos..MiniMapZPos]){
		foreach(e_index; elements){
			MenuElement_Draw(&MenuElements[e_index]);
		}
	}
	Render_HUD();
	immutable ubyte minimap_alpha=210;
	if(Render_MiniMap && Joined_Game() && Current_Screen_Overlay==ScreenOverlays.None){
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
						auto cmarr=Vector_t!(3, uint)(255)-Vector_t!(3, uint)((obj.color>>16)&255, (obj.color>>8)&255, (obj.color>>0)&255);
						cmarr=Vector_t!(3, uint)(255)-((cmarr*alpha)/256);
						colormod=[cast(ubyte)cmarr.elements[0], cast(ubyte)cmarr.elements[1], cast(ubyte)cmarr.elements[2]];
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
		if(Players[LocalPlayerID].Spawned){
			Team_t *team=&Teams[Players[LocalPlayerID].team];
			ubyte[4] col=[team.color[2], team.color[1], team.color[0], 255];
			ubyte[4] plrcol=0xff^col[]; plrcol[3]=255;
			ubyte[4] plrfcol=[255, 192, 0, 255]; 
			foreach(ref plr; Players){
				if(!plr.Spawned || !plr.InGame || plr.team!=Players[LocalPlayerID].team)
					continue;
				int xpos=cast(int)(plr.pos.x*cast(float)(minimap_rect.w)/cast(float)(MapXSize))+minimap_rect.x;
				int zpos=cast(int)(plr.pos.z*cast(float)(minimap_rect.h)/cast(float)(MapZSize))+minimap_rect.y;
				SDL_Rect prct;
				prct.w=5; prct.h=5;
				prct.x=xpos-prct.w/2; prct.y=zpos-prct.h/2;
				Vector3_t _dir=plr.dir.filter(true, false, true);
				_dir=_dir.normal();
				int midx=prct.x+prct.w/2, midy=prct.y+prct.h/2;
				Renderer_DrawLine2D(midx, midy, midx+to!int(_dir.x*10.0), midy+to!int(_dir.z*10.0), &col);
				if(plr.player_id!=LocalPlayerID){
					if(plr.equipped_item){
						if(!(plr.left_click && ItemTypes[plr.equipped_item.type].Is_Gun()))
							Renderer_FillRect2D(&prct, &col);
						else
							Renderer_FillRect2D(&prct, &plrfcol);
					}
					else{
						Renderer_FillRect2D(&prct, &col);
					}
				}
				else{
					prct.w+=2; prct.h+=2;
					prct.x--; prct.y--;
					Renderer_FillRect2D(&prct, &col);
					prct.w-=2; prct.h-=2;
					prct.x++; prct.y++;
					Renderer_FillRect2D(&prct, &plrcol);
				}
			}
		}
		Script_OnMiniMapRender();
	}
	foreach(ref elements; Z_MenuElements[MiniMapZPos..$]) {
		foreach(e_index; elements) {
			MenuElement_Draw(&MenuElements[e_index]);
		}
	}
	if(List_Players){
		Renderer_FillRect2D(null, 0xf0008080);
		//Some random optimization cause I don't want to have to allocate the same stuff on each frame
		static uint[] list_player_amount;
		static uint[][] Player_List_Table;
		list_player_amount.length=Teams.length;
		list_player_amount[0..$]=0;
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
		immutable float letter_xsize=.675*ScreenXSize/800.0;
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
				Color_ActionPerComponent!("min(a<<1, 255)")(Teams[t].icolor)|0xff000000, plrentry, font_texture, FontWidth, FontHeight, LetterPadding, [letter_xsize, 1.0]);
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
			if(!Players[LocalPlayerID].equipped_item)
				return false;
			if(!ItemTypes[Players[LocalPlayerID].equipped_item.type].Is_Gun)
				return false;
			if(!Players[LocalPlayerID].equipped_item.Reloading && MouseRightClick && BlurAmount<.8){
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
		hands_pos=Vector3_t(attached_sprites[0].pos);
	else
		hands_pos=pos+Players[player_id].dir*1.5;
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
			if(!Config_Read!bool("draw_arms"))
				continue;
			Vector3_t hand_offset=(hands_pos-mpos).abs();
			if(player_id==LocalPlayerID){
				mpos-=hand_offset*.6;
				if(LocalPlayerScoping)
					mpos-=hand_offset*.1;
			}
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
	result.rot=Vector3_t(spr.rhe, spr.rti, spr.rst);
	Item_t *item=Players[player_id].equipped_item;
	auto current_tick=PreciseClock_ToMSecs(PreciseClock());
	Vector3_t offset=item.container_type==ItemContainerType_t.Player ? Vector3_t(-.45, -.5, -.5) : Vector3_t(-1.5, 0.0, 0.0);
	result.pos=Validate_Coord(Get_Absolute_Sprite_Coord(&spr, offset+spr.model.pivot));
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
	if(!Players[player_id].equipped_item)
		return [];
	if(ItemTypes[Players[player_id].equipped_item.type].model_id==255)
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
	Item_t *item=plr.equipped_item;
	spr.model=Mod_Models[ItemTypes[item.type].model_id];
	spr.density=Vector3_t(player_id!=LocalPlayerID ? .02 : .04);
	bool item_is_gun=ItemTypes[item.type].Is_Gun();
	Vector3_t target_item_offset;
	if(player_id==LocalPlayerID){
		if(LocalPlayerScoping()){
			auto model_offset=(spr.model.pivot.filter!(true, true, true))*spr.density;
			target_item_offset=Vector3_t(10.0*spr.density.z, 0.0, model_offset.y);
		}
		else{
			if(plr.left_click && !item_is_gun){
				target_item_offset=Vector3_t(1.2, 0.0, .9);
			}
			else{
				target_item_offset=Vector3_t(.7, -.4, .45);
			}
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
	if(player_id==LocalPlayerID && item_is_gun){
		if(current_tick-item.use_timer<ItemTypes[item.type].use_delay){
			item_offset.x-=(1.0-tofloat(current_tick-item.use_timer)/tofloat(ItemTypes[item.type].use_delay))*pow(abs(item.last_recoil), 2.0)*(item.last_recoil!=0.0)*.1;
		}
	}
	//I have no idea what I'm rotating around which axis or idk, actually I am only supposed to need one single rotation
	//But this works (makes the item appear in front of the player with an offset of item_offset, considering his rotation)
	spr.rst=rot.z*0.0; spr.rhe=rot.x; spr.rti=rot.y;
	Vector3_t itempos=pos+item_offset.rotate_raw(Vector3_t(0.0, 90.0-rot.x, 90.0)).rotate_raw(Vector3_t(0.0, 90.0-rot.y+180.0, 0.0));
	spr.xpos=itempos.x; spr.ypos=itempos.y; spr.zpos=itempos.z;
	//BIG WIP
	if(item_is_gun){
		if(!item.Reloading){
			if(current_tick-item.use_timer<ItemTypes[item.type].use_delay)
				spr.rhe-=(1.0-tofloat(current_tick-item.use_timer)/tofloat(ItemTypes[item.type].use_delay))*pow(abs(item.last_recoil), 2.0)*sgn(item.last_recoil)*1.0;
		}
	}
	else
	if(!item.Reloading){
		if(current_tick-item.use_timer<ItemTypes[item.type].use_delay){
			spr.rhe-=(1.0-tofloat(current_tick-item.use_timer)/tofloat(ItemTypes[item.type].use_delay))*pow(abs(item.last_recoil), 1.0)*sgn(item.last_recoil)*20.0;
		}
	}
	if(ItemTypes[item.type].color_mod==true){
		spr.color_mod=(plr.color&0x00ffffff) | 0xff000000;
	}
	else{
		if(!item.heat || !Config_Read!bool("show_gun_heat")){
			spr.color_mod=0;
		}
		else{
			spr.color_mod=0x00ff0000 | (to!ubyte((1.0-1.0/(item.heat+1.0))*255.0)<<24);
		}
	}
	if(item.container_type==ItemContainerType_t.Object){
		auto objspr=Objects[item.container_obj].toSprite();
		spr.model=objspr.model;
		spr.density=objspr.density;
		spr.pos=objspr.pos;
	}
	sprarr~=spr;
	return sprarr;
}

bool SpriteHitScan(in Sprite_t spr, in Vector3_t pos, in Vector3_t dir, out Vector3_t voxpos, out ModelVoxel_t *outvoxptr){
	const(ModelVoxel_t)* voxptr=null;
	auto bound_hitdist=(cast(AABB_t)spr).Intersect(pos, dir);
	if(bound_hitdist!=bound_hitdist)
		return false;
	voxpos=Vector3_t(spr.xpos, spr.ypos, spr.zpos);
	immutable renderrot=Vector_t!(3, real)(spr.rot.x, -(spr.rot.y+90.0), -spr.rot.z);
	auto minvxdist=real.infinity;
	immutable spr_edges=spr.Edge_Vectors();
	immutable minpos=spr_edges[0];
	immutable xdiff=spr_edges[1]/cast(real)spr.model.size.x, ydiff=spr_edges[2]/cast(real)spr.model.size.y, 
	zdiff=spr_edges[3]/cast(real)spr.model.size.z;
	immutable hvoxsize=xdiff*.5+ydiff*.5+zdiff*.5;
	auto vxpos=minpos+hvoxsize;
	immutable invdir=Vector_t!(3, real)(1.0)/dir;
	for(uint blkx=0; blkx<spr.model.xsize; ++blkx, vxpos+=xdiff){
		Vector_t!(3, real) vzpos=0.0;
		for(uint blkz=0; blkz<spr.model.zsize; ++blkz, vzpos+=zdiff){
			foreach(immutable blk; spr.model.voxels[spr.model.offsets[blkx+blkz*spr.model.xsize]..spr.model.offsets[blkx+blkz*spr.model.xsize]
			+cast(uint)spr.model.column_lengths[blkx+blkz*spr.model.xsize]]){	
				if(!blk.visiblefaces)
					continue;
				immutable vmpos=vxpos+ydiff*blk.ypos+vzpos;
				immutable intersect_dist=AABB_t(vmpos-hvoxsize, vmpos+hvoxsize).Intersect_invdir(pos, invdir);
				if(intersect_dist==intersect_dist){
					if(intersect_dist<minvxdist){
						minvxdist=intersect_dist;
						voxpos=Vector3_t(vmpos);
						voxptr=&blk;
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

//ref _this in a struct member is slightly faster than passing a reference to an external function xP
pragma(inline, true){
	struct FireParticle_t{
		enum fVector3_t size=fVector3_t(.75);
		Vector3_t pos, vel;
		uint col, timer;
		enum mixin_InitIter="immutable WorldSpeed_FP=WorldSpeed*(1u<<20);";
		enum mixin_Update="
			particle.timer-=(particle.timer>=WorldSpeed_FP)*WorldSpeed_FP;
			particle.pos+=RandomVector.filter!(1, 0, 1)*WorldSpeed*3.0;
			immutable rnd=uniform01();
			particle.pos.y-=(rnd*rnd)*WorldSpeed*4.0;
			particle.pos+=particle.vel;
			particle.vel*=.5;
			if((Voxel_IsSolid(particle.pos) && particle.vel.abssum()<.05) || particle.timer<WorldSpeed_FP)
				particle.timer=0;
		";
		enum mixin_Render="
			immutable rendersize=[size[0]*particle.timer/(1u<<22), size[1]*particle.timer/(1u<<22), size[2]];
			Renderer_Draw3DParticle(particle.pos, rendersize[0], rendersize[1], rendersize[2], particle.col);
		";
		static void Init(ref FireParticle_t _this, fVector3_t initpos, fVector3_t initvel, real timer_ratio, uint initcol){
			_this.timer=to!uint(uniform(50, 200)*timer_ratio*(1u<<13));
			_this.pos=initpos; _this.vel=initvel; _this.col=initcol;
		}
	}
	//.25 for block break particles
	struct DirtParticle_t{
		enum fVector3_t size=fVector3_t(.1);
		fVector3_t pos, vel;
		uint col, timer;
		enum mixin_InitIter="";
		enum mixin_Update="
			particle.timer--;
			Vector3_t newpos=particle.pos+particle.vel;
			bool y_coll=false;
			if(Voxel_IsSolid(toint(newpos.x), toint(newpos.y), toint(newpos.z))){
				bool in_solid=Voxel_IsSolid(toint(particle.pos.x), toint(particle.pos.y), toint(particle.pos.z));
				if(Voxel_IsSolid(toint(newpos.x), toint(particle.pos.y), toint(particle.pos.z)))
					particle.vel.x=-particle.vel.x;
				if(Voxel_IsSolid(toint(particle.pos.x), toint(particle.pos.y), toint(newpos.z)))
					particle.vel.z=-particle.vel.z;
				if(Voxel_IsSolid(toint(particle.pos.x), toint(newpos.y), toint(particle.pos.z))){
					y_coll=true;
					particle.vel.y=-particle.vel.y*.9;
					particle.vel*=.5;
				}
				else{
					particle.vel*=.5;
				}
				if(in_solid && (particle.col&0xff000000)!=0xff000000){
					particle.timer=0;
					return;
				}
			}
			else{
				particle.pos+=particle.vel;
			}
			particle.vel.y+=.005;
		";
		enum mixin_Render="
			Renderer_Draw3DParticle(particle.pos, size[0], size[1], size[2], particle.col);
		";
	}
	struct BlockBreakParticle_t{
		enum fVector3_t size=fVector3_t(.25);
		fVector3_t pos, vel;
		uint col, timer;
		enum mixin_InitIter="";
		enum mixin_Update="
			if(particle.timer)
				particle.timer--;
			Vector3_t newpos=particle.pos+particle.vel;
			bool y_coll=false;
			if(Voxel_IsSolid(toint(newpos.x), toint(newpos.y), toint(newpos.z))){
				if(Voxel_IsSolid(toint(newpos.x), toint(particle.pos.y), toint(particle.pos.z)))
					particle.vel.x=-particle.vel.x;
				if(Voxel_IsSolid(toint(particle.pos.x), toint(newpos.y), toint(particle.pos.z))){
					y_coll=true;
					particle.vel.y=-particle.vel.y;
				}
				if(Voxel_IsSolid(toint(particle.pos.x), toint(particle.pos.y), toint(newpos.z)))
					particle.vel.z=-particle.vel.z;
				particle.vel*=.3;
			}
			else{
				particle.pos+=particle.vel;
			}
			particle.vel.y+=.005;
		";
		enum mixin_Render="
			Renderer_Draw3DParticle(particle.pos, size[0], size[1], size[2], particle.col);
		";
	}
}

struct ParticleCategory_t(P_Type){
	alias ParticleType=P_Type;
	P_Type[] particles;
	RendererParticleSize_t[3] size;
	void Iterate(alias render=true, alias update=true)(){
		mixin(P_Type.mixin_InitIter);
		foreach(ref particle; particles){
			if(!particle.timer)
				continue;
			static if(render){
				mixin(P_Type.mixin_Render);
			}
			static if(update){
				mixin(P_Type.mixin_Update);
			}
		}
		static if(update){
			while(particles.length){
				if(!particles[$-1].timer)
					particles.length--;
				else
					break;
			}
		}
	}
	void RenderUpdate(){return Iterate!(true, true)();}
	void Render(){return Iterate!(true, false)();}
}

import std.typetuple;
alias ParticleTypes=TypeTuple!(ParticleCategory_t!FireParticle_t, ParticleCategory_t!DirtParticle_t, ParticleCategory_t!BlockBreakParticle_t);
enum ParticleTypeIndexes{
	Fire=0, Dirt=1, BrokenBlock=2
}
immutable(string) __mixin_particletypes_createarray(){
	string ret="AliasSeq!(";
	foreach(ind; 0..ParticleTypes.length){
		ret~="ParticleTypes["~to!string(ind)~"],";
	}
	ret~=")";
	return ret;
}
mixin(__mixin_particletypes_createarray()~" ParticleCategories;");

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

void Create_Particles(Vector3_t pos, Vector3_t vel, float radius, float spread, uint amount, uint[] col, float timer_ratio=1.0){
	amount=to!uint(amount*Config_Read!float("particles"));
	if(!amount)
		return;
	bool use_sent_cols=radius==0;
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
	auto category=&ParticleCategories[ParticleTypeIndexes.Dirt];
	uint old_size=cast(uint)category.particles.length;
	category.particles.length+=amount;
	for(uint i=old_size; i<old_size+amount; i++){
		Vector3_t vspr=Vector3_t(spread*(uniform01()*2.0-1.0), spread*(uniform01()*2.0-1.0), spread*(uniform01()*2.0-1.0));
		category.particles[i].pos=pos;
		category.particles[i].vel=vel+vspr;
		if((uniform(0, 2) || use_sent_cols) && col.length)
			category.particles[i].col=col[uniform(0, col.length)];
		else
			category.particles[i].col=colors[uniform(0, colors.length)];
		category.particles[i].timer=cast(uint)(uniform(300, 400)*timer_ratio);
	}
}

void Create_FireParticles(Vector3_t pos, uint amount, Variant[string] opt_args=null){
	amount=to!uint(amount*Config_Read!float("particles"));
	auto category=&ParticleCategories[ParticleTypeIndexes.Fire];
	uint[] col=OptionalArguments_Read(opt_args, "col", [0x00a08000u, 0x00ffff00u, 0x00ff8000u]);
	real timer_ratio=OptionalArguments_Read(opt_args, "timer_ratio", 1.0);
	real vel_spread=OptionalArguments_Read(opt_args, "vel_spread", 0.0);
	fVector3_t vel=OptionalArguments_Read(opt_args, "vel", fVector3_t(0.0));
	size_t old_size=category.particles.length;
	category.particles.length+=amount;
	enum jitter=64;
	foreach(i; old_size..old_size+amount){
		uint icol;
		if(!uniform(0, 2))
			icol=Calculate_Alpha(col[uniform(0, col.length)], 0, 255-cast(ubyte)uniform(0, jitter));
		else
			icol=Calculate_Alpha(col[uniform(0, col.length)], 0x00ffffff, 255-cast(ubyte)uniform(0, jitter));
		category.particles[i].Init(category.particles[i], pos+RandomVector()*amount/800.0, vel+RandomVector()*vel_spread, timer_ratio, icol);
	}
}

real SmokeAmountCounter=0.0;
void Create_Smoke(Vector3_t pos, float amount, uint col, float size, float speedspread=1.0, float alpha=1.0, Vector3_t cvel=Vector3_t(0)){
	SmokeAmountCounter+=amount*SmokeAmount;
	size_t old_size=SmokeParticles.length;
	uint smoke_amount=to!uint(SmokeAmountCounter);
	SmokeAmountCounter-=smoke_amount;
	SmokeParticles.length+=smoke_amount;
	float sizeratio=pow(size, .2);
	for(size_t i=old_size; i<old_size+smoke_amount; i++){
		Vector3_t spos=pos+RandomVector()*.12*size;
		Vector3_t vel=(RandomVector()*size*.01+(spos-pos)*(.5+sizeratio*.4))*speedspread+cvel;
		SmokeParticles[i].Init(spos, vel,
		Calculate_Alpha(col, Calculate_Alpha(0, 0xffffffff, uniform!ubyte()), 255-to!ubyte(uniform01()*255.0/(1.0+size)*.8)),
		size*80.0*uniform(50, 150)*.01);
		SmokeParticles[i].alpha*=alpha;
	}
}

//Leaving this as it is here (looks nice already, even if far away from being finished), I have other things to do
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
		obj.rot=RandomVector()*360.0;
		timer=.0001;
		split_counter=0;
		obj.vel=RandomVector();
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
		foreach(blk; blocks){
			
			voxels[blk.x-minpos.x+(blk.z-minpos.z)*size.x]~=ModelVoxel_t(blk.w, cast(ushort)(blk.y-minpos.y), 15, 0);
		}
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

Debris_t Blocks_ToDebris(uint[3][] input_blocks){
	int[3] minval=[int.max, int.max, int.max], maxval=[0, 0, 0];
	Vector_t!(4, uint)[] blocks;
	foreach(block; input_blocks){
		if(Voxel_IsSolid(block)){
			blocks~=Vector_t!(4, uint)(block[0], block[1], block[2], Voxel_GetColor(block[0], block[1], block[2]));
			Voxel_Remove(block);
		}
		else{
			blocks~=Vector_t!(4, uint)(block[0], block[1], block[2], 0x00808080);
		}
		foreach(i; 0..3){
			minval[i]=min(minval[i], block[i]);
			maxval[i]=max(maxval[i], block[i]);
		}
	}
	auto middle_vec=Vector_t!(4, uint)(((iVector3_t(maxval)-minval)/2+minval).elements~0);
	Debris_t d=Debris_t(Vector3_t(middle_vec.elements[0..3]), blocks);
	d.obj.rot.y=270.0;
	d.timer=.0001;
	d.split_counter=0;
	d.obj.vel=RandomVector();
	Debris_Parts~=d;
	return d;
}

Model_t *Debris_BaseModel;

struct ExplosionSprite_t{
	Sprite_t spr;
	float size, maxsize;
}
ExplosionSprite_t[] ExplosionEffectSprites;

void Create_Explosion(Vector3_t pos, Vector3_t vel, float radius, float spread, uint amount, uint col, uint timer=0){
	if(Enable_Object_Model_Modification && Config_Read!bool("model_modification")){
		uint explosion_r=(col&255), explosion_g=(col>>8)&255, explosion_b=(col>>16)&255;
		foreach(uint obj_id, obj; Objects){
			if(!obj.modify_model || !obj.visible)
				continue;
			auto spr=Objects[obj_id].toSprite();
			//Crappy early out case check; need to fix this and consider pivots
			Vector3_t dist=(obj.pos-pos).vecabs();
			if(dist.x>radius+spr.model.size.x*2.0 || dist.y>radius+spr.model.size.y*2.0 || dist.z>radius+spr.model.size.z*2.0)
				continue;
			foreach(ref vox, vxpos; spr){
				float vxdist=(vxpos-pos).length*(.8+uniform01()*.2);
				if(vxdist>radius)
					continue;
				uint alpha=touint((vxdist/radius)*255.0);
				uint comp1=vox.color&0x00ff00ff, comp2=vox.color&0x0000ff00;
				vox.color=(((comp1*alpha)>>>8)&0x00ff00ff) | (((comp2*alpha)>>>8)&0x0000ff00);
			}
		}
	}
	//Honestly, that's such a piece of crap that we don't even want to OPTIONALLY expose it to players xd (and we already have enough other cool stuff)
	if(Config_Read!bool("effects") && 0){
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
	Create_Smoke(Vector3_t(pos.x, pos.y, pos.z), amount*.25, 0xff808080, radius);
	Create_Particles(pos, vel, radius, spread, amount*7, [], 1.0/(1.0+amount*.001));
	Create_Particles(pos, vel, 0, spread*3.0, amount*10, [0x00ffff00, 0x00ffa000], .05);
	Create_FireParticles(pos, amount*5, ["vel_spread":Variant(spread)]);
	if(Config_Read!bool("explosion_flashes"))
		Renderer_AddFlash(pos, radius*radius, 10.0);
	//WIP (go cham!)
	//Actually I think that shit is deprecated now with the fire particles engine
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
	if(ProtocolBuiltin_ExplosionSound!=VoidSoundID){
		auto src=SoundSource_t(pos);
		src.Play_Sound(Mod_Sounds[ProtocolBuiltin_ExplosionSound], [SoundPlayOptions.Volume: 1.0-1.0/(pow(radius, 3.0)+1.0)]);
		EnvironmentSoundSources~=src;
	}
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
	Renderer_SetBrightness(strength);
	Renderer_SetBlockFaceShading(Sun_Vector);
}

//Be careful: this is evil
Vector3_t Get_Absolute_Sprite_Coord(Sprite_t *spr, Vector3_t coord){
	float rot_sx=sin((spr.rhe)*PI/180.0), rot_cx=cos((spr.rhe)*PI/180.0);
	float rot_sy=sin(-(spr.rti+90.0)*PI/180.0), rot_cy=cos(-(spr.rti+90.0)*PI/180.0);
	float rot_sz=sin(-spr.rst*PI/180.0), rot_cz=cos(-spr.rst*PI/180.0);
	float fnx=(coord.x-spr.model.xpivot+.5)*spr.xdensity;
	float fny=(coord.y-spr.model.ypivot+.5)*spr.ydensity;
	float fnz=(coord.z-spr.model.zpivot+.5)*spr.zdensity;
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
	if(!Config_Read!bool("sprite_visibility_checks"))
		return true;
	auto edges=(cast(AABB_t)spr).Edges;
	int[8] x_offsets, y_offsets;
	foreach(ind, edge; edges){
		auto coords=Project2D(edge.x, edge.y, edge.z);
		x_offsets[ind]=(coords[0]<0 ? -1 : (coords[0]>ScreenXSize ? 1 : 0));
		y_offsets[ind]=(coords[1]<0 ? -1 : (coords[1]>ScreenYSize ? 1 : 0));
		if(!x_offsets[ind] && !y_offsets[ind])
			return true;
	}
	int[] dx_offsets=x_offsets, dy_offsets=y_offsets;
	if(all!"a==1"(dx_offsets) || all!"a==-1"(dx_offsets) || all!"a==1"(dy_offsets) || all!"a==-1"(dy_offsets))
		return false;
	//Quick hack to prevent the worst for those large ass bombers etc.
	if(spr.model.voxels.length>10000)
		return false;
	return true;
}

uint Calculate_Alpha(uint c1, uint c2, ushort alpha){
	ushort inv_alpha=256-to!ubyte(alpha);
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

T[4] Color_ActionPerComponent(string action, T, Args ...)(T[4] col, Args args){
	T[4] ret;
	ushort a;
	for(uint i=0; i<4; i++){
		a=col[i]; a=cast(typeof(a))mixin(action); ret[i]=cast(T)a;
	}
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
	Model_t *Model_RemoveInvBlocks(){
		Model_t* ret;
		ret.size=size; ret.pivot=pivot;
		return ret;
	}
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
	const nothrow Vector_t!(3, T)[4] Edge_Vectors(T=real)(){
		immutable renderrot=Vector_t!(3, T)(rot.x, -(rot.y+90.0), -rot.z);
		immutable minpos=(Vector_t!(3, T)(-model.pivot)*density).rotate_raw(renderrot)+pos;
		return [minpos,
		((Vector_t!(3, T)(model.size.filter!(1, 0, 0)())-model.pivot)*density).rotate_raw(renderrot)+pos-minpos,
		((Vector_t!(3, T)(model.size.filter!(0, 1, 0)())-model.pivot)*density).rotate_raw(renderrot)+pos-minpos,
		((Vector_t!(3, T)(model.size.filter!(0, 0, 1)())-model.pivot)*density).rotate_raw(renderrot)+pos-minpos];
	}
	const auto opCast(AABB_t)(){
		immutable edges=Edge_Vectors();
		real minx=real.max, maxx=-real.max, miny=real.max, maxy=-real.max, minz=real.max, maxz=-real.max;
		foreach(edgeindex; 0..8){
			immutable voxpos=edges[0]+edges[1]*to!real(edgeindex%2)+edges[2]*to!real((edgeindex%4)>1)+edges[3]*to!real(edgeindex>3);
			minx=min(voxpos.x, minx); maxx=max(voxpos.x, maxx); miny=min(voxpos.y, miny);
			maxy=max(voxpos.y, maxy); minz=min(voxpos.z, minz); maxz=max(voxpos.z, maxz);
		}
		return AABB_t(minx, miny, minz, maxx, maxy, maxz);
	}
	int opApply(scope int delegate(ref ModelVoxel_t vox, immutable in Vector_t!(3, real) pos) dg){
		immutable edges=Edge_Vectors();
		immutable minpos=edges[0];
		immutable xdiff=edges[1]/cast(real)model.size.x, ydiff=edges[2]/cast(real)model.size.y, zdiff=edges[3]/cast(real)model.size.z;
		Vector_t!(3, real) basepos=minpos+xdiff*.5+ydiff*.5+zdiff*.5;
		for(uint blkx=0; blkx<model.size.x; blkx++){
			for(uint blkz=0; blkz<model.size.z; blkz++){
				for(uint blkind=model.offsets[blkx+blkz*model.xsize];
			blkind<model.offsets[blkx+blkz*model.xsize]+cast(uint)model.column_lengths[blkx+blkz*model.xsize]; blkind++){	
					immutable voxpos=basepos+xdiff*blkx+ydiff*model.voxels[blkind].ypos+zdiff*blkz;
					int result=dg(model.voxels[blkind], voxpos);
					if(result)
						return result;
				}
			}
		}
		return 0;
	}
	const Vector_t!(3, T) RelativeCoordinates_To_AbsoluteCoordinates(T=real, T2)(Vector_t!(3, T2) coord){
		auto edges=this.Edge_Vectors!T();
		return edges[0]+edges[1]*coord.x+edges[2]*coord.y+edges[3]*coord.z;
	}
}

Sprite_t Sprite_Void(){
	Sprite_t ret;
	ret.model=null;
	return ret;
}
