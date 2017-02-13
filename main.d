import derelict.sdl2.sdl;
import std.stdio;
import std.string;
import std.conv;
import std.format;
import network;
import protocol;
import gfx;
import misc;
import ui;
import renderer;
import vector;
import world;
import script;
version(LDC){
	import ldc_stdlib;
}

version(OSX){
	//Ew why would an intelligent being even use this shit
	static assert(0);
}

void main(string[] args){
	ClientConfig_Load();
	Init_Game();
	ushort port; string address;
	string requested_name;
	if(args.length>1 && args.length<3){
		UnInit_Game();
		writeflnlog("Usage: ./main <address:port> <nick>");
		writeflnlog("Or ./main to connect to localhost as Deuce");
		writeflnlog("You can use DNS names without protocol identifiers (without \"http://\" or \"https://\")");
		return;
	}
	if(args.length>1){
		requested_name=args[2];
		formattedRead(args[1], "%s:%u", &address, &port);
	}
	else{
		requested_name=ClientConfig["nick"];
		address=ClientConfig["last_addr"];
		port=to!ushort(ClientConfig["last_port"]);
	}
	{
		int ret=Connect_To(address, port);
		if(ret<=0){
			writeflnlog("Error code: %d", ret);
			UnInit_Game();
			return;
		}
	}
	Send_Identification_Packet(requested_name);
	while(!QuitGame){
		uint t_before_frame=SDL_GetTicks();
		Check_Input();
		while(true){
			auto ret=Update_Network();
			QuitGame|=ServerDisconnected;
			if(ret.data.length)
				On_Packet_Receive(ret);
			else
				break;
		}
		Script_OnFrame();
		Update_World();
		uint t_after_update=SDL_GetTicks();
		Render_Screen();
		Finish_Render();
		uint t_after_rendering=SDL_GetTicks();
		uint tdiff=t_after_rendering-t_before_frame;
		if(Config_Read!int("fpscap")>0){
			if(tdiff<1000/Config_Read!uint("fpscap"))
				SDL_Delay(1000/Config_Read!uint("fpscap")-tdiff);
		}
		//writeflnlog("%s %s", t_after_rendering-t_after_update, t_after_update-t_before_frame);
	}
	Send_Disconnect_Packet();
	UnInit_Game();
	ClientConfig_Save();
}

void Init_Game(){
	Init_Netcode();
	Init_Gfx();
	Init_UI();
	Init_Script();
}

void UnInit_Game(){
	UnInit_UI();
	UnInit_Gfx();
	UnInit_Netcode();
}
