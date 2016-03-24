import derelict.sdl2.sdl;
import std.stdio;
import std.string;
import std.conv;
import network;
import protocol;
import gfx;
import misc;
import ui;

void main(string[] args){
	Init_Game();
	LocalClientName="lecom";
	string address=args.length>1 ? args[1] : "localhost";
	{
		int ret=Connect_To(address, 32887);
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
			if(ret.DataLength)
				On_Packet_Receive(ret);
		}
		Prepare_Render();
		Fill_Screen(null, 0);
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
}

void UnInit_Game(){
	UnInit_UI();
	UnInit_Gfx();
	UnInit_Netcode();
}
