import derelict.sdl2.sdl;
import std.string;
import gfx;
import misc;
import network;
import protocol;
import world;
import vector;
import renderer;

uint CurrentChatCursor;
bool TypingChat=false;

bool QuitGame=false;

uint ChatBox_X=0, ChatBox_Y=0;

ubyte* KeyState;

bool Menu_Mode=false;
bool Lock_Mouse=true;
int MouseXPos, MouseYPos;
int MouseMovedX, MouseMovedY;
bool MouseLeftClick, MouseRightClick;

struct MenuElement_t{
	ubyte picture_index;
	int xpos, ypos;
	int xsize, ysize;
	//Maybe optimize menu elements to get deleted when their picture index is 255
	void set(ubyte picindex, float sxpos, float sypos, float sxsize, float sysize){
		float scrnw=cast(float)scrn_surface.w, scrnh=cast(float)scrn_surface.h;
		picture_index=picindex;
		if(picture_index!=255){
			xpos=cast(int)(sxpos*scrnw);
			ypos=cast(int)(sypos*scrnh);
			xsize=cast(int)(sxsize*scrnw);
			ysize=cast(int)(sysize*scrnh);
		}
	}
}

MenuElement_t[] MenuElements;

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
					//Hardcoded key handling
					//Somebody make a GUI please so I can remove the team limits
					/*case SDLK_1:{
						if(!JoinedGame)
							Join_Team(0);
						break;
					}
					case SDLK_2:{
						if(!JoinedGame)
							Join_Team(1);
						break;
					}
					case SDLK_3:{
						if(!JoinedGame)
							Join_Team(2);
						break;
					}*/
					case SDLK_F10:{
						Set_Menu_Mode(!Menu_Mode);
						break;
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
	{
		uint mousestate=SDL_GetMouseState(&MouseXPos, &MouseYPos);
		bool old_left_click=MouseLeftClick, old_right_click=MouseRightClick;
		MouseLeftClick=cast(bool)(mousestate&SDL_BUTTON(SDL_BUTTON_LEFT));
		MouseRightClick=cast(bool)(mousestate&SDL_BUTTON(SDL_BUTTON_RIGHT));
		if(old_left_click!=MouseLeftClick || old_right_click!=MouseRightClick){
			if(Menu_Mode){
				Send_Mouse_Click(MouseLeftClick, MouseRightClick, MouseXPos, MouseYPos);
			}
		}
		if(JoinedGame){
			if(MouseLeftClick && Players[LocalPlayerID].spawned && !Menu_Mode)
				Try_Shoot();
		}
	}
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

float ChatLineBlinkSpeed=5000.0;
float ChatLineTimer=0.0;
void Render_HUD(){
	ChatLineTimer+=WorldSpeed;
	if(TypingChat){
		Render_Text_Line(ChatBox_X, ChatBox_Y, Font_SpecialColor, CurrentChatLine);
		if(((cast(uint)(ChatLineTimer*ChatLineBlinkSpeed))%32)<16){
			Render_Text_Line(ChatBox_X+CurrentChatLine.length*(FontWidth/16-LetterPadding*2), ChatBox_Y-LetterPadding*2, 0x80808080, "_");
		}
	}
	foreach(uint i, line; ChatText)
		Render_Text_Line(ChatBox_X, ChatBox_Y+(i+1)*(FontHeight/16), ChatColors[i], line);
}
