import derelict.sdl2.sdl;
import renderer;
import protocol;
import misc;
import vector;

SDL_Window *scrn_window;
SDL_Renderer *scrn_renderer;
SDL_Texture *scrn_texture;

SDL_Texture *font_texture;
uint FontWidth, FontHeight;

uint Font_SpecialColor=0xff000000;

uint ScreenXSize=800, ScreenYSize=600;

Vector3_t CameraPos=Vector3_t(256.0, 32.0, 256.0), CameraRot=Vector3_t(0.0, 0.0, 0.0);
float X_FOV=90.0, Y_FOV=90.0;

void Init_Gfx(){
	DerelictSDL2.load();
	scrn_window=SDL_CreateWindow("Voxel game client", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, ScreenXSize, ScreenYSize, 0);
	scrn_renderer=SDL_CreateRenderer(scrn_window, -1, 0);
	scrn_texture=SDL_CreateTexture(scrn_renderer, SDL_PIXELFORMAT_ARGB8888, SDL_TEXTUREACCESS_TARGET, ScreenXSize, ScreenYSize);
	{
		SDL_Surface *font_surface=SDL_LoadBMP("./Ressources/Default/Font.bmp");
		SDL_SetColorKey(font_surface, SDL_TRUE, SDL_MapRGB(font_surface.format, 255, 0, 255));
		if(font_surface){
			FontWidth=font_surface.w; FontHeight=font_surface.h;
			font_surface=SDL_ConvertSurfaceFormat(font_surface, SDL_PIXELFORMAT_RGBA8888, 0);
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
	SetCamera(CameraRot.x, CameraRot.y, CameraRot.z, X_FOV, Y_FOV, CameraPos.x, CameraPos.y, CameraPos.z);
	if(JoinedGame)
		Render_Voxels();
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
