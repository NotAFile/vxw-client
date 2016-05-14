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

uint TargetFPS=30;

void main(string[] args){
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
		requested_name="Deuce";
		address="localhost";
		port=32887;
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
		uint t1=SDL_GetTicks(), t2;
		Check_Input();
		while(true){
			auto ret=Update_Network();
			if(ret.data.length)
				On_Packet_Receive(ret);
			else
				break;
		}
		Update_World();
		Prepare_Render();
		Render_Screen();
		Finish_Render();
		t2=SDL_GetTicks();
		uint tdiff=t2-t1;
		if(tdiff<1000/TargetFPS)
			SDL_Delay(1000/TargetFPS-tdiff);
	}
	Send_Disconnect_Packet();
	UnInit_Game();
}

void Init_Game(){
	Init_Netcode();
	Init_Gfx();
	Init_UI();
	Init_Renderer();
}

void UnInit_Game(){
	UnInit_Renderer();
	UnInit_UI();
	UnInit_Gfx();
	UnInit_Netcode();
}
