import derelict.sdl2.sdl;
import renderer;
import protocol;
import misc;
import world;
import ui;
import vector;

SDL_Window *scrn_window;
SDL_Renderer *scrn_renderer;
SDL_Texture *scrn_texture;

SDL_Texture *font_texture;
uint FontWidth, FontHeight;

uint Font_SpecialColor=0xff000000;

uint ScreenXSize=800, ScreenYSize=600;

Vector3_t CameraRot=Vector3_t(0.0, 0.0, 0.0);
float X_FOV=90.0, Y_FOV=90.0;

KV6Model_t*[] Mod_Models;
SDL_Texture*[] Mod_Pictures;

void Init_Gfx(){
	DerelictSDL2.load();
	scrn_window=SDL_CreateWindow("Voxel game client", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, ScreenXSize, ScreenYSize, 0);
	scrn_renderer=SDL_CreateRenderer(scrn_window, -1, 0);
	scrn_texture=SDL_CreateTexture(scrn_renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_TARGET, ScreenXSize, ScreenYSize);
	{
		SDL_Surface *font_surface=SDL_LoadBMP("./Ressources/Default/Font.bmp");
		if(font_surface){
			FontWidth=font_surface.w; FontHeight=font_surface.h;
			{
				SDL_Surface *ffont_surface=SDL_ConvertSurfaceFormat(font_surface, SDL_PIXELFORMAT_RGBA8888, 0);
				SDL_FreeSurface(font_surface);
				font_surface=ffont_surface;
			}
			SDL_SetColorKey(font_surface, SDL_TRUE, SDL_MapRGB(font_surface.format, 255, 0, 255));
			font_texture=SDL_CreateTextureFromSurface(scrn_renderer, font_surface);
			SDL_FreeSurface(font_surface);
		}
	}
	Init_Renderer();
}

void Prepare_Render(){
	
}

void Fill_Screen(SDL_Rect *rect, uint color){
	SDL_SetRenderTarget(scrn_renderer, scrn_texture);
	SDL_SetRenderDrawColor(scrn_renderer, color&255, (color>>8)&255, (color>>16)&255, (color>>24)&255);
	SDL_RenderFillRect(scrn_renderer, rect);
}

void Render_Text_Line(uint xpos, uint ypos, uint color, string line){
	SDL_Rect lrect, fontsrcrect;
	fontsrcrect.w=FontWidth/16; fontsrcrect.h=FontHeight/16;
	lrect.w=fontsrcrect.w; lrect.h=fontsrcrect.h;
	lrect.x=xpos; lrect.y=ypos;
	SDL_SetRenderTarget(scrn_renderer, scrn_texture);
	if(color!=Font_SpecialColor){
		SDL_SetTextureColorMod(font_texture, cast(ubyte)(color>>16), cast(ubyte)(color>>8), cast(ubyte)(color));
		SDL_SetTextureBlendMode(font_texture, SDL_BLENDMODE_BLEND);
	}
	else{
		//Add special effects here
		SDL_SetTextureColorMod(font_texture, 0, 0, 0);
		SDL_SetTextureBlendMode(font_texture, SDL_BLENDMODE_BLEND);
	}
	foreach(letter; line){
		fontsrcrect.x=(letter%16)*fontsrcrect.w; fontsrcrect.y=(letter/16)*fontsrcrect.h;
		SDL_RenderCopy(scrn_renderer, font_texture, &fontsrcrect, &lrect);
		lrect.x+=lrect.w;
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
		//Limiting to 100.0°, not 90.0°, so shooting horizontally will be easier
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
		Render_FinishRendering();
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
	SDL_Quit();
}

void Render_Player(uint player_id){
	if(Players[player_id].Model<0 || player_id==LocalPlayerID)
		return;
	KV6Sprite_t[] sprites=Get_Player_Sprites(player_id);
	foreach(ref spr; sprites)
		Render_Sprite(&spr);
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
	spr.rhe=rot.y; spr.rst=rot.x; spr.rti=rot.z;
	spr.xpos=Players[player_id].pos.x; spr.ypos=Players[player_id].pos.z; spr.zpos=Players[player_id].pos.y;
	spr.xdensity=.3; spr.ydensity=.3; spr.zdensity=-.3;
	spr.model=Mod_Models[Players[player_id].Model];
	return [spr];
}
