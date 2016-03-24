import derelict.sdl2.sdl;
import misc;

SDL_Window *scrn_window;
SDL_Renderer *scrn_renderer;
SDL_Texture *scrn_texture;

SDL_Texture *font_texture;
uint FontWidth, FontHeight;

uint ScreenXSize=800, ScreenYSize=600;

void Init_Gfx(){
	DerelictSDL2.load();
	scrn_window=SDL_CreateWindow("Voxel game client", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, ScreenXSize, ScreenYSize, 0);
	scrn_renderer=SDL_CreateRenderer(scrn_window, -1, 0);
	scrn_texture=SDL_CreateTexture(scrn_renderer, SDL_PIXELFORMAT_RGBA8888, SDL_TEXTUREACCESS_TARGET, ScreenXSize, ScreenYSize);
	{
		SDL_Surface *font_surface=SDL_LoadBMP("./Ressources/Default/Font.bmp");
		if(font_surface){
			FontWidth=font_surface.w; FontHeight=font_surface.h;
			font_surface=SDL_ConvertSurfaceFormat(font_surface, SDL_PIXELFORMAT_RGBA8888, 0);
			font_texture=SDL_CreateTextureFromSurface(scrn_renderer, font_surface);
			SDL_FreeSurface(font_surface);
		}
	}
}

void Prepare_Render(){
	
}

void Fill_Screen(SDL_Rect *rect, uint color){
	SDL_SetRenderTarget(scrn_renderer, scrn_texture);
	SDL_SetRenderDrawColor(scrn_renderer, color&255, (color>>8)&255, (color>>16)&255, (color>>24)&255);
	SDL_RenderFillRect(scrn_renderer, rect);
}

void Render_Text_Line(uint xpos, uint ypos, string line){
	SDL_Rect lrect, fontsrcrect;
	fontsrcrect.w=FontWidth/16; fontsrcrect.h=FontHeight/16;
	lrect.w=fontsrcrect.w; lrect.h=fontsrcrect.h;
	lrect.x=xpos; lrect.y=ypos;
	SDL_SetRenderTarget(scrn_renderer, scrn_texture);
	foreach(letter; line){
		fontsrcrect.x=(letter%16)*fontsrcrect.w; fontsrcrect.y=(letter/16)*fontsrcrect.h;
		SDL_RenderCopy(scrn_renderer, font_texture, &fontsrcrect, &lrect);
		lrect.x+=lrect.w;
	}
}

void Finish_Render(){
	SDL_SetRenderTarget(scrn_renderer, null);
	SDL_RenderCopy(scrn_renderer, scrn_texture, null, null);
	SDL_RenderPresent(scrn_renderer);
}

void UnInit_Gfx(){
	SDL_DestroyTexture(scrn_texture);
	SDL_DestroyTexture(font_texture);
	SDL_Quit();
}
