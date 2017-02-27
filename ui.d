version(LDC){
	import ldc_stdlib;
}
version(GNU){
	import gdc_stdlib;
}
import derelict.sdl2.sdl;
import std.string;
import std.algorithm;
import std.conv;
import std.stdio;
import std.file;
import gfx;
import main;
import misc;
import network;
import protocol;
import world;
import vector;
import renderer;
import packettypes;
import script;
import modlib;
import core.stdc.stdio;

uint CurrentChatCursor;
bool TypingChat=false;

bool QuitGame=false;

uint ChatBox_X=0, ChatBox_Y=0;

ubyte[] KeyState;

bool List_Players=false;

bool Menu_Mode=false;
bool Lock_Mouse=true;
int MouseXPos, MouseYPos;
int MouseMovedX, MouseMovedY;
bool MouseLeftClick, MouseRightClick;
bool MouseLeftChanged, MouseRightChanged;

bool Mouse_ManualUnlock=false;

bool Render_MiniMap;

string LastSentLine="";

bool Changed_Palette_Color=false;
SDL_Surface *Palette_V_Colors, Palette_H_Colors;

bool NoobMessage_Enable=false, ServerMessage_Enable=false, SettingsMenu_Enable=false;
enum SettingsMenu_Options{
	Smoke, Quality, FPSTarget, Upscale, Particles, Effects, FPSPingCounter, Flashes, ChatAlpha
}

struct SettingsMenuEntry_t{
	string key;
	string entry;
	string type;
	float minval, maxval;
	string description;
}

SettingsMenu_Options SettingsMenu_SelectedOption;
SettingsMenuEntry_t[SettingsMenu_Options] SettingsMenu_ConfigEntries;

void SettingsMenu_ChangeEntry(float val){
	auto entry=SettingsMenu_ConfigEntries[SettingsMenu_SelectedOption];
	if(entry.maxval==entry.minval)
		return;
	float rangestep;
	if(entry.minval==float.infinity || entry.maxval==float.infinity)
		rangestep=1.0;
	else
		rangestep=(entry.maxval-entry.minval)/10.0;
	if(entry.type=="float"){
		float newval=Config_Read!float(entry.entry)+val*rangestep;
		newval=min(newval, entry.maxval); newval=max(newval, entry.minval);
		Config_Write(entry.entry, newval);
		if(SettingsMenu_SelectedOption==SettingsMenu_Options.Smoke)
			SmokeAmount=Renderer_SmokeRenderSpeed*Config_Read!float("smoke")*10.0;
		if(SettingsMenu_SelectedOption==SettingsMenu_Options.Quality)
			Renderer_SetQuality(Config_Read!float("renderquality"));
		if(SettingsMenu_SelectedOption==SettingsMenu_Options.Upscale)
			Change_Resolution(WindowXSize, WindowYSize);
	}
	if(entry.type=="uint"){
		val*=5.0;
		immutable uint oldval=Config_Read!uint(entry.entry);
		uint newval=oldval;
		int step=cast(int)(val*rangestep);
		if((step>0 && uint.max-step>oldval) || (step<0 && oldval>=-step)){
			if((entry.minval==float.infinity || oldval>=entry.minval-step || step>0) && (entry.maxval==float.infinity || entry.maxval-step>oldval || step<0))
				newval=oldval+step;
			else
				newval=step<0 ? cast(uint)entry.minval : cast(uint)entry.maxval;
		}
		else{
			newval=step<0 ? uint.min : uint.max;
		}
		Config_Write(entry.entry, newval);
	}
	if(entry.type=="ubyte"){
		immutable ubyte oldval=Config_Read!ubyte(entry.entry);
		ubyte newval=oldval;
		byte step=cast(byte)(val*rangestep);
		if((step>0 && ubyte.max-step>oldval) || (step<0 && oldval>=-step)){
			if((entry.minval==float.infinity || oldval>=entry.minval-step || step>0) && (entry.maxval==float.infinity || entry.maxval-step>oldval || step<0))
				newval=cast(ubyte)(oldval+step);
			else
				newval=step<0 ? cast(ubyte)entry.minval : cast(ubyte)entry.maxval;
		}
		else{
			newval=step<0 ? ubyte.min : ubyte.max;
		}
		Config_Write(entry.entry, newval);
	}
	if(entry.type=="bool"){
		Config_Write(entry.entry, val>0.0 ? "true" : "false");
	}
}

void ConvertScreenCoords(in float uxpos, in float uypos, out int lxpos, out int lypos){
	float scrnw=cast(float)ScreenXSize, scrnh=cast(float)ScreenYSize;
	lxpos=cast(int)(uxpos*scrnw); lypos=cast(int)(uypos*scrnh);
}

struct MenuElement_t{
	ubyte index;
	ubyte picture_index;
	ubyte zpos;
	ubyte transparency;
	bool reserved;
	int xpos, ypos;
	int xsize, ysize;
	float fxpos, fypos;
	float fxsize, fysize;
	union{
		uint icolor_mod;
		ubyte[3] bcolor_mod;
	}
	//Maybe optimize menu elements to get deleted when their picture index is 255
	void set(ubyte initindex, ubyte picindex, ubyte zval, float sxpos, float sypos, float sxsize, float sysize, ubyte inittransparency, uint colormod=0x00ffffff){
		index=initindex;
		picture_index=picindex;
		fxpos=sxpos; fypos=sypos;
		fxsize=sxsize; fysize=sysize;
		transparency=inittransparency;
		icolor_mod=colormod;
		AdjustToScreen();
		move_z(zval);
	}
	void move_z(ubyte zval){
		if(zpos!=zval){
			int arrind=cast(int)countUntil(Z_MenuElements[zpos], index);
			if(arrind>=0)
				Z_MenuElements[zpos]=Z_MenuElements[zpos].remove(arrind);
			Z_MenuElements[zval]~=index;
		}
		zpos=zval;
	}
	bool inactive(){
		return this.picture_index==255 || this.transparency==0 || !this.xsize || !this.ysize;
	}
	void AdjustToScreen(){
		ConvertScreenCoords(fxpos, fypos, xpos, ypos);
		ConvertScreenCoords(fxsize, fysize, xsize, ysize);
	}
}

uint[][256] Z_MenuElements;

MenuElement_t[] MenuElements;

MenuElement_t *ProtocolBuiltin_AmmoCounterBG;
MenuElement_t *ProtocolBuiltin_AmmoCounterBullet;
MenuElement_t *ProtocolBuiltin_PaletteHFG;
MenuElement_t *ProtocolBuiltin_PaletteVFG;

struct TextBox_t{
	ubyte font_index;
	int xpos, ypos;
	int xsize, ysize;
	float fxpos, fypos;
	float fxsize, fysize;
	bool wrap_lines;
	ubyte move_lines;
	string[] lines;
	uint[] colors;
	void set(ubyte picindex, float sxpos, float sypos, float sxsize, float sysize, ubyte flags){
		font_index=picindex;
		fxpos=sxpos; fypos=sypos;
		fxsize=sxsize; fysize=sysize;
		wrap_lines=cast(bool)(flags&TEXTBOX_FLAG_WRAP);
		move_lines=(flags&TEXTBOX_FLAG_MOVELINESDOWN) | (flags&TEXTBOX_FLAG_MOVELINESUP);
		AdjustToScreen();
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
	bool inactive(){
		return this.font_index==255 || !this.lines.length || !this.xsize || !this.ysize;
	}
	void AdjustToScreen(){
		ConvertScreenCoords(fxpos, fypos, xpos, ypos);
		ConvertScreenCoords(fxsize, fysize, xsize, ysize);
	}
}

TextBox_t[] TextBoxes;

void Init_UI(){
	ChatText.length=8; ChatColors.length=8;
	ubyte *kbstate;
	int kbstatesize;
	kbstate=SDL_GetKeyboardState(&kbstatesize);
	KeyState=cast(ubyte[])kbstate[0..kbstatesize];
	Set_Menu_Mode(false);
	SettingsMenu_ConfigEntries=[
		SettingsMenu_Options.Smoke : SettingsMenuEntry_t("o", "smoke", "float", 0.0, float.infinity, "sets smoke"),
		SettingsMenu_Options.Quality : SettingsMenuEntry_t("q", "renderquality", "float", 1.0, float.infinity, "set render quality (smallest is 1.0, higher value = lower quality)"),
		SettingsMenu_Options.FPSTarget : SettingsMenuEntry_t("f", "fpscap", "uint", 0.0, float.infinity, "sets the maximum framerate"),
		SettingsMenu_Options.Upscale : SettingsMenuEntry_t("u", "upscale", "float", 0.0, 1.0, "sets the upscale rate"),
		SettingsMenu_Options.Particles : SettingsMenuEntry_t("p", "particles", "float", 0.0, float.infinity, "sets the particle amount"),
		SettingsMenu_Options.Effects : SettingsMenuEntry_t("e", "effects", "bool", 0.0, 1.0, "toggles various graphical effects (like explosions)"),
		SettingsMenu_Options.FPSPingCounter : SettingsMenuEntry_t("c", "fps_ping_counter", "bool", 0.0, 1.0, "toggles the FPS and ping counter"),
		SettingsMenu_Options.Flashes : SettingsMenuEntry_t("l", "flashes", "bool", 0.0, 1.0, "toggles flashes from shots and explosions"),
		SettingsMenu_Options.ChatAlpha : SettingsMenuEntry_t("h", "chat_alpha", "ubyte", 0, 255, "sets chat transparency")
	];
}

void UnInit_UI(){
}

void Mouse_SetLock(bool lock){
	SDL_SetRelativeMouseMode((lock && !Mouse_ManualUnlock) ? SDL_TRUE : SDL_FALSE);
}

void Set_Menu_Mode(bool mode){
	Lock_Mouse=!mode;
	Mouse_SetLock(Lock_Mouse);
	Menu_Mode=mode;
}

uint PrevKeyPresses=0;

void Chat_StartTyping(){
	if(JoinedGamePhase>=JoinedGameMaxPhases){
		TypingChat=true;
		SDL_StartTextInput();
		CurrentChatLine="";
		CurrentChatCursor=0;		
	}
}

void Check_Input(){
	SDL_Event event;
	MouseMovedX=0; MouseMovedY=0;
	MouseLeftChanged=false; MouseRightChanged=false;
	bool Scrolling_Colors=false;
	bool QuitEventReceived=false;
	while(SDL_PollEvent(&event)){
		switch(event.type){
			case SDL_QUIT:{
				QuitEventReceived=true;
				break;
			}
			case SDL_KEYDOWN:{
				byte number_key_pressed=0;
				switch(event.key.keysym.sym){
					case SDLK_RETURN:{
						if(JoinedGamePhase>=JoinedGameMaxPhases){
							TypingChat=!TypingChat;
							if(TypingChat){
								Chat_StartTyping();
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
						break;
					}
					case SDLK_BACKSPACE:{
						if(TypingChat && CurrentChatCursor){
							CurrentChatLine=CurrentChatLine[0..CurrentChatCursor-1]~CurrentChatLine[CurrentChatCursor..$];
							CurrentChatCursor--;
						}
						break;
					}
					case SDLK_r:{
						if(Joined_Game() && !TypingChat){
							if(true){
								ItemReloadPacketLayout packet;
								Send_Packet(ItemReloadPacketID, packet);
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
					case SDLK_HOME:{
						Mouse_ManualUnlock=!Mouse_ManualUnlock;
						Mouse_SetLock(Lock_Mouse);
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
							CurrentChatCursor=cast(uint)CurrentChatLine.length;
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
					case SDLK_e:if(!TypingChat && SettingsMenu_Enable)SettingsMenu_SelectedOption=SettingsMenu_Options.Effects;break;
					case SDLK_o:if(!TypingChat && SettingsMenu_Enable)SettingsMenu_SelectedOption=SettingsMenu_Options.Smoke;break;
					case SDLK_p:if(!TypingChat && SettingsMenu_Enable)SettingsMenu_SelectedOption=SettingsMenu_Options.Particles;break;
					case SDLK_q:if(!TypingChat && SettingsMenu_Enable)SettingsMenu_SelectedOption=SettingsMenu_Options.Quality;break;
					case SDLK_f:if(!TypingChat && SettingsMenu_Enable)SettingsMenu_SelectedOption=SettingsMenu_Options.FPSTarget;break;
					case SDLK_u:if(!TypingChat && SettingsMenu_Enable)SettingsMenu_SelectedOption=SettingsMenu_Options.Upscale;break;
					case SDLK_c:{
						if(TypingChat && (KeyState[SDL_SCANCODE_LCTRL] || KeyState[SDL_SCANCODE_RCTRL])){
							SDL_SetClipboardText(toStringz(CurrentChatLine));
						}
						if(!TypingChat && SettingsMenu_Enable)SettingsMenu_SelectedOption=SettingsMenu_Options.FPSPingCounter;
						break;
					}
					case SDLK_l:if(!TypingChat && SettingsMenu_Enable)SettingsMenu_SelectedOption=SettingsMenu_Options.Flashes;break;
					case SDLK_h:if(!TypingChat && SettingsMenu_Enable)SettingsMenu_SelectedOption=SettingsMenu_Options.ChatAlpha;break;
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
										ctr2=cast(uint)txtarr.length;
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
					case SDLK_PLUS:{
						if(!TypingChat && SettingsMenu_Enable){
							SettingsMenu_ChangeEntry(KeyState[SDL_SCANCODE_LCTRL] ? 1.0 : .5);
						}
						break;
					}
					case SDLK_MINUS:{
						if(!TypingChat && SettingsMenu_Enable){
							SettingsMenu_ChangeEntry(KeyState[SDL_SCANCODE_LCTRL] ? -1.0 : -.5);
						}
						break;
					}
					case SDLK_F1:{
						NoobMessage_Enable=!NoobMessage_Enable;
						if(NoobMessage_Enable){
							ServerMessage_Enable=false;
							SettingsMenu_Enable=false;
						}
						break;
					}
					case SDLK_F2:{
						ServerMessage_Enable=!ServerMessage_Enable;
						if(ProtocolBuiltin_ServerMessageScript>=0){
							if(ServerMessage_Enable)
								Loaded_Scripts[ProtocolBuiltin_ServerMessageScript].Call_Func("Show");
							else
								Loaded_Scripts[ProtocolBuiltin_ServerMessageScript].Call_Func("Hide");
						}
						if(ServerMessage_Enable){
							NoobMessage_Enable=false;
							SettingsMenu_Enable=false;
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
					MouseMovedX += event.motion.xrel;
					MouseMovedY += event.motion.yrel;
				}
				break;
			}
			case SDL_MOUSEBUTTONDOWN:{
				if(Menu_Mode || Lock_Mouse){
					bool old_left_click=MouseLeftClick, old_right_click=MouseRightClick;
					/*MouseLeftClick=cast(bool)(event.button.button&SDL_BUTTON_LEFT);
					MouseRightClick=cast(bool)(event.button.button&SDL_BUTTON_RIGHT);*/
					//Weird functionality (I mean, why the fuck is SDL_BUTTON_LEFT 1 and SDL_BUTTON_RIGHT 3 ??? It even goes against the docs)
					if(event.button.button<3)
						MouseLeftClick=true;
					if(event.button.button>1)
						MouseRightClick=true;
					MouseLeftChanged=old_left_click!=MouseLeftClick;
					MouseRightChanged=old_right_click!=MouseRightClick;
					if(MouseLeftChanged && MouseLeftClick && JoinedGame){
						if(Players[LocalPlayerID].items.length){
							if(Players[LocalPlayerID].items[Players[LocalPlayerID].item].Can_Use()){
								Update_Position_Data(true);
								Update_Rotation_Data(true);
							}
						}
					}
					if(MouseLeftChanged || MouseRightChanged){
						Send_Mouse_Click(MouseLeftClick, MouseRightClick, event.button.x, event.button.y);
					}
					if(Menu_Mode)
						Script_OnMouseClick(MouseLeftClick, MouseRightClick);
					if(Joined_Game()){
						Players[LocalPlayerID].left_click=MouseLeftClick;
						Players[LocalPlayerID].right_click=MouseRightClick;
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
					MouseLeftChanged=old_left_click!=MouseLeftClick;
					MouseRightChanged=old_right_click!=MouseRightClick;
					if(MouseLeftChanged || MouseRightChanged){
						Send_Mouse_Click(MouseLeftClick, MouseRightClick, event.button.x, event.button.y);
					}
					if(Menu_Mode)
						Script_OnMouseClick(MouseLeftClick, MouseRightClick);
					if(Joined_Game()){
						Players[LocalPlayerID].left_click=MouseLeftClick;
						Players[LocalPlayerID].right_click=MouseRightClick;
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
				if(TypingChat){
					CurrentChatLine=cast(string)fromStringz(event.edit.text.ptr);
					CurrentChatCursor=event.edit.start;
				}
				break;
			}
			case SDL_WINDOWEVENT:{
				switch(event.window.event){
					case SDL_WINDOWEVENT_RESIZED:
					case SDL_WINDOWEVENT_SIZE_CHANGED:{
						Change_Resolution(event.window.data1, event.window.data2);
						SDL_DisplayMode dmode;
						if(!SDL_GetCurrentDisplayMode(SDL_GetWindowDisplayIndex(scrn_window), &dmode)){
							ClientConfig["fullscreen"]=to!string(dmode.w==event.window.data1 && dmode.h==event.window.data2);
						}
						break;
					}
					default:{break;}
				}
				break;
			}
			case SDL_DROPFILE:{
				string contents=readText(fromStringz(event.drop.file));
				if(!TypingChat){
					Chat_StartTyping();
				}
				if(TypingChat)
					CurrentChatLine~=contents;
				if(event.drop.file)
					SDL_free(event.drop.file);
				break;
			}
			default:{break;}
		}
	}
	if(QuitEventReceived){
		if(!KeyState[SDL_SCANCODE_LALT])
			QuitGame=true;
		else
			SettingsMenu_Enable=!SettingsMenu_Enable;
		if(SettingsMenu_Enable){
			ServerMessage_Enable=false;
			NoobMessage_Enable=false;
		}
	}
	if(!TypingChat){
		QuitGame|=cast(bool)KeyState[SDL_SCANCODE_ESCAPE];
		if(!LoadingMap){
			ushort KeyPresses=0;
			uint[2][] KeyBits=[[SDL_SCANCODE_S, 0], [SDL_SCANCODE_W, 1], [SDL_SCANCODE_A, 2], [SDL_SCANCODE_D, 3],
			[SDL_SCANCODE_SPACE, 4], [SDL_SCANCODE_LCTRL, 5], [SDL_SCANCODE_E, 6], [SDL_SCANCODE_LEFT, 7], [SDL_SCANCODE_RIGHT, 8],
			[SDL_SCANCODE_DOWN, 9], [SDL_SCANCODE_UP, 10], [SDL_SCANCODE_LSHIFT, 11]];
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
					plr.Set_Crouch(cast(bool)(KeyPresses&32));
					plr.Use_Object=cast(bool)(KeyPresses&64);
					plr.Sprint=cast(bool)(KeyPresses&2048);
					plr.KeysChanged=true;
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
		if(Players[LocalPlayerID].items.length){
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
	for(uint i=cast(uint)ChatText.length-1; i; i--){
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
	//TODO: fix array out of bounds exception
	if(Joined_Game()){
		if(Players[LocalPlayerID].items.length){
			if(ItemTypes[Players[LocalPlayerID].items[Players[LocalPlayerID].item].type].is_weapon){
				Item_t *item=&Players[LocalPlayerID].items[Players[LocalPlayerID].item];
				if(ProtocolBuiltin_AmmoCounterBG){
					MenuElement_Draw(ProtocolBuiltin_AmmoCounterBG);
				}
				if(ProtocolBuiltin_AmmoCounterBullet && !item.Reloading){
					MenuElement_t *e=ProtocolBuiltin_AmmoCounterBullet;
					int xsizechange=0, ysizechange=0;
					if(e.xsize>=e.ysize){
						ysizechange=e.ysize;
					}
					if(e.ysize>=e.xsize){
						xsizechange=e.xsize;
					}
					for(uint i=0; i<item.amount1; i++){
						MenuElement_Draw(e,e.xpos+i*xsizechange,e.ypos+i*ysizechange,e.xsize,e.ysize);
					}
				}
			}
			if(ItemTypes[Players[LocalPlayerID].items[Players[LocalPlayerID].item].type].show_palette){
				if(ProtocolBuiltin_PaletteVFG){
					MenuElement_t *e=ProtocolBuiltin_PaletteVFG;
					SDL_Rect r;
					int y = e.ypos+Palette_Color_VIndex-e.ysize/2;
					if(ProtocolBuiltin_PaletteHFG){
						y += ProtocolBuiltin_PaletteHFG.ysize/2;
					}
					MenuElement_Draw(e,e.xpos+Palette_Color_HIndex-e.xsize/2,y,e.xsize,e.ysize);
				}
				if(ProtocolBuiltin_PaletteHFG){
					MenuElement_Draw(ProtocolBuiltin_PaletteHFG);
				}
				if(ProtocolBuiltin_PaletteHFG && ProtocolBuiltin_PaletteVFG){
					MenuElement_t *v=ProtocolBuiltin_PaletteVFG, h=ProtocolBuiltin_PaletteHFG;
					uint color=Players[LocalPlayerID].color;
					//SDL_SetRenderDrawColor(scrn_renderer, (color>>16)&255, (color>>8)&255, (color>>0)&255, (color>>24)&255);
					//MenuElement_Draw(v,v.xpos+Palette_Color_HIndex-v.xsize/2,h.ypos,v.xsize,v.ysize);
					//SDL_RenderFillRect(scrn_renderer, &r);
				}
			}
		}
	}
	Render_All_Text();
}

float ChatLineBlinkSpeed=30.0;
float ChatLineTimer=0.0;
string InstructionsFile_Contents="";
void Render_All_Text(){
	if(!ChatBox_Y)
		ChatBox_Y=FontHeight/16;
	if(JoinedGame){
		if(TypingChat){
			ChatLineTimer+=WorldSpeed;
			Render_Text_Line(ChatBox_X, ChatBox_Y+to!uint(ChatText.length)*(FontHeight/16), Font_SpecialColor, CurrentChatLine, font_texture, FontWidth, FontHeight, LetterPadding);
			if(((cast(uint)(ChatLineTimer*ChatLineBlinkSpeed))%32)<16){
				Render_Text_Line(ChatBox_X+CurrentChatCursor*(FontWidth/16-LetterPadding*2),
				ChatBox_Y+to!uint(ChatText.length)*(FontHeight/16)-LetterPadding*2, 0x80808080, "_", font_texture,
				FontWidth, FontHeight, LetterPadding);
			}
		}
		else{
			ChatLineTimer=0.0;
		}
		{
			uint linepos=0;
			immutable uint chat_alpha=Config_Read!ubyte("chat_alpha")<<24;
			foreach_reverse(i, line; ChatText){
				if(line.length){
					Render_Text_Line(ChatBox_X, ChatBox_Y+linepos*(FontHeight/16), ChatColors[i] | chat_alpha, line, font_texture, FontWidth, FontHeight, LetterPadding);
					linepos++;
				}
			}
		}
	}
	foreach(ref box; TextBoxes){
		if(box.font_index==255)
			continue;
		uint ypos=box.ypos;
		foreach(uint i, ref line; box.lines){
			uint col;
			if(box.colors.length)
				col=box.colors[i];
			else
				col=0xffffffff;
			//Render_Text_Line(box.xpos, ypos, col, line, Mod_Pictures[box.font_index], Mod_Picture_Sizes[box.font_index][0], Mod_Picture_Sizes[box.font_index][1], 0,
			//box.xsizeratio, box.ysizeratio);
			Render_Text_Line(box.xpos, ypos, col, line, Mod_Pictures[box.font_index], Mod_Picture_Sizes[box.font_index][0], Mod_Picture_Sizes[box.font_index][1], 0,
			[box.xpos+box.xsize, ypos+box.ysize/box.lines.length]);
			if(box.wrap_lines)
				ypos+=to!float(Mod_Picture_Sizes[box.font_index][1]);
		}
	}
	if(NoobMessage_Enable){
		if(!InstructionsFile_Contents.length){
			import std.file;
			InstructionsFile_Contents=readText("./Instructions.txt");
			if(!InstructionsFile_Contents.length)
				InstructionsFile_Contents.length=1;
		}
		Renderer_FillRect(null, 0xff00ffff);
		string nick=JoinedGame ? Players[LocalPlayerID].name : Config_Read!string("nick");
		Render_Text_Line(0, 0, Font_SpecialColor, "Welcome to VoxelWar version "~to!string(Protocol_Version)~", "~nick~"!
Well, there's a short and simple instructions file, but why even bother reading that!1!1!111!!!1
Anyways, here's the instructions:\n"~InstructionsFile_Contents, font_texture, FontWidth, FontHeight, LetterPadding);
	}
	if(SettingsMenu_Enable){
		Renderer_FillRect(null, 0x80008080);
		string settings_str="VoxelWar engine settings:\n";
		foreach(entry; SettingsMenu_ConfigEntries.byValue())
			settings_str~="	"~entry.key~" = "~entry.description~" {"~Config_Read!string(entry.entry)~"}\n";
		Render_Text_Line(0, 0, Font_SpecialColor, settings_str, font_texture, FontWidth, FontHeight, LetterPadding, [ScreenXSize, ScreenYSize]);
	}
	static PreciseClock_t __hud_prev_tick;
	static uint __hud_tick_amount;
	static PreciseClockDiff_t __hud_ticks_sum;
	auto current_tick=PreciseClock();
	if(__hud_prev_tick>PreciseClock_TimeFromNSecs(0) && __hud_prev_tick!=current_tick){
		__hud_tick_amount++;
		__hud_ticks_sum+=current_tick-__hud_prev_tick;
		real avg=(cast(real)10e9)*(cast(real)__hud_tick_amount)/(cast(real)PreciseClock_ToNSecs(__hud_ticks_sum));
		if(Config_Read!bool("fps_ping_counter")){
			string fps_ping_str=format("[%.2f FPS;%s ms]", avg, Get_Ping());
			Render_Text_Line(cast(int)(ScreenXSize-(FontWidth/16-LetterPadding*2)*fps_ping_str.length), 0, Font_SpecialColor, fps_ping_str, font_texture, FontWidth, FontHeight, LetterPadding);
		}
		if(__hud_tick_amount>avg*5){
			__hud_ticks_sum/=__hud_tick_amount;
			__hud_tick_amount=1;
		}
	}
	__hud_prev_tick=current_tick;
}




string[string] ClientConfig;

T Config_Read(T)(string entry){
	if(!(entry in ClientConfig)){
		writeflnerr("Missing client config entry %s", entry);
		return T.init;
	}
	try{
		return to!T(ClientConfig[entry]);
	}catch(ConvException){
		writeflnerr("config.txt entry %s has an invalid value of %s (has to be of type %s)", entry, ClientConfig[entry], T.stringof);
	}
	return T.init;
}

void Config_Write(T)(string entry, T val){
	ClientConfig[entry]=to!string(val);
}

void ClientConfig_Load(){
	import std.file;
	if(!exists("./config.txt")){
		ClientConfig["nick"]="Deuce";
		ClientConfig["resolution_x"]="800";
		ClientConfig["resolution_y"]="600";
		ClientConfig["fullscreen"]="false";
		ClientConfig["upscale"]="0.5";
		ClientConfig["anti_aliasing"]="false";
		ClientConfig["smoke"]="1.0";
		ClientConfig["fpscap"]="60";
		ClientConfig["renderquality"]="1.5";
		ClientConfig["particles"]="1.0";
		ClientConfig["effects"]="true";
		ClientConfig["vsync"]="true";
		ClientConfig["hwaccel"]="true";
		ClientConfig["flashes"]="true";
		ClientConfig["chat_alpha"]="255";
		ClientConfig["fps_ping_counter"]="false";
		ClientConfig["mouse_accuracy"]="0.075";
		ClientConfig["last_addr"]="localhost";
		ClientConfig["last_port"]="32887";
		ClientConfig.rehash();
		return;
	}
	auto f=File("./config.txt", "r");
	string line;
	while((line=f.readln())!=null){
		string entry_name, entry_content;
		size_t eqpos=line.indexOf('=');
		if(eqpos<0)
			continue;
		entry_name=line[0..eqpos].strip();
		entry_content=line[eqpos+1..$-1];
		ClientConfig[entry_name]=entry_content;
	}
	ClientConfig.rehash();
}

void ClientConfig_Save(){
	ClientConfig.rehash();
	auto f=File("./config.txt", "wb+");
	foreach(entry; ClientConfig.byKey()){
		f.writeln(entry, "=", ClientConfig[entry]);
	}
}
