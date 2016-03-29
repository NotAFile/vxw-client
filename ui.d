import derelict.sdl2.sdl;
import std.string;
import gfx;
import misc;
import network;
import protocol;
import world;
import vector;

string[] ChatText;
uint[] ChatColors;
string CurrentChatLine="";

uint CurrentChatCursor;
bool TypingChat=false;

bool QuitGame=false;

ubyte* KeyState;

bool Lock_Mouse=true;
int MouseXPos, MouseYPos;
int MouseMovedX, MouseMovedY;
bool MouseLeftClick, MouseRightClick;

void Init_UI(){
	ChatText.length=8; ChatColors.length=8;
	KeyState=SDL_GetKeyboardState(null);
}

void UnInit_UI(){
}

uint PrevKeyPresses=0;

void Check_Input(){
	SDL_Event event;
	MouseMovedX=0; MouseMovedY=0;
	while(SDL_PollEvent(&event)){
		switch(event.type){
			case SDL_QUIT:{
				QuitGame=true;
				break;
			}
			case SDL_KEYDOWN:{
				switch(event.key.keysym.sym){
					case SDLK_RETURN:{
						TypingChat=!TypingChat;
						if(TypingChat){
							SDL_StartTextInput();
							CurrentChatLine="";
						}
						else{
							SDL_StopTextInput();
							if(CurrentChatLine.length)
								Send_Chat_Packet(CurrentChatLine);
							CurrentChatLine="";
						}
					}
					case SDLK_BACKSPACE:{
						if(CurrentChatLine.length)
							CurrentChatLine.length--;
					}
					case SDLK_F10:{
						Lock_Mouse=!Lock_Mouse;
						SDL_SetRelativeMouseMode(Lock_Mouse ? SDL_TRUE : SDL_FALSE);
					}
					default:{break;}
				}
				break;
			}
			case SDL_MOUSEMOTION:{
				if(Lock_Mouse){
					MouseMovedX=event.motion.xrel;
					MouseMovedY=event.motion.yrel;
				}
				break;
			}
			case SDL_TEXTINPUT:{
				if(TypingChat){
					string input=cast(string)fromStringz(event.text.text.ptr);
					CurrentChatLine~=input;
				}
				break;
			}
			case SDL_TEXTEDITING:{
				if(TypingChat){
					CurrentChatLine=cast(string)fromStringz(event.edit.text.ptr);
					CurrentChatCursor=event.edit.start;
					writeflnlog("SDL editing text %d", event.edit.length);
				}
				break;
			}
			default:{break;}
		}
	}
	if(!TypingChat){
		QuitGame|=cast(bool)KeyState[SDL_SCANCODE_ESCAPE];
		if(Joined_Game()){
			ubyte KeyPresses=0;
			uint[2][] KeyBits=[[SDL_SCANCODE_S, 0], [SDL_SCANCODE_W, 1], [SDL_SCANCODE_A, 2], [SDL_SCANCODE_D, 3],
			[SDL_SCANCODE_SPACE, 4], [SDL_SCANCODE_LCTRL, 5]];
			foreach(kb; KeyBits)
				KeyPresses|=(1<<kb[1])*(cast(int)(cast(bool)KeyState[kb[0]]));
			if(KeyPresses!=PrevKeyPresses){
				Send_Key_Presses(KeyPresses);
				PrevKeyPresses=KeyPresses;
				Player_t *plr=&Players[LocalPlayerID];
				plr.Go_Back=cast(bool)(KeyPresses&1);
				plr.Go_Forwards=cast(bool)(KeyPresses&2);
				plr.Go_Left=cast(bool)(KeyPresses&4);
				plr.Go_Right=cast(bool)(KeyPresses&8);
				plr.Jump=cast(bool)(KeyPresses&16);
				plr.Crouch=cast(bool)(KeyPresses&32);
				plr.KeysChanged=true;
			}
		}
	}
	if(!Lock_Mouse){
		uint mousestate=SDL_GetMouseState(&MouseXPos, &MouseYPos);
		MouseLeftClick=cast(bool)(mousestate&SDL_BUTTON(SDL_BUTTON_LEFT));
		MouseRightClick=cast(bool)(mousestate&SDL_BUTTON(SDL_BUTTON_RIGHT));
	}
}

void WriteMsg(string msg, uint color){
	for(uint i=ChatText.length-1; i; i--){
		ChatColors[i]=ChatColors[i-1];
		ChatText[i]=ChatText[i-1];
	}
	ChatColors[0]=color;
	ChatText[0]=msg;
}

void Render_HUD(){
	if(TypingChat)
		Render_Text_Line(0, 0, Font_SpecialColor, CurrentChatLine~"_");
	foreach(uint i, line; ChatText)
		Render_Text_Line(0, (i+1)*FontHeight/16, ChatColors[i], line);
}
