import derelict.sdl2.sdl;
import std.stdio;
import std.string;
import std.conv;
import std.format;
import core.memory;
import core.time;
import core.stdc.signal;
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

uint __gc_frame_counter=0;
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
	auto prev_t=PreciseClock();
	while(!QuitGame){
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
		Render_Screen();
		Finish_Render();
		auto current_t=PreciseClock();
		auto tdiff=current_t-prev_t;
		__gc_frame_counter++;
		if(Config_Read!int("fpscap")>0){
			auto target_delay=PreciseClock_DiffFromNSecs((cast(double)10e9)/(cast(double)Config_Read!int("fpscap")));
			if(tdiff<target_delay){
				auto wait_delay=target_delay-tdiff;
				PreciseClock_Wait(wait_delay);
			}
		}
		prev_t=PreciseClock();
		if(__gc_frame_counter>=600)
			__do_gc_collect();
	}
	Send_Disconnect_Packet();
	UnInit_Game();
	ClientConfig_Save();
	SDL_Quit();
}

void __do_gc_collect(){
	GC.collect();
	GC.minimize();
	__gc_frame_counter=0;
 }

void Init_Game(){
	Init_Netcode();
	Init_Gfx();
	Init_UI();
	Init_Script();
	version(DMD){
		signal(SIGSEGV, &SignalHandler);
	}
}

void UnInit_Game(){
	UnInit_UI();
	UnInit_Gfx();
	UnInit_Netcode();
}

version(DMD){
	extern(C) @nogc @system nothrow void SignalHandler(int signum){
		if(signum==SIGSEGV){
			SDL_SetRelativeMouseMode(SDL_FALSE);
			signal(SIGSEGV, SIG_DFL);
		}
	}
}
else{
	extern(C) @system nothrow void SignalHandler(int signum){
		if(signum==SIGSEGV){
			SDL_SetRelativeMouseMode(SDL_FALSE);
			signal(SIGSEGV, SIG_DFL);
		}
	}
}
