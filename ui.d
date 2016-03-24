import derelict.sdl2.sdl;
import std.string;
import gfx;
import misc;
import network;
import protocol;

string[] ChatText;
string CurrentChatLine="";

uint CurrentChatCursor;
bool TypingChat=false;

bool QuitGame=false;

ubyte* KeyState;

void Init_UI(){
	ChatText.length=8;
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
	QuitGame|=cast(bool)KeyState[SDL_SCANCODE_ESCAPE];
}

void WriteMsg(string msg){
	for(uint i=ChatText.length-1; i; i--)
		ChatText[i]=ChatText[i-1];
	ChatText[0]=msg;
}

void Render_HUD(){
	if(TypingChat)
		Render_Text_Line(0, 0, CurrentChatLine~"_");
	foreach(uint i, line; ChatText)
		Render_Text_Line(0, (i+1)*FontHeight/16, line);
}
