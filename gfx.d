import derelict.sdl2.sdl;
import derelict.sdl2.image;
import std.math;
import std.format;
import std.algorithm;
import std.random;
import renderer;
import voxlap;
import protocol;
import misc;
import world;
import ui;
import vector;
version(LDC){
	import ldc_stdlib;
}

SDL_Window *scrn_window;
SDL_Renderer *scrn_renderer;
SDL_Texture *scrn_texture;

SDL_Texture *font_texture;
SDL_Texture *borderless_font_texture;
uint FontWidth, FontHeight;

SDL_Texture *minimap_texture;
SDL_Surface *minimap_srfc;

MenuElement_t *ProtocolBuiltin_ScopePicture;

uint Font_SpecialColor=0xff000000;

uint ScreenXSize=800, ScreenYSize=600;

Vector3_t CameraRot=Vector3_t(0.0, 0.0, 0.0);
Vector3_t CameraPos=Vector3_t(0.0, 0.0, 0.0);
float X_FOV=90.0, Y_FOV=90.0;

KV6Model_t*[] Mod_Models;
SDL_Texture*[] Mod_Pictures;
uint[2][] Mod_Picture_Sizes;

uint Enable_Shade_Text=1;
uint LetterPadding=0;
immutable bool Dank_Text=false;

bool Software_Renderer=false;

Vector3_t TerrainOverview;

immutable bool Enable_Object_Model_Modification=true;

void Init_Gfx(){
	DerelictSDL2.load();
	DerelictSDL2Image.load();
	if(SDL_Init(SDL_INIT_EVERYTHING))
		writeflnlog("[WARNING] SDL2 didn't initialize properly: %s", SDL_GetError());
	if(IMG_Init(IMG_INIT_PNG)!=IMG_INIT_PNG)
		writeflnlog("[WARNING] IMG for PNG didn't initialize properly: %s", IMG_GetError());
	scrn_window=SDL_CreateWindow("Voxel game client", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, ScreenXSize, ScreenYSize, 0);
	SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "1");
	Software_Renderer=false;
	scrn_renderer=SDL_CreateRenderer(scrn_window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
	scrn_texture=SDL_CreateTexture(scrn_renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_TARGET, ScreenXSize, ScreenYSize);
	{
		SDL_Surface *font_surface=SDL_LoadBMP("./Ressources/Default/Font.bmp");
		if(font_surface){
			Set_Font(font_surface);
		}
	}
	Init_Renderer();
}

void Set_Font(SDL_Surface *ffnt){
	SDL_Surface *fnt=SDL_ConvertSurfaceFormat(ffnt, SDL_PIXELFORMAT_ARGB8888, 0);
	FontWidth=fnt.w; FontHeight=fnt.h;
	SDL_SetColorKey(fnt, SDL_TRUE, SDL_MapRGB(fnt.format, 255, 0, 255));
	if(borderless_font_texture)
		SDL_DestroyTexture(borderless_font_texture);
	borderless_font_texture=SDL_CreateTextureFromSurface(scrn_renderer, fnt);
	LetterPadding=0;
	for(uint i=0; i<Enable_Shade_Text; i++){
		SDL_Surface *s=Shade_Text(fnt);
		if(i)
			SDL_FreeSurface(fnt);
		fnt=s;
	}
	if(font_texture)
		SDL_DestroyTexture(font_texture);
	font_texture=SDL_CreateTextureFromSurface(scrn_renderer, fnt);
	SDL_FreeSurface(fnt);
}

void Set_MiniMap_Size(uint xsize, uint ysize){
	if(minimap_srfc){
		if(xsize==minimap_srfc.w && ysize==minimap_srfc.h)
			return;
	}
	if(minimap_srfc)
		SDL_FreeSurface(minimap_srfc);
	if(minimap_texture)
		SDL_DestroyTexture(minimap_texture);
	SDL_Surface *tmp=SDL_CreateRGBSurface(0, xsize, ysize, 32, 0, 0, 0, 0);
	minimap_srfc=SDL_ConvertSurfaceFormat(tmp, SDL_PIXELFORMAT_ARGB8888, 0);
	SDL_FreeSurface(tmp);
	minimap_texture=SDL_CreateTextureFromSurface(scrn_renderer, minimap_srfc);
}

void Update_MiniMap(){
	uint x, y, z;
	uint *pixel_ptr=cast(uint*)minimap_srfc.pixels;
	for(z=0; z<MapZSize; z++){
		for(x=0; x<MapXSize; x++){
			uint col=Voxel_GetColor(x, Voxel_FindFloorZ(x, 0, z), z);
			pixel_ptr[x]=col;
		}
		pixel_ptr=cast(uint*)((cast(ubyte*)pixel_ptr)+minimap_srfc.pitch);
	}
	SDL_UpdateTexture(minimap_texture, null, minimap_srfc.pixels, minimap_srfc.pitch);
}

uint *Pixel_Pointer(SDL_Surface *s, int x, int y){
	return cast(uint*)((cast(ubyte*)s.pixels)+(x<<2)+(y*s.pitch));
}

SDL_Surface *Shade_Text(SDL_Surface *srfc){
	LetterPadding++;
	uint LetterWidth=(srfc.w+LetterPadding*16*2)/16, LetterHeight=(srfc.h+LetterPadding*16*2)/16;
	SDL_Surface *dst=SDL_CreateRGBSurface(0, 16*LetterWidth, 16*LetterHeight, 32, 0, 0, 0, 0);
	//SDL_FillRect crashes here, so we're filling dst manually
	uint ColorKey;
	SDL_GetColorKey(srfc, &ColorKey);
	ColorKey&=0x00ffffff;
	for(uint y=0; y<dst.h; y++){
		for(uint x=0; x<dst.w; x++){
			*Pixel_Pointer(dst, x, y)=ColorKey;
		}
	}
	for(uint lx=0; lx<16; lx++){
		for(uint ly=0; ly<16; ly++){
			uint srcletterxp=lx*FontWidth/16, srcletteryp=ly*FontHeight/16;
			uint dstletterxp=lx*LetterWidth+LetterPadding, dstletteryp=ly*LetterHeight+LetterPadding;
			//TL;DR this could be an SDL_BlitSurface call
			for(uint y=0; y<FontHeight/16; y++){
				for(uint x=0; x<FontWidth/16; x++){
					*Pixel_Pointer(dst, dstletterxp+x, dstletteryp+y)=*Pixel_Pointer(srfc, srcletterxp+x, srcletteryp+y);
				}
			}
		}
	}
	SDL_FreeSurface(srfc);
	srfc=dst;
	dst=SDL_ConvertSurfaceFormat(srfc, srfc.format.format, 0);
	for(uint lx=0; lx<16; lx++){
		for(uint ly=0; ly<16; ly++){
			uint letterxp=lx*LetterWidth, letteryp=ly*LetterHeight;
			for(uint y=0; y<dst.h/16; y++){
				for(uint x=0; x<dst.w/16; x++){
					if(*Pixel_Pointer(srfc, letterxp+x, letteryp+y)!=ColorKey)
						continue;
					bool upc=y>0 ? (*Pixel_Pointer(srfc, letterxp+x, letteryp+y-1)!=ColorKey) : false;
					bool lfc=x>0 ? (*Pixel_Pointer(srfc, letterxp+x-1, letteryp+y)!=ColorKey) : false;
					bool rgc=x<(dst.w/16-1) ? (*Pixel_Pointer(srfc, letterxp+x+1, letteryp+y)!=ColorKey) : false;
					bool lwc=y<(dst.h/16-1) ? (*Pixel_Pointer(srfc, letterxp+x, letteryp+y+1)!=ColorKey) : false;
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

void Fill_Screen(SDL_Rect *rect, uint color){
	SDL_SetRenderTarget(scrn_renderer, scrn_texture);
	SDL_SetRenderDrawColor(scrn_renderer, color&255, (color>>8)&255, (color>>16)&255, (color>>24)&255);
	if(!Software_Renderer)
		SDL_RenderFillRect(scrn_renderer, rect);
}

void Render_Text_Line(uint xpos, uint ypos, uint color, string line, SDL_Texture *font, uint font_w, uint font_h, uint letter_padding, float 
	xsizeratio=1.0, float ysizeratio=1.0){
	SDL_Rect lrect, fontsrcrect;
	lrect.x=xpos; lrect.y=ypos;
	SDL_SetRenderTarget(scrn_renderer, scrn_texture);
	uint padding;
	ubyte old_r, old_g, old_b;
	SDL_BlendMode old_blend_mode;
	if(color!=Font_SpecialColor){
		fontsrcrect.w=font_w/16; fontsrcrect.h=font_h/16;
		SDL_GetTextureColorMod(font, &old_r, &old_g, &old_b);
		SDL_GetTextureBlendMode(font, &old_blend_mode);
		SDL_SetTextureColorMod(font, cast(ubyte)(color>>16), cast(ubyte)(color>>8), cast(ubyte)(color));
		SDL_SetTextureBlendMode(font, SDL_BLENDMODE_BLEND);
		padding=letter_padding*2;
	}
	else{
		fontsrcrect.w=font_w/16-letter_padding*2; fontsrcrect.h=font_h/16-letter_padding*2;
		SDL_GetTextureColorMod(borderless_font_texture, &old_r, &old_g, &old_b);
		SDL_GetTextureBlendMode(borderless_font_texture, &old_blend_mode);
		SDL_SetTextureColorMod(borderless_font_texture, 255, 255, 255);
		SDL_SetTextureBlendMode(borderless_font_texture, SDL_BLENDMODE_MOD);
		font=borderless_font_texture;
		padding=0;
	}
	lrect.w=toint(tofloat(fontsrcrect.w)*xsizeratio); lrect.h=toint(tofloat(fontsrcrect.h)*ysizeratio);
	if(Dank_Text){
		lrect.w++; lrect.h++;
	}
	foreach(letter; line){
		fontsrcrect.x=(letter%16)*fontsrcrect.w;
		fontsrcrect.y=(letter/16)*fontsrcrect.h;
		SDL_RenderCopy(scrn_renderer, font, &fontsrcrect, &lrect);
		lrect.x+=lrect.w-padding*xsizeratio;
	}
	SDL_SetTextureColorMod(font, old_r, old_g, old_b);
	SDL_SetTextureBlendMode(font, old_blend_mode);
}

uint[][] Player_List_Table;

void Render_World(SDL_Surface *dst_srfc, bool Render_Cursor){
	Render_Voxels();
	for(uint p=0; p<Players.length; p++)
		Render_Player(p);
	foreach(ref bdmg; BlockDamage){
		foreach(ref prtcl; bdmg.particles){
			float dst; int scrx, scry;
			if(!Project2D(prtcl.x, prtcl.y, prtcl.z, &dst, scrx, scry))
				continue;
			if(dst<0.0)
				continue;
			/*Vector3_t dist=Vector3_t(prtcl.x, prtcl.y, prtcl.z)-pos;
			dist.x=tofloat(toint(dist.x));
			dist.y=tofloat(toint(dist.y));
			dist.z=tofloat(toint(dist.z));
			dst=dist.length;*/
			Render_Rectangle(scrx, scry, cast(int)(20.0/(dst+1.0))+1, cast(int)(20.0/(dst+1.0))+1, prtcl.col, dst);
		}
	}
	foreach(ref dmgobj_id; DamagedObjects){
		Object_t *dmgobj=&Objects[dmgobj_id];
		foreach(ref prtcl; dmgobj.particles){
			float dst; int scrx, scry;
			if(!Project2D(prtcl.x, prtcl.y, prtcl.z, &dst, scrx, scry))
				continue;
			if(dst<0.0)
				continue;
			Render_Rectangle(scrx, scry, cast(int)(20.0/(dst+1.0))+1, cast(int)(20.0/(dst+1.0))+1, prtcl.col, dst);
		}
	}
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
		float dst;
		int scrx, scry;
		if(!Project2D(p.pos.x, p.pos.y, p.pos.z, &dst, scrx, scry))
			continue;
		if(dst<0.0)
			continue;
		Render_Rectangle(scrx, scry, cast(int)(20.0/(dst+1.0))+1, cast(int)(20.0/(dst+1.0))+1, p.col, tofloat(toint(dst)));
	}
	float particle_size=BlockBreakParticleSize*dst_srfc.w;
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
		float dst;
		int scrx, scry;
		if(!Project2D(p.pos.x, p.pos.y, p.pos.z, &dst, scrx, scry))
			continue;
		if(dst<0.0)
			continue;
		Render_Rectangle(scrx, scry, cast(int)(50.0/(dst+1.0))+1, cast(int)(50.0/(dst+1.0))+1, p.col, tofloat(toint(dst)));
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
	if(Render_Cursor)
		*Pixel_Pointer(dst_srfc, dst_srfc.w/2, dst_srfc.h/2)=0xffffff^*Pixel_Pointer(dst_srfc, dst_srfc.w/2, dst_srfc.h/2);
}


void Render_Screen(){
	//Fill_Screen(null, SDL_MapRGB(scrn_surface.format, 0, 255, 255));
	bool Render_Local_Player=false;
	if(Joined_Game()){
		Render_Local_Player|=Players[LocalPlayerID].Spawned && Players[LocalPlayerID].InGame;
	}
	if(LoadedCompleteMap){
		Set_Frame_Buffer(scrn_surface);
		Vector3_t pos;
		if(Render_Local_Player || JoinedGame){
			if(!Menu_Mode)
				CameraRot.x+=MouseMovedX*.5; CameraRot.y+=MouseMovedY*.5;
			Vector3_t rt;
			rt.x=CameraRot.y;
			rt.y=CameraRot.x;
			rt.z=CameraRot.z;
			if(Render_Local_Player)
				Players[LocalPlayerID].dir=rt.RotationAsDirection;
			//Limiting to 100.0°, not 90.0°, so shooting vertically will be easier
			if(CameraRot.y<-100.0)
				CameraRot.y=-100.0;
			if(CameraRot.y>100.0)
				CameraRot.y=100.0;
			pos=Players[LocalPlayerID].pos;
			CameraPos=pos;
			SetCamera(CameraRot.x, CameraRot.y, CameraRot.z, X_FOV, Y_FOV, pos.x, pos.y, pos.z);
		}
		else{
			CameraRot.x+=MouseMovedX*.7; CameraRot.y+=MouseMovedY*.5;
			TerrainOverview.y+=uniform01()*.5;
			TerrainOverview.x+=cos(TerrainOverview.y*PI/180.0)*.3;
			TerrainOverview.z+=sin(TerrainOverview.y*PI/180.0)*.3;
			pos=TerrainOverview;
			pos.y=-15.0;
			Vector3_t crot=CameraRot*.05+Vector3_t(0.0, 45.0, 0.0);
			CameraPos=pos;
			SetCamera(crot.x, crot.y, crot.z, X_FOV, Y_FOV, pos.x, pos.y, pos.z);
		}
		if(Render_Local_Player)
			Update_Rotation_Data();
		Prepare_Render();
		Render_World(scrn_surface, false);
		{
			if(Render_Local_Player){
				if(Players[LocalPlayerID].item_types.length)
					if(ItemTypes[Players[LocalPlayerID].item_types[Players[LocalPlayerID].item]].is_weapon
					&& !Players[LocalPlayerID].items[Players[LocalPlayerID].item].Reloading&& MouseRightClick){
						if(ProtocolBuiltin_ScopePicture)
							Render_Round_ZoomedIn(400, 300, Mod_Picture_Sizes[ProtocolBuiltin_ScopePicture.picture_index][0]/2, 1.1, 1.1);
					}
						
			}
		}
		Render_FinishRendering();
	}
	SDL_SetRenderTarget(scrn_renderer, scrn_texture);
	{
		SDL_Rect r;
		foreach(ref elements; Z_MenuElements[1..$]){
			foreach(e_index; elements){
				MenuElement_t *e=&MenuElements[e_index];
				if(e.picture_index==255)
					continue;
				r.x=e.xpos; r.y=e.ypos; r.w=e.xsize; r.h=e.ysize;
				if(e.transparency<255)
					SDL_SetTextureAlphaMod(Mod_Pictures[e.picture_index], e.transparency);
				SDL_RenderCopy(scrn_renderer, Mod_Pictures[e.picture_index], null, &r);
				if(e.transparency<255)
					SDL_SetTextureAlphaMod(Mod_Pictures[e.picture_index], 255);
			}
		}
	}
	Render_HUD();
	immutable ubyte minimap_alpha=210;
	if(Render_MiniMap && Joined_Game()){
		SDL_Rect minimap_rect;
		Team_t *team=&Teams[Players[LocalPlayerID].team];
		minimap_rect.x=0; minimap_rect.y=0; minimap_rect.w=scrn_surface.w; minimap_rect.h=scrn_surface.h;
		SDL_SetTextureAlphaMod(minimap_texture, minimap_alpha);
		SDL_SetTextureBlendMode(minimap_texture, SDL_BLENDMODE_BLEND);
		SDL_RenderCopy(scrn_renderer, minimap_texture, null, null);
		SDL_SetRenderDrawColor(scrn_renderer, team.color[2], team.color[1], team.color[0], 255);
		foreach(ref plr; Players){
			if(!plr.Spawned || !plr.InGame || plr.team!=Players[LocalPlayerID].team)
				continue;
			int xpos=cast(int)(plr.pos.x*cast(float)(minimap_rect.w)/cast(float)(MapXSize))+minimap_rect.x;
			int zpos=cast(int)(plr.pos.z*cast(float)(minimap_rect.h)/cast(float)(MapZSize))+minimap_rect.y;
			SDL_Rect prct;
			prct.w=4; prct.h=4;
			prct.x=xpos-prct.w/2; prct.y=zpos-prct.h/2;
			SDL_RenderFillRect(scrn_renderer, &prct);
		}
		foreach(ref obj; Objects){
			if(!obj.visible || obj.minimap_img==255)
				continue;
			SDL_Rect orct;
			orct.w=Mod_Picture_Sizes[obj.minimap_img][0]*minimap_rect.w/MapXSize;
			orct.h=Mod_Picture_Sizes[obj.minimap_img][1]*minimap_rect.h/MapZSize;
			int xpos=cast(int)(obj.pos.x*cast(float)(minimap_rect.w)/cast(float)(MapXSize))+minimap_rect.x;
			int zpos=cast(int)(obj.pos.z*cast(float)(minimap_rect.h)/cast(float)(MapZSize))+minimap_rect.y;
			orct.x=xpos-orct.w/2; orct.y=zpos-orct.h/2;
			SDL_RenderCopy(scrn_renderer, Mod_Pictures[obj.minimap_img], null, &orct);
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
			list_player_amount[p.team]++;
			Player_List_Table[p.team][list_player_amount[p.team]-1]=p.player_id;
		}
		uint teamlist_w=scrn_surface.w/Teams.length;
		for(uint t=0; t<Teams.length; t++){
			for(uint plist_index=0; plist_index<list_player_amount[t]; plist_index++){
				Player_t *plr=&Players[Player_List_Table[t][plist_index]];
				string plrentry=format("%s [#%s]", plr.name, plr.player_id);
				Render_Text_Line(t*teamlist_w, plist_index*FontHeight/16, Teams[t].icolor, plrentry, font_texture, FontWidth, FontHeight, LetterPadding);
			}
		}
	}
}

KV6Sprite_t Get_Object_Sprite(uint obj_id){
	Object_t *obj=&Objects[obj_id];
	KV6Sprite_t spr;
	spr.xpos=obj.pos.x+obj.density.x; spr.ypos=obj.pos.y; spr.zpos=obj.pos.z;
	float xrot=obj.rot.x, yrot=obj.rot.y, zrot=obj.rot.z;
	spr.rti=yrot; spr.rhe=xrot; spr.rst=zrot;
	spr.xdensity=obj.density.x; spr.ydensity=obj.density.y; spr.zdensity=obj.density.z;
	spr.model=obj.model;
	return spr;
	
}

void Render_Object(uint obj_id){
	Object_t *obj=&Objects[obj_id];
	KV6Sprite_t spr=Get_Object_Sprite(obj_id);
	Render_Sprite(&spr);
	if(false){
		foreach(uint vi, ref model_vertex; obj.Vertices){
			float dst;
			int scrx, scry;
			Vector3_t worldvertex=model_vertex.rotate_raw(obj.rot)+obj.pos;
			if(!Project2D(worldvertex.x, worldvertex.y, worldvertex.z, &dst, scrx, scry))
				continue;
			if(dst<0.0)
				continue;
			int rect_w=cast(int)(50.0/(dst+1.0))+1, rect_h=rect_w;
			scrx-=rect_w/2; scry-=rect_h/2;
			if(obj.Vertex_Collisions[vi][0] || obj.Vertex_Collisions[vi][1] || obj.Vertex_Collisions[vi][2])
				Render_Rectangle(scrx, scry, rect_w, rect_h, 0x00ff8000, 0.0);
			else
				Render_Rectangle(scrx, scry, rect_w, rect_h, 0x00ffff00, 0.0);
		}
	}
}

void Finish_Render(){
	SDL_SetRenderTarget(scrn_renderer, null);
	SDL_RenderCopy(scrn_renderer, scrn_texture, null, null);
	SDL_RenderPresent(scrn_renderer);
}

void UnInit_Gfx(){
	UnInit_Renderer();
	SDL_DestroyTexture(scrn_texture);
	SDL_DestroyTexture(font_texture);
	SDL_DestroyTexture(borderless_font_texture);
	IMG_Quit();
	SDL_Quit();
}

void Render_Player(uint player_id){
	if(!Players[player_id].Spawned)
		return;
	KV6Sprite_t[] sprites=Get_Player_Sprites(player_id);
	sprites~=Get_Player_Attached_Sprites(player_id);
	foreach(ref spr; sprites){
		spr.replace_black=Teams[Players[player_id].team].icolor;
		Render_Sprite(&spr);
	}
}

SDL_Surface* ScopeSurface;
void Render_Round_ZoomedIn(int scrx, int scry, int radius, float xzoom, float yzoom){
	{
		bool new_srfc=false;
		if(!ScopeSurface)
			new_srfc=true;
		else
			new_srfc=ScopeSurface.w!=radius*2 || ScopeSurface.h!=radius*2;
		if(new_srfc){
			if(ScopeSurface){
				SDL_FreeSurface(ScopeSurface);
				ScopeSurface=null;
			}
			ScopeSurface=SDL_CreateRGBSurface(0, radius*2, radius*2, 32, 0, 0, 0, 0);
		}
	}
	Set_Frame_Buffer(ScopeSurface);
	SetCamera(CameraRot.x, CameraRot.y, CameraRot.z, X_FOV/xzoom/tofloat(scrn_surface.w/radius), Y_FOV/yzoom/tofloat(scrn_surface.h/radius), CameraPos.x, CameraPos.y, CameraPos.z);
	Render_World(ScopeSurface, true);
	int pow_radius=radius*radius;
	SDL_Rect src, dst;
	src.h=dst.h=1;
	src.y=0;
	for(int y=scry-radius; y<scry+radius; y++){
		int pow_y=(scry-y)*(scry-y);
		src.w=dst.w=(cast(uint)sqrt(tofloat(pow_radius-pow_y)))<<1;
		dst.y=y; src.y=y-(scry-radius);
		src.x=radius-(src.w>>1);
		dst.x=src.x+scrx-radius;
		SDL_BlitSurface(ScopeSurface, &src, scrn_surface, &dst);
	}
	//SDL_BlitSurface(ScopeSurface, null, scrn_surface, &screen_rect);
}

//Other note: this system is only WIP and will be replaced with server-side stuff someday

/*Documentation Note:
 * If you want to change the way player KV6 sprites are positioned, 
 * rotated or resized when rendering, use this function and Get_Player_Attached_Sprites.
 * They return an array of all sprites that have to be rendered for this player.
 * Mod_Models (stupid name ikr, suggestions are welcome) contains all models
 * that the server tells the client to load.
*/
//Get_Player_Sprites returns sprites that are rendered AND checked for hits when shooting
//Use it for any body parts
//Get_Player_Attached_Sprites returns sprites that are ONLY rendered and NOT checked for hits
//Use it for things like weapons/items and miscellaneous attachments
/*KV6Sprite_t[] Get_Player_Sprites(uint player_id){
	//Keep this line and assign this rotation at least for the head
	//(spr.rhe=rot.y, spr.rst=rot.x, spr.rti=rot.z)
	Vector3_t rot=Players[player_id].dir.DirectionAsRotation;
	Vector3_t pos=Players[player_id].pos;
	//"Placeholder"; if you are going to change the way players look as described above,
	//feel free to throw out the following few lines and insert your
	//awesome-looking stuff
	KV6Sprite_t[] sprarr;
	KV6Sprite_t spr;
	if(player_id!=LocalPlayerID){
		spr.rst=rot.z; spr.rti=rot.y; spr.rhe=rot.x;
		spr.xpos=pos.x; spr.ypos=pos.y; spr.zpos=pos.z;
		spr.xdensity=.2; spr.ydensity=.2; spr.zdensity=.2;
		if(Players[player_id].Model!=-1){
			spr.model=Mod_Models[Players[player_id].Model];
			sprarr~=spr;
		}
	}
	float player_offset=tofloat(player_id==LocalPlayerID)*1.0;
	//offset coords: forwards, y-wards, sidewards
	Vector3_t arm_offset=Vector3_t(player_offset, -.4, .4);
	spr.rst=rot.z; spr.rhe=rot.x; spr.rti=rot.y;
	Vector3_t armpos=pos+arm_offset.rotate_raw(Vector3_t(0.0, 90.0-rot.x, 90.0)).rotate_raw(Vector3_t(0.0, 270.0-rot.y, 0.0));
	spr.xpos=armpos.x; spr.ypos=armpos.y; spr.zpos=armpos.z;
	spr.xdensity=.05; spr.ydensity=.05; spr.zdensity=.05;
	spr.model=Mod_Models[Players[player_id].Arm_Model];
	sprarr~=spr;
	return sprarr;
}*/

KV6Sprite_t[] Get_Player_Sprites(uint player_id){
	Player_t *plr=&Players[player_id];
	Vector3_t rot=Players[player_id].dir.DirectionAsRotation;
	Vector3_t pos=Players[player_id].pos;
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
		KV6Model_t *modelfile=Mod_Models[model.model_id];
		spr.xdensity=model.size.x/tofloat(modelfile.xsize);
		spr.ydensity=model.size.y/tofloat(modelfile.ysize); spr.zdensity=model.size.z/tofloat(modelfile.zsize);
		spr.model=modelfile;
		Vector3_t mpos=pos;
		Vector3_t offsetrot=mrot;
		offsetrot.x=0.0; offsetrot.z=0.0; offsetrot.y=rot.y;
		Vector3_t offset=model.offset.rotate_raw(offsetrot);
		mpos-=offset;
		spr.xpos=mpos.x; spr.ypos=mpos.y; spr.zpos=mpos.z;
		sprarr~=spr;
		Sprite_Visible(&spr);
	}
	return sprarr;
}

KV6Sprite_t[] Get_Player_Attached_Sprites(uint player_id){
	if(!Players[player_id].item_types.length || !Players[player_id].Spawned)
		return [];
	Vector3_t rot=Players[player_id].dir.DirectionAsRotation;
	Vector3_t pos=Players[player_id].pos;
	KV6Sprite_t[] sprarr;
	KV6Sprite_t spr;
	Vector3_t item_offset;
	if(player_id==LocalPlayerID)
		item_offset=Vector3_t(2.0, -.4, .4);
	else
		item_offset=Vector3_t(.8, 0.0, .4);
	//I have no idea what I'm rotating around which axis or idk, actually I am only supposed to need one single rotation
	//But this works (makes the item appear in front of the player with an offset of item_offset, considering his rotation)
	spr.rst=rot.z; spr.rhe=rot.x; spr.rti=rot.y;
	Vector3_t itempos=pos+item_offset.rotate_raw(Vector3_t(0.0, 90.0-rot.x, 90.0)).rotate_raw(Vector3_t(0.0, 90.0-rot.y+180.0, 0.0));
	spr.xpos=itempos.x; spr.ypos=itempos.y; spr.zpos=itempos.z;
	spr.xdensity=.04; spr.ydensity=.04; spr.zdensity=.04;
	//BIG WIP
	uint current_tick=SDL_GetTicks();
	Item_t *item=&Players[player_id].items[Players[player_id].item];
	if(ItemTypes[item.type].is_weapon){
		if(!item.Reloading && item.amount1){
			if(current_tick-item.use_timer<ItemTypes[item.type].use_delay)
				spr.rhe-=(1.0-tofloat(current_tick-item.use_timer)/tofloat(ItemTypes[item.type].use_delay))*-item.last_recoil*7.5;
		}
	}
	else
	if(Players[player_id].left_click && !item.Reloading){
		if(current_tick-item.use_timer<ItemTypes[item.type].use_delay){
			spr.rhe+=tofloat(current_tick-item.use_timer)*45.0/tofloat(ItemTypes[item.type].use_delay);
		}
	}
	if(Players[player_id].item==1)
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

int SpriteHitScan(KV6Sprite_t *spr, Vector3_t pos, Vector3_t dir, out Vector3_t voxpos, out KV6Voxel_t *outvoxptr){
	uint x, z;
	KV6Voxel_t *sblk, blk, eblk;
	float rot_sx, rot_cx, rot_sy, rot_cy, rot_sz, rot_cz;
	rot_sx=sin((spr.rhe)*PI/180.0); rot_cx=cos((spr.rhe)*PI/180.0);
	rot_sy=sin(-(spr.rti+90.0)*PI/180.0); rot_cy=cos(-(spr.rti+90.0)*PI/180.0);
	rot_sz=sin(spr.rst*PI/180.0); rot_cz=cos(-spr.rst*PI/180.0);
	if(!Sprite_BoundHitCheck(spr, pos, dir))
		return 0;
	float voxxsize=fabs(spr.xdensity), voxysize=fabs(spr.ydensity), voxzsize=fabs(spr.zdensity);
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

void Create_Particles(Vector3_t pos, Vector3_t vel, float radius, float spread, uint amount, uint col, uint timer=0){
	uint old_size=Particles.length;
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
}

bool Sprite_Visible(KV6Sprite_t *spr){
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
		float renddist=Vox_Project2D(fnx, fnz, fny, &screenx, &screeny);
		if(renddist<0.0)
			continue;
		if(screenx<0 || screeny<0)
			continue;
		if(renddist>Visibility_Range)
			continue;
		//Only after I fixed raycasting code
		Vector3_t vpos=Vector3_t(fnx, fny, fnz);
		Vector3_t vdist=vpos-CameraPos;
		if(vdist.length>Visibility_Range)
			continue;
		auto result=RayCast(Vector3_t(fnx, fny, fnz), vdist.abs, vdist.length);
		if(!result.collside)
			return true;
		return true;
		//Vox_DrawRect2D(screenx, screeny, 10, 10, 0xffffffff, renddist);
	}
	return false;
}

bool Sprite_BoundHitCheck(KV6Sprite_t *spr, Vector3_t pos, Vector3_t dir){
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
