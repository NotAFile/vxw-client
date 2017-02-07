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

string[string] ClientConfig;

version(OSX){
	//Ew why would an intelligent non-pleb even use this shit
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

T Config_Read(T)(string entry){
	if(!(entry in ClientConfig)){
		writeflnerr("Missing client config entry %s", entry);
		return T.init;
	}
	return to!T(ClientConfig[entry]);
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
		ClientConfig["upscale"]="false";
		ClientConfig["smoke"]="true";
		ClientConfig["fpscap"]="60";
		ClientConfig["last_addr"]="localhost";
		ClientConfig["last_port"]="32887";
		ClientConfig.rehash();
		return;
	}
	auto f=File("./config.txt", "r");
	string line;
	while((line=f.readln())!=null){
		string entry_name, entry_content;
		int eqpos=line.indexOf('=');
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
