import sdl2;
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
import snd;
version(LDC){
	import ldc_stdlib;
}

version(OSX){
	pragma(msg, "No. Just no.");
	static assert(0);
}

uint __gc_frame_counter=0;
void main(string[] args){
	ClientConfig_Load();
	Init_Game();
	ushort port; string address;
	string requested_name=ClientConfig["nick"];
	{
		switch(args.length){
			case 1:{
				address=ClientConfig["last_addr"];
				port=to!ushort(ClientConfig["last_port"]);
				break;
			}
			case 2:{
				import std.string;
				if(args[1].indexOf(':')>0){
					formattedRead(args[1], "%s:%u", &address, &port);
				}
				else{
					address=args[1];
					port=32887;
				}
				break;
			}
			case 3:{
				requested_name=args[2];
				goto case 2;
				break;
			}
			default:{
				writeflnlog("Usage: ./main <address:port> <nick>");
				writeflnlog("Or ./main to connect to the address with the nickname defined in config.txt (or default)");
				writeflnlog("You can use DNS names without any protocol identifiers (without \"http://\" or \"https://\")");
				UnInit_Game();
				return;
				break;
			}
		}
	}
	{
		SDL_SetWindowTitle(scrn_window, toStringz("[VoxelWar] Connecting to "~address~":"~to!string(port)));
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
}

void __do_gc_collect(){
	GC.collect();
	GC.minimize();
	__gc_frame_counter=0;
 }

void Init_Game(){
	Init_Netcode();
	Init_Gfx();
	Init_Snd();
	Init_UI();
	Init_Script();
	Init_World();
	signal(SIGSEGV, &SignalHandler);
}

void UnInit_Game(){
	UnInit_World();
	UnInit_UI();
	UnInit_Gfx();
	UnInit_Snd();
	UnInit_Netcode();
	ClientConfig_Save();
	SDL_Quit();
}

bool got_sigsegv=false;
version(GNU){
	extern(C) @system nothrow void SignalHandler(int signum){
		if(signum==SIGSEGV && !got_sigsegv){
			got_sigsegv=true;
			SDL_SetRelativeMouseMode(SDL_FALSE);
			signal(SIGSEGV, SIG_DFL);
		}
	}
}
else{
	extern(C) @nogc @system nothrow void SignalHandler(int signum){
		if(signum==SIGSEGV && !got_sigsegv){
			got_sigsegv=true;
			SDL_SetRelativeMouseMode(SDL_FALSE);
			signal(SIGSEGV, SIG_DFL);
		}
	}
}
