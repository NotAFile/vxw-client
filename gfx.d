import derelict.sdl2.sdl;
import std.math;
import std.algorithm;
import renderer;
import voxlap;
import protocol;
import misc;
import world;
import ui;
import vector;

SDL_Window *scrn_window;
SDL_Renderer *scrn_renderer;
SDL_Texture *scrn_texture;

SDL_Texture *font_texture;
SDL_Texture *borderless_font_texture;
uint FontWidth, FontHeight;

uint Font_SpecialColor=0xff000000;

uint ScreenXSize=800, ScreenYSize=600;

Vector3_t CameraRot=Vector3_t(0.0, 0.0, 0.0);
float X_FOV=90.0, Y_FOV=90.0;

KV6Model_t*[] Mod_Models;
SDL_Texture*[] Mod_Pictures;

uint Enable_Shade_Text=1;
uint LetterPadding=0;
immutable bool Dank_Text=false;

void Init_Gfx(){
	DerelictSDL2.load();
	scrn_window=SDL_CreateWindow("Voxel game client", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, ScreenXSize, ScreenYSize, 0);
	SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "1");
	scrn_renderer=SDL_CreateRenderer(scrn_window, -1, SDL_RENDERER_ACCELERATED);
	scrn_texture=SDL_CreateTexture(scrn_renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_TARGET, ScreenXSize, ScreenYSize);
	{
		SDL_Surface *font_surface=SDL_LoadBMP("./Ressources/Default/Font.bmp");
		if(font_surface){
			FontWidth=font_surface.w; FontHeight=font_surface.h;
			{
				SDL_Surface *ffont_surface=SDL_ConvertSurfaceFormat(font_surface, SDL_PIXELFORMAT_ARGB8888, 0);
				SDL_FreeSurface(font_surface);
				font_surface=ffont_surface;
			}
			SDL_SetColorKey(font_surface, SDL_TRUE, SDL_MapRGB(font_surface.format, 255, 0, 255));
			borderless_font_texture=SDL_CreateTextureFromSurface(scrn_renderer, font_surface);
			for(uint i=0; i<Enable_Shade_Text; i++){
				SDL_Surface *s=Shade_Text(font_surface);
				font_surface=s;
			}
			font_texture=SDL_CreateTextureFromSurface(scrn_renderer, font_surface);
			SDL_FreeSurface(font_surface);
		}
	}
	Init_Renderer();
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
	SDL_RenderFillRect(scrn_renderer, rect);
}

void Render_Text_Line(uint xpos, uint ypos, uint color, string line){
	SDL_Rect lrect, fontsrcrect;
	lrect.x=xpos; lrect.y=ypos;
	SDL_SetRenderTarget(scrn_renderer, scrn_texture);
	SDL_Texture *font;
	uint padding;
	if(color!=Font_SpecialColor){
		fontsrcrect.w=FontWidth/16; fontsrcrect.h=FontHeight/16;
		SDL_SetTextureColorMod(font_texture, cast(ubyte)(color>>16), cast(ubyte)(color>>8), cast(ubyte)(color));
		SDL_SetTextureBlendMode(font_texture, SDL_BLENDMODE_BLEND);
		font=font_texture;
		padding=LetterPadding*2;
	}
	else{
		fontsrcrect.w=FontWidth/16-LetterPadding*2; fontsrcrect.h=FontHeight/16-LetterPadding*2;
		SDL_SetTextureColorMod(borderless_font_texture, 255, 255, 255);
		SDL_SetTextureBlendMode(borderless_font_texture, SDL_BLENDMODE_MOD);
		font=borderless_font_texture;
		padding=0;
	}
	lrect.w=fontsrcrect.w; lrect.h=fontsrcrect.h;
	if(Dank_Text){
		lrect.w++; lrect.h++;
	}
	foreach(letter; line){
		fontsrcrect.x=(letter%16)*fontsrcrect.w;
		fontsrcrect.y=(letter/16)*fontsrcrect.h;
		SDL_RenderCopy(scrn_renderer, font, &fontsrcrect, &lrect);
		lrect.x+=lrect.w-padding;
	}
}

void Render_Screen(){
	Fill_Screen(null, SDL_MapRGB(scrn_surface.format, 0, 255, 255));
	if(Joined_Game()){
		CameraRot.x+=MouseMovedX*.5; CameraRot.y+=MouseMovedY*.5;
		//For some reason, this has to be rotated 90° right, TODO: investigate why and fix
		Vector3_t rt=CameraRot;
		rt.x-=90.0;
		Players[LocalPlayerID].dir=rt.RotationAsDirection;
		//Limiting to 100.0°, not 90.0°, so shooting vertically will be easier
		if(CameraRot.y<-100.0)
			CameraRot.y=-100.0;
		if(CameraRot.y>100.0)
			CameraRot.y=100.0;
		Vector3_t pos=Players[LocalPlayerID].pos;
		SetCamera(CameraRot.x, CameraRot.y, CameraRot.z, X_FOV, Y_FOV, pos.x, pos.y, pos.z);
		Update_Rotation_Data();
		Render_Voxels();
		for(uint p=0; p<Players.length; p++)
			Render_Player(p);
		*Pixel_Pointer(scrn_surface, scrn_surface.w/2, scrn_surface.h/2)=0xffffff;
		Render_FinishRendering();
	}
	SDL_SetRenderTarget(scrn_renderer, scrn_texture);
	foreach(ref e; MenuElements){
		if(e.picture_index==255)
			continue;
		SDL_Rect r;
		r.x=e.xpos; r.y=e.ypos; r.w=e.xsize; r.h=e.ysize;
		SDL_RenderCopy(scrn_renderer, Mod_Pictures[e.picture_index], null, &r);
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
	SDL_Quit();
}

void Render_Player(uint player_id){
	if(Players[player_id].Model<0 || player_id==LocalPlayerID)
		return;
	KV6Sprite_t[] sprites=Get_Player_Sprites(player_id);
	foreach(ref spr; sprites){
		Render_Sprite(&spr);
	}
}

/*Documentation Note:
 * If you want to change the way player KV6 sprites are positioned, 
 * rotated or resized when rendering, use this function.
 * It returns an array of all sprites that have to be rendered for this player.
 * Mod_Models (stupid name ikr, suggestions are welcome) contains all models
 * that the server requires.
*/
KV6Sprite_t[] Get_Player_Sprites(uint player_id){
	//Keep this line and assign this rotation at least for the head
	//(spr.rhe=rot.y, spr.rst=rot.x, spr.rti=rot.z)
	Vector3_t rot=Players[player_id].dir.DirectionAsRotation;
	//"Placeholder"; if you are going to change the way players look as described above,
	//feel free to throw out the following few lines and insert your
	//awesome-looking stuff
	KV6Sprite_t spr;
	spr.rst=rot.z; spr.rhe=rot.y+90.0; spr.rti=rot.x+180.0;
	spr.xpos=Players[player_id].pos.x; spr.ypos=Players[player_id].pos.y; spr.zpos=Players[player_id].pos.z;
	spr.xdensity=.3; spr.ydensity=.3; spr.zdensity=.3;
	spr.model=Mod_Models[Players[player_id].Model];
	return [spr];
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

int Vox_SpriteHitScan(KV6Sprite_t *spr, Vector3_t pos, Vector3_t dir, out Vector3_t voxpos, out KV6Voxel_t *voxptr){
	uint x, y;
	KV6Voxel_t *sblk, blk, eblk;
	float rot_sx, rot_cx, rot_sy, rot_cy, rot_sz, rot_cz;
	rot_sx=sin(spr.rhe*PI/180.0); rot_cx=cos(spr.rhe*PI/180.0);
	rot_sy=sin(spr.rti*PI/180.0); rot_cy=cos(spr.rti*PI/180.0);
	rot_sz=sin(spr.rst*PI/180.0); rot_cz=cos(spr.rst*PI/180.0);
	float voxxsize=fabs(spr.xdensity)*2.0, voxysize=fabs(spr.ydensity)*2.0, voxzsize=fabs(spr.zdensity)*2.0;
	for(x=0; x<spr.model.xsize; ++x){
		for(y=0; y<spr.model.ysize; ++y){
			uint index=Count_KV6Blocks(spr.model, x, y);
			if(index>=spr.model.voxelcount)
				continue;
			sblk=&spr.model.voxels[index];
			eblk=&sblk[cast(uint)spr.model.ylength[x][y]];
			for(blk=sblk; blk<eblk; ++blk){
				float fnx=(x-spr.model.xpivot)*spr.xdensity;
				float fny=(y-spr.model.ypivot)*spr.ydensity;
				float fnz=((spr.model.zsize-2-blk.zpos)-(spr.model.zsize-spr.model.zpivot))*spr.zdensity;
				float rot_y=fny, rot_z=fnz, rot_x;
				fny=rot_y*rot_cx - rot_z*rot_sx; fnz=rot_y*rot_sx + rot_z*rot_cx;
				rot_x=fnx; rot_z=fnz;
				fnz=rot_z*rot_cy - rot_x*rot_sy; fnx=rot_z*rot_sy + rot_x*rot_cy;
				rot_x=fnx; rot_y=fny;
				fnx=rot_x*rot_cz - rot_y*rot_sz; fny=rot_x*rot_sz + rot_y*rot_cz;
				fnx+=spr.xpos; fny+=spr.ypos; fnz+=spr.zpos;
				Vector3_t vpos=Vector3_t(fnx, fny, fnz);
				Vector3_t vdist=(vpos-pos).abs;
				float dist=(vpos-pos).length;
				Vector3_t lookpos=pos+dir*dist;
				Vector3_t cdist=(lookpos-vpos).vecabs;
				if(cdist.x<voxxsize && cdist.y<voxxsize && cdist.z<voxzsize){
					voxpos=vpos;
					voxptr=blk;
					return 1;
				}
			}
		}
	}
	return 0;
}
