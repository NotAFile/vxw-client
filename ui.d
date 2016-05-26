import derelict.sdl2.sdl;
import std.string;
import std.algorithm;
import gfx;
import misc;
import network;
import protocol;
import world;
import vector;
import renderer;
import packettypes;
version(LDC){
	import ldc_stdlib;
}

uint CurrentChatCursor;
bool TypingChat=false;

bool QuitGame=false;

uint ChatBox_X=0, ChatBox_Y=0;

ubyte* KeyState;

bool List_Players=false;

bool Menu_Mode=false;
bool Lock_Mouse=true;
int MouseXPos, MouseYPos;
int MouseMovedX, MouseMovedY;
bool MouseLeftClick, MouseRightClick;

immutable float MouseAccuracyConst=.75;

bool Render_MiniMap;

string LastSentLine="";

bool Changed_Palette_Color=false;
SDL_Surface *Palette_V_Colors, Palette_H_Colors;

void ConvertScreenCoords(in float uxpos, in float uypos, out int lxpos, out int lypos){
	float scrnw=cast(float)scrn_surface.w, scrnh=cast(float)scrn_surface.h;
	lxpos=cast(int)(uxpos*scrnw); lypos=cast(int)(uypos*scrnh);
}

struct MenuElement_t{
	ubyte index;
	ubyte picture_index;
	ubyte zpos;
	ubyte transparency;
	int xpos, ypos;
	int xsize, ysize;
	//Maybe optimize menu elements to get deleted when their picture index is 255
	void set(ubyte initindex, ubyte picindex, ubyte zval, float sxpos, float sypos, float sxsize, float sysize, ubyte inittransparency){
		index=initindex;
		picture_index=picindex;
		ConvertScreenCoords(sxpos, sypos, xpos, ypos);
		ConvertScreenCoords(sxsize, sysize, xsize, ysize);
		if(zpos!=zval){
			int arrind=countUntil(Z_MenuElements[zpos], index);
			if(arrind>=0)
				Z_MenuElements[zpos]=Z_MenuElements[zpos].remove(arrind);
			Z_MenuElements[zval]~=index;
		}
		zpos=zval;
		transparency=inittransparency;
	}
}

uint[][255] Z_MenuElements;

MenuElement_t[] MenuElements;

MenuElement_t *AmmoCounterBG;
MenuElement_t *AmmoCounterBullet;

MenuElement_t *ProtocolBuiltin_PaletteHFG;
MenuElement_t *ProtocolBuiltin_PaletteVFG;

struct TextBox_t{
	ubyte font_index;
	int xpos, ypos;
	int xsize, ysize;
	float xsizeratio, ysizeratio;
	bool wrap_lines;
	ubyte move_lines;
	string[] lines;
	uint[] colors;
	void set(ubyte picindex, float sxpos, float sypos, float sxsize, float sysize, float sxsizeratio, float sysizeratio, ubyte flags){
		font_index=picindex;
		ConvertScreenCoords(sxpos, sypos, xpos, ypos);
		ConvertScreenCoords(sxsize, sysize, xsize, ysize);
		wrap_lines=cast(bool)(flags&TEXTBOX_FLAG_WRAP);
		move_lines=(flags&TEXTBOX_FLAG_MOVELINESDOWN) | (flags&TEXTBOX_FLAG_MOVELINESUP);
		xsizeratio=sxsizeratio; ysizeratio=sysizeratio;
	}
	void set_line(ubyte line, uint color, string text){
		if(line>=lines.length){
			lines.length=line+1;
			colors.length=line+1;
		}
		if(move_lines&TEXTBOX_FLAG_MOVELINESDOWN){
			scroll_down(0, line);
		}
		else
		if(move_lines&TEXTBOX_FLAG_MOVELINESUP){
			scroll_up(line, cast(ubyte)lines.length);
		}
		lines[line]=text;
		colors[line]=color;
	}
	void scroll_up(ubyte start, ubyte end){
		for(uint i=start; i<end-1; i++){
			lines[i]=lines[i+1]; colors[i]=colors[i+1];
		}
	}
	void scroll_down(ubyte start, ubyte end){
		for(uint i=end-1; i>start; i++){
			lines[i]=lines[i-1]; colors[i]=colors[i-1];
		}
	}
}

TextBox_t[] TextBoxes;

void Init_UI(){
	ChatText.length=8; ChatColors.length=8;
	KeyState=SDL_GetKeyboardState(null);
	Set_Menu_Mode(false);
}

void UnInit_UI(){
}

void Set_Menu_Mode(bool mode){
	Lock_Mouse=!mode;
	SDL_SetRelativeMouseMode(Lock_Mouse ? SDL_TRUE : SDL_FALSE);
	Menu_Mode=mode;
}

uint PrevKeyPresses=0;

void Check_Input(){
	SDL_Event event;
	MouseMovedX=0; MouseMovedY=0;
	bool Scrolling_Colors=false;
	while(SDL_PollEvent(&event)){
		switch(event.type){
			case SDL_QUIT:{
				QuitGame=true;
				break;
			}
			case SDL_KEYDOWN:{
				byte number_key_pressed=0;
				switch(event.key.keysym.sym){
					case SDLK_RETURN:{
						if(Joined_Game()){
							TypingChat=!TypingChat;
							if(TypingChat){
								SDL_StartTextInput();
								CurrentChatLine="";
								CurrentChatCursor=0;
							}
							else{
								SDL_StopTextInput();
								if(CurrentChatLine.length){
									LastSentLine=CurrentChatLine;
									Send_Chat_Packet(CurrentChatLine);
								}
								CurrentChatLine="";
								CurrentChatCursor=0;
							}
						}
					}
					case SDLK_BACKSPACE:{
						if(TypingChat && CurrentChatCursor){
							CurrentChatLine=CurrentChatLine[0..CurrentChatCursor-1]~CurrentChatLine[CurrentChatCursor..$];
							CurrentChatCursor--;
						}
						break;
					}
					case SDLK_r:{
						if(Joined_Game && !TypingChat){
							if(true){
								ItemReloadPacketLayout packet;
								Send_Packet(ItemReloadPacketID, packet);
								Players[LocalPlayerID].items[Players[LocalPlayerID].item].Reloading=true;
							}
						}
						break;
					}
					case SDLK_1:number_key_pressed=1; break;
					case SDLK_2:number_key_pressed=2; break;
					case SDLK_3:number_key_pressed=3; break;
					case SDLK_4:number_key_pressed=4; break;
					case SDLK_5:number_key_pressed=5; break;
					case SDLK_6:number_key_pressed=6; break;
					case SDLK_7:number_key_pressed=7; break;
					case SDLK_8:number_key_pressed=8; break;
					case SDLK_9:number_key_pressed=9; break;
					case SDLK_0:number_key_pressed=10; break;
					case SDLK_F10:{
						Lock_Mouse=!Lock_Mouse;
						if(Menu_Mode)
							Lock_Mouse=false;
						SDL_SetRelativeMouseMode(Lock_Mouse ? SDL_TRUE : SDL_FALSE);
						break;
					}
					case SDLK_LEFT:{
						if(TypingChat && CurrentChatCursor){
							CurrentChatCursor--;
						}
						break;
					}
					case SDLK_RIGHT:{
						if(TypingChat && CurrentChatCursor<CurrentChatLine.length){
							CurrentChatCursor++;
						}
						break;
					}
					case SDLK_UP:{
						if(TypingChat && LastSentLine){
							CurrentChatLine=LastSentLine;
							CurrentChatCursor=CurrentChatLine.length;
						}
						break;
					}
					case SDLK_m:{
						if(!TypingChat){
							Render_MiniMap=!Render_MiniMap;
							if(Render_MiniMap)
								Update_MiniMap();
						}
						break;
					}
					case SDLK_c:{
						if(TypingChat && (KeyState[SDL_SCANCODE_LCTRL] || KeyState[SDL_SCANCODE_RCTRL])){
							SDL_SetClipboardText(toStringz(CurrentChatLine));
						}
						break;
					}
					case SDLK_v:{
						if(TypingChat && (KeyState[SDL_SCANCODE_LCTRL] || KeyState[SDL_SCANCODE_RCTRL])){
							if(SDL_HasClipboardText()){
								char *txt=SDL_GetClipboardText();
								if(!txt){
									writeflnerr("Couldn't get clipboard text: %s", *SDL_GetError());
									break;
								}
								char[] txtarr=cast(char[])fromStringz(txt);
								SDL_Event txtevent;
								for(uint ctr=0; ctr<txtarr.length/32+1; ctr++){
									uint ctr2=(ctr+1)*32;
									if(ctr2>txtarr.length)
										ctr2=txtarr.length;
									txtevent.text.text[]=0;
									txtevent.text.text[0..(ctr2-ctr*32)]=txtarr[ctr*32..ctr2];
									txtevent.type=SDL_TEXTINPUT;
									SDL_PushEvent(&txtevent);
								}
								txtarr=[];
								SDL_free(txt);
							}
						}
						break;
					}
					default:{break;}
				}
				if(number_key_pressed>0 && Joined_Game() && !TypingChat){
					ToolSwitchPacketLayout packet;
					number_key_pressed--;
					packet.tool_id=number_key_pressed;
					Send_Packet(ToolSwitchPacketID, packet);
				}
				break;
			}
			case SDL_MOUSEMOTION:{
				if(Lock_Mouse || Menu_Mode){
					MouseMovedX=event.motion.xrel;
					MouseMovedY=event.motion.yrel;
				}
				break;
			}
			case SDL_MOUSEBUTTONDOWN:{
				if(Menu_Mode || Lock_Mouse){
					bool old_left_click=MouseLeftClick, old_right_click=MouseRightClick;
					/*MouseLeftClick=cast(bool)(event.button.button&SDL_BUTTON_LEFT);
					MouseRightClick=cast(bool)(event.button.button&SDL_BUTTON_RIGHT);*/
					//Weird functionality (I mean, why the fuck is SDL_BUTTON_LEFT 1 and SDL_BUTTON_RIGHT 3 ???)
					if(event.button.button<3)
						MouseLeftClick=true;
					if(event.button.button>1)
						MouseRightClick=true;
					if(old_left_click!=MouseLeftClick || old_right_click!=MouseRightClick){
						Send_Mouse_Click(MouseLeftClick, MouseRightClick, event.button.x, event.button.y);
					}
				}
				break;
			}
			case SDL_MOUSEBUTTONUP:{
				if(Menu_Mode || Lock_Mouse){
					bool old_left_click=MouseLeftClick, old_right_click=MouseRightClick;
					/*MouseLeftClick=!(cast(bool)(event.button.button&SDL_BUTTON_LEFT));
					MouseRightClick=!(cast(bool)(event.button.button&SDL_BUTTON_RIGHT));*/
					if(event.button.button<3)
						MouseLeftClick=false;
					if(event.button.button>1)
						MouseRightClick=false;
					if(old_left_click!=MouseLeftClick || old_right_click!=MouseRightClick){
						Send_Mouse_Click(MouseLeftClick, MouseRightClick, event.button.x, event.button.y);
					}
				}
				break;
			}
			case SDL_TEXTINPUT:{
				if(TypingChat){
					string input=cast(string)fromStringz(event.text.text.ptr);
					CurrentChatLine=CurrentChatLine[0..CurrentChatCursor]~input~CurrentChatLine[CurrentChatCursor..$];
					CurrentChatCursor+=input.length;
				}
				break;
			}
			case SDL_TEXTEDITING:{
				writeflnlog("O.O omg I just received an SDL2 text editing event omg does that thing suddenly work now or what...");
				writeflnlog("I wonder whether you see an IME text input bar now :O");
				if(TypingChat){
					CurrentChatLine=cast(string)fromStringz(event.edit.text.ptr);
					CurrentChatCursor=event.edit.start;
				}
				break;
			}
			default:{break;}
		}
	}
	if(!TypingChat){
		QuitGame|=cast(bool)KeyState[SDL_SCANCODE_ESCAPE];
		if(!LoadingMap){
			ushort KeyPresses=0;
			uint[2][] KeyBits=[[SDL_SCANCODE_S, 0], [SDL_SCANCODE_W, 1], [SDL_SCANCODE_A, 2], [SDL_SCANCODE_D, 3],
			[SDL_SCANCODE_SPACE, 4], [SDL_SCANCODE_LCTRL, 5], [SDL_SCANCODE_E, 6], [SDL_SCANCODE_LEFT, 7], [SDL_SCANCODE_RIGHT, 8],
			[SDL_SCANCODE_DOWN, 9], [SDL_SCANCODE_UP, 10]];
			foreach(kb; KeyBits)
				KeyPresses|=(1<<kb[1])*(cast(int)(cast(bool)KeyState[kb[0]]));
			if(KeyPresses!=PrevKeyPresses){
				Send_Key_Presses(KeyPresses);
				PrevKeyPresses=KeyPresses;
				if(Joined_Game()){
					Player_t *plr=&Players[LocalPlayerID];
					plr.Go_Back=cast(bool)(KeyPresses&1);
					plr.Go_Forwards=cast(bool)(KeyPresses&2);
					plr.Go_Left=cast(bool)(KeyPresses&4);
					plr.Go_Right=cast(bool)(KeyPresses&8);
					plr.Jump=cast(bool)(KeyPresses&16);
					//plr.Crouch=cast(bool)(KeyPresses&32);
					plr.Use_Object=cast(bool)(KeyPresses&64);
					plr.KeysChanged=true;
					plr.Set_Crouch(cast(bool)(KeyPresses&32));
				}
			}
		}
	}
	if(!TypingChat && KeyState[SDL_SCANCODE_LSHIFT] && KeyState[SDL_SCANCODE_7]){
		TypingChat=true;
		SDL_StartTextInput();
		CurrentChatLine="/";
		CurrentChatCursor=1;
	}
	{
		uint mousestate=SDL_GetMouseState(&MouseXPos, &MouseYPos);
		/*bool old_left_click=MouseLeftClick, old_right_click=MouseRightClick;
		MouseLeftClick=cast(bool)(mousestate&SDL_BUTTON(SDL_BUTTON_LEFT));
		MouseRightClick=cast(bool)(mousestate&SDL_BUTTON(SDL_BUTTON_RIGHT));
		if(old_left_click!=MouseLeftClick || old_right_click!=MouseRightClick){
			Send_Mouse_Click(MouseLeftClick, MouseRightClick, MouseXPos, MouseYPos);
		}*/
	}
	if(Joined_Game()){
		if(Players[LocalPlayerID].item_types.length){
			if(ItemTypes[Players[LocalPlayerID].items[Players[LocalPlayerID].item].type].show_palette && ProtocolBuiltin_PaletteHFG && ProtocolBuiltin_PaletteVFG){
				float scrollspeed=WorldSpeed*15.0;
				if(KeyState[SDL_SCANCODE_LEFT] && Palette_Color_HIndex>=scrollspeed){
					Changed_Palette_Color=true;
					Scrolling_Colors=true;
					Palette_Color_HPos-=scrollspeed;
				}
				if(KeyState[SDL_SCANCODE_RIGHT] && Palette_Color_HPos+scrollspeed<ProtocolBuiltin_PaletteHFG.xsize){
					Changed_Palette_Color=true;
					Scrolling_Colors=true;
					Palette_Color_HPos+=scrollspeed;
				}
				if(KeyState[SDL_SCANCODE_UP] && Palette_Color_VPos>=scrollspeed){
					Changed_Palette_Color=true;
					Scrolling_Colors=true;
					Palette_Color_VPos-=scrollspeed;
				}
				if(KeyState[SDL_SCANCODE_DOWN] && Palette_Color_VPos+scrollspeed<ProtocolBuiltin_PaletteVFG.ysize){
					Changed_Palette_Color=true;
					Scrolling_Colors=true;
					Palette_Color_VPos+=scrollspeed;
				}
				Palette_Color_HIndex=touint(Palette_Color_HPos); Palette_Color_VIndex=touint(Palette_Color_VPos);
			}
		}
	}
	if(Changed_Palette_Color){
		Check_Palette_Color();
		Changed_Palette_Color=false;
	}
	List_Players=cast(bool)KeyState[SDL_SCANCODE_TAB];
}

string[] ChatText;
uint[] ChatColors;
string CurrentChatLine="";
void WriteMsg(string msg, uint color){
	for(uint i=ChatText.length-1; i; i--){
		ChatColors[i]=ChatColors[i-1];
		ChatText[i]=ChatText[i-1];
	}
	ChatColors[0]=color;
	ChatText[0]=msg;
}

void Check_Palette_Color(){
	if(!ProtocolBuiltin_PaletteHFG || !ProtocolBuiltin_PaletteVFG)
		return;
	/*float xratio=1.0-tofloat(Palette_Color_HIndex)/tofloat(ProtocolBuiltin_PaletteHFG.xsize);
	float yratio=1.0-tofloat(Palette_Color_VIndex)/tofloat(ProtocolBuiltin_PaletteVFG.ysize);
	int pixelx=toint(tofloat(Mod_Picture_Sizes[ProtocolBuiltin_PaletteHFG.picture_index][0]-1)*xratio);
	int pixely=toint(tofloat(Mod_Picture_Sizes[ProtocolBuiltin_PaletteVFG.picture_index][1]-1)*yratio);*/
	int pixelx=((Palette_H_Colors.w-1)*Palette_Color_HIndex/ProtocolBuiltin_PaletteHFG.xsize);
	int pixely=Palette_V_Colors.h-1-((Palette_V_Colors.h-1)*Palette_Color_VIndex/ProtocolBuiltin_PaletteVFG.ysize);
	uint h_color=*Pixel_Pointer(Palette_H_Colors, pixelx, Palette_H_Colors.h/2);
	uint v_color=*Pixel_Pointer(Palette_V_Colors, Palette_V_Colors.w/2, pixely);
	uint new_color;
	{
		int ha=(h_color>>24)&255, hb=(h_color>>16)&255, hg=(h_color>>8)&255, hr=(h_color>>0)&255;
		int va=(v_color>>24)&255, vb=(v_color>>16)&255, vg=(v_color>>8)&255, vr=(v_color>>0)&255;
		ha=min(ha*va/255, 255); hr=min(hr*vr/255, 255); hg=min(hg*vg/255, 255); hb=min(hb*vb/255, 255);
		new_color=(ha<<24) | (hr<<16) | (hg<<8) | hb;
	}
	if(new_color!=Players[LocalPlayerID].color){
		SetPlayerColorPacketLayout packet;
		packet.color=new_color;
		Send_Packet(SetPlayerColorPacketID, packet);
	}
}

uint Palette_Color_HIndex=0, Palette_Color_VIndex=0;
float Palette_Color_HPos=0.0, Palette_Color_VPos=0.0;

void Render_HUD(){
	if(Joined_Game()){
		if(Players[LocalPlayerID].item_types.length){
			if(ItemTypes[Players[LocalPlayerID].items[Players[LocalPlayerID].item].type].is_weapon){
				Item_t *item=&Players[LocalPlayerID].items[Players[LocalPlayerID].item];
				if(AmmoCounterBG){
					MenuElement_t *e=AmmoCounterBG;
					SDL_Rect r;
					r.x=e.xpos; r.y=e.ypos; r.w=e.xsize; r.h=e.ysize;
					if(e.transparency<255)
						SDL_SetTextureAlphaMod(Mod_Pictures[e.picture_index], e.transparency);
					SDL_RenderCopy(scrn_renderer, Mod_Pictures[e.picture_index], null, &r);
					if(e.transparency<255)
						SDL_SetTextureAlphaMod(Mod_Pictures[e.picture_index], 255);
				}
				if(AmmoCounterBullet){
					MenuElement_t *e=AmmoCounterBullet;
					for(uint i=0; i<item.amount1; i++){
						SDL_Rect r;
						r.x=e.xpos; r.y=e.ypos+i*e.ysize; r.w=e.xsize; r.h=e.ysize;
						if(e.transparency<255)
							SDL_SetTextureAlphaMod(Mod_Pictures[e.picture_index], e.transparency);
						SDL_RenderCopy(scrn_renderer, Mod_Pictures[e.picture_index], null, &r);
						if(e.transparency<255)
							SDL_SetTextureAlphaMod(Mod_Pictures[e.picture_index], 255);
					}
				}
			}
			if(ItemTypes[Players[LocalPlayerID].items[Players[LocalPlayerID].item].type].show_palette){
				if(ProtocolBuiltin_PaletteVFG){
					MenuElement_t *e=ProtocolBuiltin_PaletteVFG;
					SDL_Rect r;
					r.x=e.xpos+Palette_Color_HIndex-e.xsize/2; r.y=e.ypos+Palette_Color_VIndex-e.ysize/2; r.w=e.xsize; r.h=e.ysize;
					if(ProtocolBuiltin_PaletteHFG){
						r.y+=ProtocolBuiltin_PaletteHFG.ysize/2;
					}
					if(e.transparency<255)
						SDL_SetTextureAlphaMod(Mod_Pictures[e.picture_index], e.transparency);
					SDL_RenderCopy(scrn_renderer, Mod_Pictures[e.picture_index], null, &r);
					if(e.transparency<255)
						SDL_SetTextureAlphaMod(Mod_Pictures[e.picture_index], 255);
				}
				if(ProtocolBuiltin_PaletteHFG){
					MenuElement_t *e=ProtocolBuiltin_PaletteHFG;
					SDL_Rect r;
					r.x=e.xpos; r.y=e.ypos; r.w=e.xsize; r.h=e.ysize;
					if(e.transparency<255)
						SDL_SetTextureAlphaMod(Mod_Pictures[e.picture_index], e.transparency);
					SDL_RenderCopy(scrn_renderer, Mod_Pictures[e.picture_index], null, &r);
					if(e.transparency<255)
						SDL_SetTextureAlphaMod(Mod_Pictures[e.picture_index], 255);
				}
				if(ProtocolBuiltin_PaletteHFG && ProtocolBuiltin_PaletteVFG){
					MenuElement_t *v=ProtocolBuiltin_PaletteVFG, h=ProtocolBuiltin_PaletteHFG;
					uint color=Players[LocalPlayerID].color;
					SDL_SetRenderDrawColor(scrn_renderer, (color>>16)&255, (color>>8)&255, (color>>0)&255, (color>>24)&255);
					SDL_Rect r;
					r.x=v.xpos+Palette_Color_HIndex-v.xsize/2; r.y=h.ypos; r.w=v.xsize; r.h=h.ysize;
					SDL_RenderFillRect(scrn_renderer, &r);
				}
			}
		}
	}
	Render_All_Text();
}

float ChatLineBlinkSpeed=30.0;
float ChatLineTimer=0.0;
uint __hud_prev_tick=0, __hud_tick_amount=0;
float __hud_avg_delta_ticks=0.0;
void Render_All_Text(){
	if(JoinedGame){
		if(TypingChat){
			ChatLineTimer+=WorldSpeed;
			Render_Text_Line(ChatBox_X, ChatBox_Y, Font_SpecialColor, CurrentChatLine, font_texture, FontWidth, FontHeight, LetterPadding);
			if(((cast(uint)(ChatLineTimer*ChatLineBlinkSpeed))%32)<16){
				Render_Text_Line(ChatBox_X+CurrentChatCursor*(FontWidth/16-LetterPadding*2), ChatBox_Y-LetterPadding*2, 0x80808080, "_", font_texture,
				FontWidth, FontHeight, LetterPadding);
			}
		}
		else{
			ChatLineTimer=0.0;
		}
		foreach(uint i, line; ChatText)
			Render_Text_Line(ChatBox_X, ChatBox_Y+(i+1)*(FontHeight/16), ChatColors[i], line, font_texture, FontWidth, FontHeight, LetterPadding);
	}
	foreach(ref box; TextBoxes){
		if(box.font_index==255)
			continue;
		SDL_Texture *fnt=Mod_Pictures[box.font_index];
		foreach(uint i, ref line; box.lines){
			Render_Text_Line(box.xpos, box.ypos, box.colors[i], line,fnt,Mod_Picture_Sizes[box.font_index][0], Mod_Picture_Sizes[box.font_index][1],0,
			box.xsizeratio, box.ysizeratio);
		}
	}
	uint current_tick=SDL_GetTicks();
	if(__hud_prev_tick && __hud_prev_tick!=current_tick){
		__hud_tick_amount++;
		float delta_t=1000.0/tofloat(current_tick-__hud_prev_tick);
		__hud_avg_delta_ticks+=delta_t;
		float avg=__hud_avg_delta_ticks/tofloat(__hud_tick_amount);
		string fps_ping_str=format("%.2f FPS|%d ms", avg, Get_Ping());
		Render_Text_Line(scrn_surface.w-(FontWidth/16-LetterPadding*2)*fps_ping_str.length, 0, Font_SpecialColor, fps_ping_str, font_texture, FontWidth, FontHeight, LetterPadding);
		if(__hud_tick_amount>avg*5){
			__hud_tick_amount=0;
			__hud_avg_delta_ticks=avg;
		}
	}
	__hud_prev_tick=current_tick;
}
