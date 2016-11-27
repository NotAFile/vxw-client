import derelict.sdl2.sdl;
import derelict.sdl2.image;
import std.math;
import std.format;
import std.algorithm;
import std.conv;
import std.random;
import std.traits;
import renderer;
import protocol;
import misc;
import world;
import ui;
import vector;
import script;
version(LDC){
	import ldc_stdlib;
}
import core.stdc.stdio;

SDL_Window *scrn_window;

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

uint ScreenXSize=800, ScreenYSize=600;

Vector3_t CameraRot=Vector3_t(0.0, 0.0, 0.0), CameraPos=Vector3_t(0.0, 0.0, 0.0);
Vector3_t MouseRot=Vector3_t(0.0, -90.0, 0.0);
float X_FOV=90.0, Y_FOV=90.0;

float[3][ParticleSizeTypes] ParticleSizeRatios;

KV6Model_t*[] Mod_Models;
RendererTexture_t[] Mod_Pictures;
SDL_Surface*[] Mod_Picture_Surfaces;
uint[2][] Mod_Picture_Sizes;

uint Enable_Shade_Text=0;
uint LetterPadding=0;
immutable bool Dank_Text=false;

Vector3_t TerrainOverview;

bool Do_Sprite_Visibility_Checks=true;

immutable bool Enable_Object_Model_Modification=true;

float BlurAmount=0.0, BaseBlurAmount=0.0, BlurAmountDecay=.99;
float ShakeAmount=0.0, BaseShakeAmount=0.0, ShakeAmountDecay=.9;

ubyte MiniMapZPos=250, InvisibleZPos=0, StartZPos=1;

void Init_Gfx(){
	DerelictSDL2.load();
	DerelictSDL2Image.load();
	if(SDL_Init(SDL_INIT_TIMER | SDL_INIT_VIDEO | SDL_INIT_EVENTS))
		writeflnlog("[WARNING] SDL2 didn't initialize properly: %s", SDL_GetError());
	if(IMG_Init(IMG_INIT_PNG)!=IMG_INIT_PNG)
		writeflnlog("[WARNING] IMG for PNG didn't initialize properly: %s", IMG_GetError());
	Renderer_Init();
	scrn_window=SDL_CreateWindow("Voxelwar", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, ScreenXSize, ScreenYSize, Renderer_WindowFlags);
	Renderer_SetUp();
	{
		SDL_Surface *font_surface=SDL_LoadBMP("./Ressources/Default/Font.png");
		if(font_surface){
			Set_Font(font_surface);
			SDL_FreeSurface(font_surface);
		}
	}
	ParticleSizeRatios=[
		ParticleSizeTypes.Normal: [.1, .1, .1],
		ParticleSizeTypes.BlockDamageParticle: [.05, .05, .05],
		ParticleSizeTypes.DamagedObjectParticle: [.1, .1, .1],
		ParticleSizeTypes.BlockBreakParticle: [.25, .25, .25]
	];
	foreach(sizetype; EnumMembers!ParticleSizeTypes){
		uint[3] pixelsize=Renderer_GetParticleSize(ParticleSizeRatios[sizetype][0], ParticleSizeRatios[sizetype][1], ParticleSizeRatios[sizetype][2]);
		ParticleSizes[sizetype]=ParticleSize_t();
		ParticleSizes[sizetype].w=pixelsize[0]; ParticleSizes[sizetype].h=pixelsize[1]; ParticleSizes[sizetype].l=pixelsize[2];
	}
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
	minimap_texture=Renderer_TextureFromSurface(minimap_srfc);
}

void Update_MiniMap(){
	uint x, y, z;
	uint *pixel_ptr=cast(uint*)minimap_srfc.pixels;
	for(z=0; z<MapZSize; z++){
		for(x=0; x<MapXSize; x++){
			uint col=Voxel_GetColor(x, Voxel_FindFloorZ(x, 0, z), z);
			pixel_ptr[x]=col&0x00ffffff;
		}
		pixel_ptr=cast(uint*)((cast(ubyte*)pixel_ptr)+minimap_srfc.pitch);
	}
	Renderer_UploadToTexture(minimap_srfc, minimap_texture);
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
	if(color!=Font_SpecialColor){
		fontsrcrect.w=font_w/16; fontsrcrect.h=font_h/16;
		padding=letter_padding*2;
	}
	else{
		letter_padding=0;
		fontsrcrect.w=borderless_font_surface.w/16-letter_padding*2; fontsrcrect.h=borderless_font_surface.h/16-letter_padding*2;
		font=borderless_font_texture;
		padding=0;
	}
	lrect.w=to!int(to!float(fontsrcrect.w)*xsizeratio); lrect.h=to!int(to!float(fontsrcrect.h)*ysizeratio);
	if(Dank_Text){
		lrect.w++; lrect.h++;
	}
	uint[2] texsize=[font_surface.w, font_surface.h];
	ubyte[3] cmod=[cast(ubyte)((color>>16)&255),cast(ubyte)((color>>8)&255),cast(ubyte)(color&255)];
	foreach(letter; line){
		bool letter_processed=false;
		switch(letter){
			case '\n':lrect.x=xpos; lrect.y+=lrect.h-padding; letter_processed=true; break;
			default:break;
		}
		if(letter_processed) continue;
		fontsrcrect.x=(letter%16)*fontsrcrect.w;
		fontsrcrect.y=(letter/16)*fontsrcrect.h;
		Renderer_Blit2D(font, &texsize, &lrect, 255, &cmod, &fontsrcrect);
		lrect.x+=lrect.w-padding*xsizeratio;
	}
}

enum ParticleSizeTypes{
	Normal=0, BlockDamageParticle=1, DamagedObjectParticle=2, BlockBreakParticle=3
}

struct ParticleSize_t{
	uint w, h, l;
}

ParticleSize_t[ParticleSizeTypes] ParticleSizes;

uint[][] Player_List_Table;

void Render_World(bool Render_Cursor){
	Renderer_DrawVoxels();
	for(uint p=0; p<Players.length; p++){
		Render_Player(p);
	}
	uint particle_w=ParticleSizes[ParticleSizeTypes.BlockDamageParticle].w, particle_h=ParticleSizes[ParticleSizeTypes.BlockDamageParticle].h,
	particle_l=ParticleSizes[ParticleSizeTypes.BlockDamageParticle].l;
	foreach(ref bdmg; BlockDamage){
		foreach(ref prtcl; bdmg.particles){
			Renderer_Draw3DParticle(prtcl.x, prtcl.y, prtcl.z, particle_w, particle_h, particle_l, prtcl.col);
		}
	}
	particle_w=ParticleSizes[ParticleSizeTypes.DamagedObjectParticle].w, particle_h=ParticleSizes[ParticleSizeTypes.DamagedObjectParticle].h,
	particle_l=ParticleSizes[ParticleSizeTypes.DamagedObjectParticle].l;
	foreach(ref dmgobj_id; DamagedObjects){
		Object_t *dmgobj=&Objects[dmgobj_id];
		foreach(ref prtcl; dmgobj.particles){
			Renderer_Draw3DParticle(prtcl.x, prtcl.y, prtcl.z, particle_w, particle_h, particle_l, prtcl.col);
		}
	}
	particle_w=ParticleSizes[ParticleSizeTypes.Normal].w, particle_h=ParticleSizes[ParticleSizeTypes.Normal].h,
	particle_l=ParticleSizes[ParticleSizeTypes.Normal].l;
	foreach(ref p; Particles){
		if(!p.timer)
			continue;
		if(p.timer)
			p.timer--;
		bool in_solid=Voxel_IsSolid(toint(p.pos.x), toint(p.pos.y), toint(p.pos.z));
		Vector3_t newpos=p.pos+p.vel;
		bool y_coll=false;
		if(Voxel_IsSolid(toint(newpos.x), toint(newpos.y), toint(newpos.z))){
			if(Voxel_IsSolid(toint(newpos.x), toint(p.pos.y), toint(p.pos.z)))
				p.vel.x=-p.vel.x;
			if(Voxel_IsSolid(toint(p.pos.x), toint(p.pos.y), toint(newpos.z)))
				p.vel.z=-p.vel.z;
			if(Voxel_IsSolid(toint(p.pos.x), toint(newpos.y), toint(p.pos.z))){
				y_coll=true;
				p.vel.y=-p.vel.y*.9;
				p.vel*=.7;
			}
			else{
				p.vel*=.7;
			}
			if(in_solid){
				p.timer=0;
				continue;
			}
		}
		else{
			p.pos+=p.vel;
		}
		p.vel.y+=.005;
		Renderer_Draw3DParticle(&p.pos, particle_w, particle_h, particle_l, p.col);
	}
	particle_w=ParticleSizes[ParticleSizeTypes.BlockBreakParticle].w, particle_h=ParticleSizes[ParticleSizeTypes.BlockBreakParticle].h,
	particle_l=ParticleSizes[ParticleSizeTypes.BlockBreakParticle].l;
	foreach(ref p; BlockBreakParticles){
		if(!p.timer)
			continue;
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
		Renderer_Draw3DParticle(&p.pos, particle_w, particle_h, particle_l, p.col);
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
	for(uint o=0; o<Objects.length; o++){
		if(!Objects[o].visible)
			continue;
		Render_Object(o);
	}
	{
		struct DrawSmokeCircleParams{
			float dst;
			uint color, alpha;
			int size;
			float xpos, ypos, zpos;
		}
		DrawSmokeCircleParams[] params;
		float SmokeParticleSizeIncrease=1.0f+WorldSpeed*.09f, SmokeParticleAlphaDecay=(1.0f*.99f)/SmokeParticleSizeIncrease;
		foreach(ref p; SmokeParticles){
			p.size*=SmokeParticleSizeIncrease; p.alpha*=SmokeParticleAlphaDecay;
			p.pos+=p.vel;
			p.vel*=.96f;
			float dst;
			int scrx, scry;
			if(!Project2D(p.pos.x, p.pos.y, p.pos.z, &dst, scrx, scry))
				continue;
			if(dst<=0.0)
				continue;
			uint size=cast(uint)(p.size*90.0/X_FOV/dst);
			uint color=p.col;
			//Vox_Calculate_2DFog(cast(ubyte*)&color, p.pos.x-CameraPos.x, p.pos.y-CameraPos.y);
			uint alpha=cast(uint)(p.alpha*256.0f);
			params~=DrawSmokeCircleParams(dst, color, alpha, size, p.pos.x, p.pos.y, p.pos.z);
			if(p.size>p.remove_size)
				p.alpha=0f;
			if(!alpha)
				p.alpha=0f;
		}
		params.sort!("a.dst>b.dst");
		for(uint i=0; i<params.length; i++){
			DrawSmokeCircleParams *p=&params[i];
			Renderer_DrawSmokeCircle(p.xpos, p.ypos, p.zpos, p.size, p.color, p.alpha, p.dst);
		}
		params.length=0;
	}
	while(SmokeParticles.length){
		if(!SmokeParticles[$-1].alpha)
			SmokeParticles.length--;
		else
			break;
	}
}

void MenuElement_draw(MenuElement_t* e) {
	if(e.inactive()) {
		return;
	}
	SDL_Rect r={e.xpos,e.ypos,e.xsize,e.ysize};
	if((e.icolor_mod&0x00ffffff)!=0x00ffffff) { //bcolor_mod exists
		ubyte[3] cmod=e.bcolor_mod; cmod.reverse;
		Renderer_Blit2D(Mod_Pictures[e.picture_index], &Mod_Picture_Sizes[e.picture_index], &r, e.transparency, &cmod);
	} else {
		Renderer_Blit2D(Mod_Pictures[e.picture_index], &Mod_Picture_Sizes[e.picture_index], &r, e.transparency);
	}
}

void MenuElement_draw(MenuElement_t* e, int x, int y, int w, int h) {
	if(e.inactive() || !w || !h) {
		return;
	}
	SDL_Rect r={x, y, w, h};
	if((e.icolor_mod&0x00ffffff)!=0x00ffffff) { //bcolor_mod exists
		ubyte[3] cmod=e.bcolor_mod; cmod.reverse;
		Renderer_Blit2D(Mod_Pictures[e.picture_index], &Mod_Picture_Sizes[e.picture_index], &r, e.transparency, &cmod);
	} else {
		Renderer_Blit2D(Mod_Pictures[e.picture_index], &Mod_Picture_Sizes[e.picture_index], &r, e.transparency);
	}
}

void Render_Screen(){
	Renderer_SetCamera(CameraRot.x, CameraRot.y, CameraRot.z, X_FOV, Y_FOV, CameraPos.x, CameraPos.y, CameraPos.z);
	if(LoadedCompleteMap){
		Renderer_StartRendering(true);
		Render_World(false);
	} else {
		Renderer_StartRendering(false);
	}
	bool Render_Local_Player=false;
	bool Render_Scope=false;
	if(Joined_Game()){
		Render_Local_Player|=Players[LocalPlayerID].Spawned && Players[LocalPlayerID].InGame;
	}
	if(LoadedCompleteMap){
		Vector3_t pos;
		if(Render_Local_Player){
			float mousexvel=MouseMovedX*.5*MouseAccuracyConst*X_FOV/90.0, mouseyvel=MouseMovedY*.5*MouseAccuracyConst*Y_FOV/90.0;
			if(!Menu_Mode){
				if(Players[LocalPlayerID].item_types.length){
					if(ItemTypes[Players[LocalPlayerID].items[Players[LocalPlayerID].item].type].is_weapon){
						if(MouseRightClick){
							MouseRot.x+=mouseyvel*(uniform01()*2.0-1.0)*.75; MouseRot.y+=mousexvel*(uniform01()*2.0-1.0)*.75;
							mousexvel*=.6; mouseyvel*=.6;
						}
					}
				}
				MouseRot.x+=mousexvel; MouseRot.y+=mouseyvel;
			}
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
			pos=Players[LocalPlayerID].pos;
			CameraPos=pos;
			CameraRot=MouseRot;
		}
		else{
			MouseRot.x+=MouseMovedX*.7; MouseRot.y+=MouseMovedY*.5;
			TerrainOverview.y+=uniform01()*.5;
			TerrainOverview.x+=cos(TerrainOverview.y*PI/180.0)*.3;
			TerrainOverview.z+=sin(TerrainOverview.y*PI/180.0)*.3;
			pos=TerrainOverview;
			pos.y=-15.0;
			Vector3_t crot=MouseRot*.05+Vector3_t(0.0, 45.0, 0.0);
			CameraPos=pos;
			CameraRot=crot;
		}
		CameraPos.x+=(uniform01()*2.0-1.0)*(ShakeAmount+BaseShakeAmount);
		CameraPos.y+=(uniform01()*2.0-1.0)*(ShakeAmount+BaseShakeAmount);
		CameraPos.z+=(uniform01()*2.0-1.0)*(ShakeAmount+BaseShakeAmount);
		Renderer_SetCamera(CameraRot.x, CameraRot.y, CameraRot.z, X_FOV, Y_FOV, CameraPos.x, CameraPos.y, CameraPos.z);
		if(Render_Local_Player)
			Update_Rotation_Data();
		Do_Sprite_Visibility_Checks=true;
		{
			if(Render_Local_Player){
				if(Players[LocalPlayerID].item_types.length){
					if(ItemTypes[Players[LocalPlayerID].item_types[Players[LocalPlayerID].item]].is_weapon
					&& !Players[LocalPlayerID].items[Players[LocalPlayerID].item].Reloading && MouseRightClick){
						if(ProtocolBuiltin_ScopePicture){
							Render_Scope=true;
							Render_Round_ZoomedIn(400, 300, Mod_Picture_Sizes[ProtocolBuiltin_ScopePicture.picture_index][0]/2, 1.1, 1.1);
						}
					}
				}
			}
		}
	}
	
	//SDL_SetRenderTarget(scrn_renderer, scrn_texture);
	/*{
		//SDL_SetTextureColorMod(vxrend_texture, (VoxlapInterface.fogcol>>16)&255, (VoxlapInterface.fogcol>>8)&255, (VoxlapInterface.fogcol>>0)&255);
		/*{
			float fr=(Fog_Color>>16)&255, fg=(Fog_Color>>8)&255, fb=(Fog_Color>>0)&255;
			immutable float fog_alpha=.15;
			float r=fr*fog_alpha+255.0*(1.0-fog_alpha), g=fg*fog_alpha+255.0*(1.0-fog_alpha), b=fb*fog_alpha+255.0*(1.0-fog_alpha);
			SDL_SetTextureColorMod(vxrend_texture, cast(ubyte)r, cast(ubyte)g, cast(ubyte)b);
		}
		SDL_SetTextureBlendMode(vxrend_texture, SDL_BLENDMODE_BLEND);
		SDL_SetTextureAlphaMod(vxrend_texture, cast(ubyte)(32+(tofloat(255-32)/(1.0+BlurAmount+BaseBlurAmount))));
		SDL_RenderCopy(scrn_renderer, vxrend_texture, null, &dstrect);
		if(Render_Scope){
			MenuElement_t *e=ProtocolBuiltin_ScopePicture;
			SDL_Rect r;
			r.w=Mod_Picture_Sizes[e.picture_index][0]; r.h=Mod_Picture_Sizes[e.picture_index][1];			
			r.x=e.xpos-r.w/2+shakex; r.y=e.ypos-r.h/2+shakey;
			if(e.transparency<255)
				SDL_SetTextureAlphaMod(Mod_Pictures[e.picture_index], e.transparency);
			SDL_RenderCopy(scrn_renderer, Mod_Pictures[e.picture_index], null, &r);
			if(e.transparency<255)
				SDL_SetTextureAlphaMod(Mod_Pictures[e.picture_index], 255);
		}
	}*/
	Renderer_Start2D();
	foreach(ref elements; Z_MenuElements[StartZPos..MiniMapZPos]) {
		foreach(e_index; elements) {
			MenuElement_draw(&MenuElements[e_index]);
		}
	}
	Render_HUD();
	immutable ubyte minimap_alpha=210;
	if(Render_MiniMap && Joined_Game()){
		SDL_Rect minimap_rect;
		Team_t *team=&Teams[Players[LocalPlayerID].team];
		minimap_rect.x=0; minimap_rect.y=0; minimap_rect.w=ScreenXSize; minimap_rect.h=ScreenYSize;
		uint[2] minimap_size=[minimap_srfc.w, minimap_srfc.h];
		Renderer_Blit2D(minimap_texture, &minimap_size, &minimap_rect, 255);
		ubyte[4] col=[team.color[2], team.color[1], team.color[0], 255];
		ubyte[4] plrcol=0xff^col[];
		foreach(ref plr; Players){
			if(!plr.Spawned || !plr.InGame || plr.team!=Players[LocalPlayerID].team)
				continue;
			int xpos=cast(int)(plr.pos.x*cast(float)(minimap_rect.w)/cast(float)(MapXSize))+minimap_rect.x;
			int zpos=cast(int)(plr.pos.z*cast(float)(minimap_rect.h)/cast(float)(MapZSize))+minimap_rect.y;
			SDL_Rect prct;
			prct.w=4; prct.h=4;
			prct.x=xpos-prct.w/2; prct.y=zpos-prct.h/2;
			if(plr.player_id!=LocalPlayerID)
				Renderer_FillRect(&prct, &col);
			else
				Renderer_FillRect(&prct, &plrcol);
		}
		foreach(ref obj; Objects){
			if(!obj.visible || obj.minimap_img==255)
				continue;
			SDL_Rect orct;
			ubyte r, g, b;
			bool restore_color_mod=false;
			ubyte[3] colormod=[255, 255, 255];
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
			MenuElement_draw(&MenuElements[e_index]);
		}
	}
	if(List_Players){
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
		uint teamlist_w=cast(uint)(ScreenXSize/Teams.length); //cast for 64 bit systems
		for(uint t=0; t<Teams.length; t++){
			for(uint plist_index=0; plist_index<list_player_amount[t]; plist_index++){
				Player_t *plr=&Players[Player_List_Table[t][plist_index]];
				string plrentry=format("%s [#%s]", plr.name, plr.player_id);
				Render_Text_Line(t*teamlist_w, plist_index*FontHeight/16, Teams[t].icolor, plrentry, font_texture, FontWidth, FontHeight, LetterPadding);
			}
		}
	}
	if(!Render_Local_Player)
		Renderer_ShowInfo();
	Renderer_Finish2D();
	/*BlurAmount*=BlurAmountDecay;
	ShakeAmount*=ShakeAmountDecay;
	Set_Blur(BlurAmount+BaseBlurAmount);*/
}

KV6Sprite_t Get_Object_Sprite(uint obj_id){
	Object_t *obj=&Objects[obj_id];
	KV6Sprite_t spr;
	spr.xpos=obj.pos.x+obj.density.x; spr.ypos=obj.pos.y; spr.zpos=obj.pos.z;
	float xrot=obj.rot.x, yrot=obj.rot.y, zrot=obj.rot.z;
	spr.rti=yrot; spr.rhe=xrot; spr.rst=zrot;
	spr.xdensity=obj.density.x; spr.ydensity=obj.density.y; spr.zdensity=obj.density.z;
	spr.model=obj.model;
	if(obj.color){
		if(obj.color&0xff000000){
			spr.color_mod=obj.color;
		}
		spr.replace_black=obj.color;
	}
	return spr;
	
}

void Finish_Render(){
	//printf("fullness: %i\n",overlay_bind_fullness());
	/*SDL_SetRenderTarget(scrn_renderer, null);
	SDL_RenderCopy(scrn_renderer, scrn_texture, null, null);
	SDL_RenderPresent(scrn_renderer);*/
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

void Render_Object(uint obj_id){
	Object_t *obj=&Objects[obj_id];
	KV6Sprite_t spr=Get_Object_Sprite(obj_id);
	Renderer_DrawSprite(&spr);
}

void Render_Player(uint player_id){
	if(!Players[player_id].Spawned)
		return;
	KV6Sprite_t[] sprites=Get_Player_Sprites(player_id);
	sprites~=Get_Player_Attached_Sprites(player_id);
	foreach(ref spr; sprites){
		spr.replace_black=Teams[Players[player_id].team].icolor;
		Renderer_DrawSprite(&spr);
	}
}

void Render_Round_ZoomedIn(int scrx, int scry, int radius, float xzoom, float yzoom) {
		
}

KV6Sprite_t[] Get_Player_Sprites(uint player_id){
	Player_t *plr=&Players[player_id];
	Vector3_t rot=Players[player_id].dir.DirectionAsRotation;
	Vector3_t pos=Players[player_id].pos;
	if(player_id==LocalPlayerID)
		pos=CameraPos;
	KV6Sprite_t[] sprarr;
	KV6Sprite_t spr;
	foreach(ref model; plr.models){
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
		KV6Model_t *modelfile=Mod_Models[model.model_id];
		spr.xdensity=model.size.x/tofloat(modelfile.xsize);
		spr.ydensity=model.size.y/tofloat(modelfile.ysize); spr.zdensity=model.size.z/tofloat(modelfile.zsize);
		spr.model=modelfile;
		Vector3_t mpos=pos;
		Vector3_t offsetrot=mrot;
		offsetrot.x=0.0; offsetrot.z=0.0; offsetrot.y=-rot.y;
		Vector3_t offset=model.offset.rotate_raw(offsetrot);
		mpos-=offset;
		spr.xpos=mpos.x; spr.ypos=mpos.y; spr.zpos=mpos.z;
		sprarr~=spr;
		Sprite_Visible(&spr);
	}
	return sprarr;
}

auto Get_Player_Scope(uint player_id){
	struct Result_t{
		Vector3_t pos, rot;
	}
	Result_t result;
	KV6Sprite_t spr=Get_Player_Attached_Sprites(player_id)[0];
	result.rot=Vector3_t(spr.rhe, spr.rti, spr.rst);
	result.pos=Get_Absolute_Sprite_Coord(&spr, Vector3_t(spr.model.xsize, spr.model.ysize/2.0, spr.model.zsize/2.0));
	return result;
}

//Note: Sprite number zero has to be the weapon when scoping
KV6Sprite_t[] Get_Player_Attached_Sprites(uint player_id){
	if(!Players[player_id].item_types.length || !Players[player_id].Spawned)
		return [];
	if(ItemTypes[Players[player_id].items[Players[player_id].item].type].model_id==255)
		return[];
	Vector3_t rot=Players[player_id].dir.DirectionAsRotation;
	Vector3_t pos=Players[player_id].pos;
	KV6Sprite_t[] sprarr;
	KV6Sprite_t spr;
	Vector3_t item_offset;
	if(player_id==LocalPlayerID){
		pos=CameraPos;
	}
	item_offset=Vector3_t(.8, 0.0, .4);
	/*if(player_id==LocalPlayerID && false){
		item_offset=Vector3_t(2.0, -.4, .4);
		pos=CameraPos;
	}
	else{
		item_offset=Vector3_t(.8, 0.0, .4);
	}*/
	//I have no idea what I'm rotating around which axis or idk, actually I am only supposed to need one single rotation
	//But this works (makes the item appear in front of the player with an offset of item_offset, considering his rotation)
	spr.rst=rot.z*0.0; spr.rhe=rot.x; spr.rti=rot.y;
	Vector3_t itempos=pos+item_offset.rotate_raw(Vector3_t(0.0, 90.0-rot.x, 90.0)).rotate_raw(Vector3_t(0.0, 90.0-rot.y+180.0, 0.0));
	spr.xpos=itempos.x; spr.ypos=itempos.y; spr.zpos=itempos.z;
	spr.xdensity=.04; spr.ydensity=.04; spr.zdensity=.04;
	//BIG WIP
	uint current_tick=SDL_GetTicks();
	Item_t *item=&Players[player_id].items[Players[player_id].item];
	if(ItemTypes[item.type].is_weapon){
		if(!item.Reloading && item.amount1){
			if(current_tick-item.use_timer<ItemTypes[item.type].use_delay)
				spr.rhe-=(1.0-tofloat(current_tick-item.use_timer)/tofloat(ItemTypes[item.type].use_delay))*-item.last_recoil*0.0;
		}
	}
	else
	if(Players[player_id].left_click && !item.Reloading){
		if(current_tick-item.use_timer<ItemTypes[item.type].use_delay){
			spr.rhe+=tofloat(current_tick-item.use_timer)*45.0/tofloat(ItemTypes[item.type].use_delay)*(ItemTypes[item.type].is_weapon ? 1.0 : -1.0);
		}
	}
	if(ItemTypes[Players[player_id].items[Players[player_id].item].type].color_mod==true)
		spr.color_mod=(Players[player_id].color&0x00ffffff) | 0xff000000;
	spr.model=Mod_Models[ItemTypes[Players[player_id].items[Players[player_id].item].type].model_id];
	sprarr~=spr;
	return sprarr;
}

uint Count_KV6Blocks(KV6Model_t *model, uint dstx, uint dsty){
	uint index=0;
	for(uint x=0; x<dstx; x++)
		index+=model.xlength[x];
	uint xy=dstx*model.ysize;
	for(uint y=0; y<dsty; y++)
		index+=model.ylength[dstx][y];
	return index;
}

int SpriteHitScan(KV6Sprite_t *spr, Vector3_t pos, Vector3_t dir, out Vector3_t voxpos, out KV6Voxel_t *outvoxptr, float vox_size=1.0){
	uint x, z;
	KV6Voxel_t *sblk, blk, eblk;
	float rot_sx, rot_cx, rot_sy, rot_cy, rot_sz, rot_cz;
	rot_sx=sin((spr.rhe)*PI/180.0); rot_cx=cos((spr.rhe)*PI/180.0);
	rot_sy=sin(-(spr.rti+90.0)*PI/180.0); rot_cy=cos(-(spr.rti+90.0)*PI/180.0);
	rot_sz=sin(spr.rst*PI/180.0); rot_cz=cos(-spr.rst*PI/180.0);
	if(!Sprite_BoundHitCheck(spr, pos, dir))
		return 0;
	float voxxsize=fabs(spr.xdensity)*vox_size, voxysize=fabs(spr.ydensity)*vox_size, voxzsize=fabs(spr.zdensity)*vox_size;
	KV6Voxel_t *voxptr=null;
	float minvxdist=10e99;
	for(x=0; x<spr.model.xsize; ++x){
		for(z=0; z<spr.model.zsize; ++z){
			uint index=Count_KV6Blocks(spr.model, x, z);
			if(index>=spr.model.voxelcount)
				continue;
			sblk=&spr.model.voxels[index];
			eblk=&sblk[cast(uint)spr.model.ylength[x][z]];
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
				/*if(x==spr.model.xsize/2 && y==spr.model.ysize/2 && blk==sblk){
					writeflnlog("%s %s", lookpos, vpos);
				}*/
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
	outvoxptr=voxptr;
	if(voxptr)
		return 1;
	return 0;
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

void Create_Particles(Vector3_t pos, Vector3_t vel, float radius, float spread, uint amount, uint col, uint timer=0){
	uint old_size=cast(uint)Particles.length;
	uint sent_col_chance=(col>>24)&255;
	Particles.length+=amount;
	uint[] colors;
	pos.y+=.1;
	if(radius && sent_col_chance<255){
		for(int x=toint(pos.x-1.0); x<toint(pos.x+1.0); x++){
			for(int y=toint(pos.y-1.0); y<toint(pos.y+1.0); y++){
				for(int z=toint(pos.z-1.0); z<toint(pos.z+1.0); z++){
					if(!Valid_Coord(x, y, z))
						continue;
					if(Voxel_IsSolid(x, y, z) && Voxel_IsSurface(x, y, z)){
						colors~=Voxel_GetColor(x, y, z);
					}
				}
			}
		}
	}
	if(Voxel_IsWater(pos.x, pos.y, pos.z)){
		sent_col_chance=0;
		pos.y-=1.0;
	}
	pos.y-=.1;
	if(!colors.length)
		sent_col_chance=256;
	for(uint i=old_size; i<old_size+amount; i++){
		Vector3_t vspr=Vector3_t(spread*(uniform01()*2.0-1.0), spread*(uniform01()*2.0-1.0), spread*(uniform01()*2.0-1.0));
		Particles[i].pos=pos;
		Particles[i].vel=vel+vspr;
		if(uniform(0, 256)<sent_col_chance)
			Particles[i].col=col;
		else
			Particles[i].col=colors[uniform(0, colors.length)];
		Particles[i].timer=!timer ? uniform(300, 400) : timer;
	}
}

void Create_Smoke(Vector3_t pos, uint amount, uint col, float size){
	uint old_size=cast(uint)SmokeParticles.length;
	SmokeParticles.length+=amount;
	for(uint i=old_size; i<old_size+amount; i++){
		Vector3_t spos=pos+RandomVector()*size*.1;
		Vector3_t vel=RandomVector()*size*.01;
		SmokeParticles[i].Init(spos, vel, col, size*30.0);
	}
}

void Create_Explosion(Vector3_t pos, Vector3_t vel, float radius, float spread, uint amount, uint col, uint timer=0){
	static if(Enable_Object_Model_Modification){
		uint explosion_r=(col&255), explosion_g=(col>>8)&255, explosion_b=(col>>16)&255;
		foreach(uint obj_id, obj; Objects){
			if(!obj.modify_model)
				continue;
			//Crappy early out case check; need to fix this and consider pivots
			Vector3_t size=obj.density*Vector3_t(obj.model.xsize, obj.model.ysize, obj.model.zsize);
			Vector3_t dist=(obj.pos-pos).vecabs();
			if(dist.x>radius+size.x*2.0 || dist.y>radius+size.y*2.0 || dist.z>radius+size.z*2.0)
				continue;
			KV6Sprite_t spr=Get_Object_Sprite(obj_id);
			{
				float rot_sx=sin((spr.rhe)*PI/180.0), rot_cx=cos((spr.rhe)*PI/180.0);
				float rot_sy=sin(-(spr.rti+90.0)*PI/180.0), rot_cy=cos(-(spr.rti+90.0)*PI/180.0);
				float rot_sz=sin(spr.rst*PI/180.0), rot_cz=cos(-spr.rst*PI/180.0);
				for(uint blkx=0; blkx<spr.model.xsize; ++blkx){
					for(uint blkz=0; blkz<spr.model.zsize; ++blkz){
						uint index=Count_KV6Blocks(spr.model, blkx, blkz);
						if(index>=spr.model.voxelcount)
							continue;
						KV6Voxel_t *sblk=&spr.model.voxels[index];
						KV6Voxel_t *eblk=&sblk[cast(uint)spr.model.ylength[blkx][blkz]];
						for(KV6Voxel_t *blk=sblk; blk<eblk; ++blk){
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
	Create_Smoke(Vector3_t(pos.x, pos.y, pos.z), amount+1, 0xff808080, radius);
}


//Be careful: this is evil
Vector3_t Get_Absolute_Sprite_Coord(KV6Sprite_t *spr, Vector3_t coord){
	float rot_sx=sin((spr.rhe)*PI/180.0), rot_cx=cos((spr.rhe)*PI/180.0);
	float rot_sy=sin(-(spr.rti+90.0)*PI/180.0), rot_cy=cos(-(spr.rti+90.0)*PI/180.0);
	float rot_sz=sin(spr.rst*PI/180.0), rot_cz=cos(-spr.rst*PI/180.0);
	float fnx=(coord.x-spr.model.xpivot)*spr.xdensity;
	float fny=(coord.y-spr.model.ypivot)*spr.ydensity;
	float fnz=(coord.z-spr.model.zpivot)*spr.zdensity;
	float rot_y=fny, rot_z=fnz, rot_x=fnx;
	fny=rot_y*rot_cx - rot_z*rot_sx; fnz=rot_y*rot_sx + rot_z*rot_cx;
	rot_x=fnx; rot_z=fnz;
	fnz=rot_z*rot_cy - rot_x*rot_sy; fnx=rot_z*rot_sy + rot_x*rot_cy;
	rot_x=fnx; rot_y=fny;
	fnx=rot_x*rot_cz - rot_y*rot_sz; fny=rot_x*rot_sz + rot_y*rot_cz;
	fnx+=spr.xpos; fny+=spr.ypos; fnz+=spr.zpos;
	return Vector3_t(fnx, fny, fnz);
}

bool Sprite_Visible(KV6Sprite_t *spr){
	if(!Do_Sprite_Visibility_Checks)
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
		Vector3_t vpos=Vector3_t(fnx, fny, fnz);
		Vector3_t vdist=vpos-CameraPos;
		if(vdist.length>Visibility_Range)
			continue;
		auto result=RayCast(Vector3_t(fnx, fny, fnz), vdist.abs, vdist.length);
		if(!result.collside)
			return true;
		return true;
	}
	return false;
}

//Ok yeah, this code sux
bool Sprite_BoundHitCheck(KV6Sprite_t *spr, Vector3_t pos, Vector3_t dir){
	return true;
	float rot_sx=sin((spr.rhe)*PI/180.0), rot_cx=cos((spr.rhe)*PI/180.0);
	float rot_sy=sin(-(spr.rti+90.0)*PI/180.0), rot_cy=cos(-(spr.rti+90.0)*PI/180.0);
	float rot_sz=sin(spr.rst*PI/180.0), rot_cz=cos(-spr.rst*PI/180.0);
	float minx=10e99, maxx=-10e99, miny=10e99, maxy=-10e99, minz=10e99, maxz=-10e99;
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
		minx=min(fnx, minx); maxx=max(fnx, maxx); miny=min(fny, miny); maxy=max(fny, maxy); minz=min(fnz, minz); maxz=max(fnz, maxz);
	}
	Vector3_t start=Vector3_t(minx, miny, minz);
	Vector3_t end=Vector3_t(maxx, maxy, maxz);
	Vector3_t size=end-start;
	Vector3_t mpos=start+size/2.0;
	float dist=(mpos-pos).length;
	Vector3_t lookpos=pos+dir*dist;
	Vector3_t cdist=(lookpos-mpos).vecabs;
	size=size.vecabs();
	if(cdist.x<size.x && cdist.y<size.y && cdist.z<size.z)
		return true;
	return false;
}
