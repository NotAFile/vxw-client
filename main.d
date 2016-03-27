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

void main(string[] args){
	Init_Game();
	ushort port; string address;
	if(args.length>1){
		LocalClientName=args[2];
		formattedRead(args[1], "vsc://%s:%u", &address, &port);
	}
	else{
		LocalClientName="Deuce";
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
	Send_Identification_Packet();
	while(!QuitGame){
		Check_Input();
		{
			auto ret=Update_Network();
			if(ret.data.length)
				On_Packet_Receive(ret);
		}
		Prepare_Render();
		Render_Screen();
		Render_HUD();
		Finish_Render();
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
