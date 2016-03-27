import derelict.sdl2.sdl;
import std.string;
import gfx;
import misc;
import network;
import protocol;
import vector;

string[] ChatText;
uint[] ChatColors;
string CurrentChatLine="";

uint CurrentChatCursor;
bool TypingChat=false;

bool QuitGame=false;

ubyte* KeyState;

void Init_UI(){
	ChatText.length=8; ChatColors.length=8;
	KeyState=SDL_GetKeyboardState(null);
}

void UnInit_UI(){
}

void Check_Input(){
	SDL_Event event;
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
					default:{break;}
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
		if(KeyState[SDL_SCANCODE_DOWN]){
			CameraRot.y+=1.0;
		}
		if(KeyState[SDL_SCANCODE_UP]){
			CameraRot.y-=1.0;
		}
		if(KeyState[SDL_SCANCODE_LEFT]){
			CameraRot.x-=1.0;
		}
		if(KeyState[SDL_SCANCODE_RIGHT]){
			CameraRot.x+=1.0;
		}
		if(KeyState[SDL_SCANCODE_W]){
			CameraPos-=CameraRot.sincos().filter(1, 0, 1);
		}
		if(KeyState[SDL_SCANCODE_S]){
			CameraPos+=CameraRot.sincos().filter(1, 0, 1);
		}
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
