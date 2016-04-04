import derelict.sdl2.sdl;
import std.conv;
import std.algorithm;
import std.format;
import std.digest.crc;
import std.stdio;
import std.file;
import std.exception;
import std.math;
import std.string;
import network;
import renderer;
import packettypes;
import ui;
import misc;
import vector;
import world;
import gfx;

PlayerID_t LocalPlayerID;

string CurrentMapName;
bool LoadingMap=false;
uint MapLoadingSize=0;
uint MapTargetSize=0;

ubyte[] CurrentLoadingMap;

uint MapXSize, MapYSize, MapZSize;

uint Client_Version=1;

uint JoinedGameMaxPhases=4;
uint JoinedGamePhase=0;
bool JoinedGame;

struct ModFile_t{
	ubyte type;
	ushort index;
	string name;
	uint size;
	ubyte[] data;
	uint hash;
	bool receiving_data;
	this(string initname, uint initsize, ushort initindex, ubyte inittype){
		name=initname; size=initsize; index=initindex; type=inittype;
		hash=0; receiving_data=false;
	}
	void Loading_Finished(){
		receiving_data=false;
		string fname="./Ressources/"~name;
		try{
			File f=File(fname, "wb+");
			f.rawWrite(data);
			f.close();
		}
		catch(ErrnoException){
			writeflnerr("Couldn't open file %s for writing mod", fname);
		}
		data=[];
		switch(type){
			//On Linux, I probably could have used virtual files in RAM instead of physically re-loading them :d
			case 0:{
				SDL_Surface *fsrfc=SDL_LoadBMP(toStringz(fname));
				if(!fsrfc){writeflnerr("Couldn't load %s", fname); return;}
				SDL_Surface *srfc=SDL_ConvertSurfaceFormat(fsrfc, SDL_PIXELFORMAT_RGBA8888, 0);
				SDL_SetColorKey(srfc, SDL_TRUE, SDL_MapRGB(srfc.format, 255, 0, 255));
				SDL_Texture *tex=SDL_CreateTextureFromSurface(scrn_renderer, srfc);
				SDL_FreeSurface(srfc);
				SDL_FreeSurface(fsrfc);
				if(Mod_Pictures.length<=index)
					Mod_Pictures.length=index+1;
				Mod_Pictures[index]=tex;
				break;
			}
			case 1:{
				KV6Model_t *model=Load_KV6(fname);
				if(!model){
					writeflnerr("Couldn't load %s", fname);
					return;
				}
				if(Mod_Models.length<=index)
					Mod_Models.length=index+1;
				Mod_Models[index]=model;
				break;
			}
			default:{break;}
		}
	}
	bool LoadFromFile(){
		string fname="./Ressources/"~name;
		bool loaded_file=false;
		if(exists(fname)){
			if(isFile(fname) && !isDir(fname)){
				File f=File(fname);
				long lfsize=f.size();
				if(lfsize<int.max){
					data.length=cast(uint)lfsize;
					f.rawRead(data);
					ubyte[4] hashbuf=crc32Of(data);
					hash=*(cast(uint*)hashbuf.ptr);
					loaded_file=true;
					Loading_Finished();
					writeflnlog("Loaded %s from disk", fname);
				}
				else{
					writeflnerr("File %s is too large (%s)", fname, lfsize);
				}
				f.close();
			}
		}
		receiving_data=false;
		return loaded_file;
	}
	void Append_Data(ubyte[] append_data){
		if(!receiving_data){
			data=[];
			receiving_data=true;
		}
		data~=append_data[];
		if(data.length>=size){
			Loading_Finished();
			writeflnlog("Downloaded %s from server", name);
		}
		if(data.length>size){
			writeflnlog("Got more data than needed (%s/%s)? o.o", data.length, size);
			return;
		}
	}
}

ModFile_t[][] LoadingMods;

void Send_Identification_Packet(string requested_name){
	ClientVersionPacketLayout packet;
	packet.client_version=Client_Version;
	packet.name=requested_name;
	ubyte[] data=PackStructToPacket(packet);
	Send_Data(data);
}

void Send_Chat_Packet(string line){
	ChatMessagePacketLayout packet;
	packet.color=0;
	packet.message=line;
	ubyte[] data=PackStructToPacket(packet);
	Send_Data(ChatPacketID~data);
}

void On_Packet_Receive(ReceivedPacket_t recv_packet){
	if(JoinedGamePhase>=JoinedGameMaxPhases){
		ubyte id=(cast(ubyte[])recv_packet.data)[0];
		ubyte *contentptr=(cast(ubyte*)recv_packet.data)+1;
		uint packetlength=recv_packet.data.length;
		ubyte[] PacketData=cast(ubyte[])recv_packet.data[1..$];
		debug{
			writeflnlog("Received packet with ID %s", id);
		}
		switch(id){
			case MapChangePacketID:{
				auto packet=UnpackPacketToStruct!(MapChangePacketLayout)(PacketData);
				MapXSize=packet.xsize; MapYSize=packet.ysize; MapZSize=packet.zsize;
				MapTargetSize=packet.datasize;
				CurrentMapName=packet.mapname;
				WriteMsg(format("Loading map %s of size %d and dimensions %dx%dx%d", CurrentMapName, MapTargetSize, MapXSize, MapYSize, MapZSize),
				Font_SpecialColor);
				CurrentLoadingMap=[];
				break;
			}
			case MapChunkPacketID:{
				auto packet=UnpackPacketToStruct!(MapChunkPacketLayout)(PacketData);
				/*if(!packet.data.length)
					break;*/
				CurrentLoadingMap~=packet.data;
				WriteMsg(format("Received map chunk of size %d - (%d/%d)", packet.data.length, CurrentLoadingMap.length, MapTargetSize),
				Font_SpecialColor);
				if(CurrentLoadingMap.length==MapTargetSize)
					Load_Map(CurrentLoadingMap);
				break;
			}
			case PlayerJoinPacketID:{
				auto packet=UnpackPacketToStruct!(PlayerJoinPacketLayout)(PacketData);
				writeflnlog("Player #%d %s joined %s", packet.player_id, packet.name, Teams[packet.team_id].name);
				Init_Player(packet.name, packet.player_id);
				if(packet.player_id==LocalPlayerID)
					Join_Game();
				break;
			}
			case TeamDataPacketID:{
				auto packet=UnpackPacketToStruct!(TeamDataPacketLayout)(PacketData);
				Init_Team(packet.name, packet.team_id, packet.color);
				/*if(packet.team_id<3){
					//Hardcoded key handling
					//Somebody make a GUI please so I can remove the team limits
					WriteMsg(format(">>>>>>>PRESS %d TO JOIN %s TEAM<<<<<<<<", packet.team_id+1, packet.name), Teams[packet.team_id].icolor);
				}*/
				break;
			}
			case ChatPacketID:{
				auto packet=UnpackPacketToStruct!(ChatMessagePacketLayout)(PacketData);
				WriteMsg(packet.message, packet.color);
				break;
			}
			case DisconnectPacketID:{
				auto packet=UnpackPacketToStruct!(PlayerDisconnectPacketLayout)(PacketData);
				writeflnlog("Player with ID %d disconnected", packet.player_id);
				break;
			}
			case MapEnvironmentPacketID:{
				auto packet=UnpackPacketToStruct!(MapEnvironmentPacketLayout)(PacketData);
				Set_Fog(packet.fog_color, packet.visibility_range);
				break;
			}
			case ExistingPlayerPacketID:{
				auto packet=UnpackPacketToStruct!(ExistingPlayerPacketLayout)(PacketData);
				Init_Player(packet.name, packet.player_id);
				break;
			}
			case ModRequirementPacketID:{
				auto packet=UnpackPacketToStruct!(ModRequirementPacketLayout)(PacketData);
				string filename="Ressources/"~packet.path;
				ModFile_t mf=ModFile_t(packet.path, packet.size, packet.index, packet.type);
				if(LoadingMods.length<=packet.type)
					LoadingMods.length=packet.type+1;
				if(LoadingMods[packet.type].length<=packet.index)
					LoadingMods[packet.type].length=packet.index+1;
				LoadingMods[packet.type][packet.index]=mf;
				if(mf.LoadFromFile())
					packet.hash=mf.hash;
				auto packetbytes=PackStructToPacket(packet);
				Send_Packet(ModRequirementPacketID, packet);
				break;
			}
			case ModDataPacketID:{
				auto packet=UnpackPacketToStruct!(ModDataPacketLayout)(PacketData);
				LoadingMods[packet.type][packet.index].Append_Data(cast(ubyte[])packet.data);
				break;
			}
			case PlayerSpawnPacketID:{
				auto packet=UnpackPacketToStruct!(PlayerSpawnPacketLayout)(PacketData);
				Players[packet.player_id].Spawn(Vector3_t(packet.pos), packet.team_id);
				break;
			}
			case PlayerRotationPacketID:{
				auto packet=UnpackPacketToStruct!(PlayerRotationPacketLayout)(PacketData);
				//TODO: investigate why I have to do rotation.reverse here and fix
				packet.rotation.reverse;
				Players[packet.player_id].dir=Vector3_t(packet.rotation);
				if(packet.player_id==LocalPlayerID)
					CameraRot=Players[packet.player_id].dir.DirectionAsRotation;
				break;
			}
			case WorldUpdatePacketID:{
				ushort PlayersExisting;
				ubyte[2] PlayersExistingBytes=PacketData[0..2];
				if(EnableByteFlip)
					PlayersExistingBytes.reverse;
				PlayersExisting=*(cast(ushort*)PlayersExistingBytes.ptr);
				uint PlayerArraySize=(PlayersExisting/8)+(cast(int)((PlayersExisting%8)!=0));
				uint[] PlayerTable;
				uint plrindex=0;
				for(uint bytenum=0; bytenum<PlayerArraySize; bytenum++){
					for(uint nbit=0; nbit<8; nbit++){
						uint bit=1<<nbit;
						if(PacketData[bytenum+2]&bit){
							PlayerTable~=bytenum*8+nbit-1;
							plrindex++;
						}
					}
				}
				PlayerArraySize+=2;
				float[3][] positiondata=cast(float[3][])PacketData[PlayerArraySize+1..$];
				for(uint p=0; p<PlayerTable.length; p++){
					float[3] pos=positiondata[p];
					if(EnableByteFlip){
						foreach(ref coord;pos){
							ubyte[4] content=ConvertVariableToArray(coord);
							content.reverse;
							coord=ConvertArrayToVariable!(float)(content);
						}
					
					}
					uint player_id=PlayerTable[p];
					if(Players[player_id].player_id!=LocalPlayerID)
						Players[player_id].pos=Vector3_t(pos);
				}
				break;
			}
			case PlayerKeyEventPacketID:{
				auto packet=UnpackPacketToStruct!(PlayerKeyEventPacketLayout)(PacketData);
				ubyte keys=packet.keys;
				Player_t *plr=&Players[packet.player_id];
				plr.Go_Back=cast(bool)(keys&1);
				plr.Go_Forwards=cast(bool)(keys&2);
				plr.Go_Left=cast(bool)(keys&4);
				plr.Go_Right=cast(bool)(keys&8);
				plr.Jump=cast(bool)(keys&16);
				plr.Crouch=cast(bool)(keys&32);
				plr.KeysChanged=true;
				break;
			}
			case BindModelPacketID:{
				auto packet=UnpackPacketToStruct!(BindModelPacketLayout)(PacketData);
				Players[packet.player_id].Model=packet.model;
				break;
			}
			case PlayerPositionPacketID:{
				auto packet=UnpackPacketToStruct!(PlayerPositionPacketLayout)(PacketData);
				Players[LocalPlayerID].pos=Vector3_t(packet.position);
				break;
			}
			case WorldPhysicsPacketID:{
				auto packet=UnpackPacketToStruct!(WorldPhysicsPacketLayout)(PacketData);
				Gravity=packet.g; AirFriction=packet.airfriction; GroundFriction=packet.groundfriction;
				PlayerJumpPower=packet.player_jumppower; PlayerWalkSpeed=packet.player_walkspeed;
				WorldSpeedRatio=packet.world_speed*4.0;
				break;
			}
			case MenuElementPacketID:{
				auto packet=UnpackPacketToStruct!(MenuElementPacketLayout)(PacketData);
				if(packet.elementindex>=MenuElements.length)
					MenuElements.length=packet.elementindex+1;
				MenuElements[packet.elementindex].set(packet.picindex, packet.xpos, packet.ypos, packet.xsize, packet.ysize);
				break;
			}
			case ToggleMenuPacketID:{
				auto packet=UnpackPacketToStruct!(ToggleMenuPacketLayout)(PacketData);
				Set_Menu_Mode(cast(bool)packet.EnableMenu);
				break;
			}
			default:{
				writeflnlog("Invalid packet ID %d", id);
				break;
			}
		}
	}
	else{
		debug{
			writeflnlog("Received packet");
		}
		ubyte[] PacketData=recv_packet.data;
		switch(JoinedGamePhase){
			case 0:{
				auto packet=UnpackPacketToStruct!(ServerVersionPacketLayout)(PacketData);
				LocalPlayerID=packet.player_id;
				writeflnlog("Server version: %d, Player ID: %d", packet.server_version, LocalPlayerID);
				JoinedGamePhase=JoinedGameMaxPhases-1;
				break;
			}
			default:{break;}
		}
		JoinedGamePhase++;
	}
}

void Send_Disconnect_Packet(){
	ubyte[2] data=[DisconnectPacketID, 0];
	Send_Data(data.ptr, 2);
}

void Send_Packet(T)(PacketID_t id, T packet){
	auto packetbytes=PackStructToPacket(packet);
	Send_Data(id~packetbytes);
}

immutable float RotationDataSendDist=.01;
Vector3_t LastRotationDataSent=Vector3_t(0.0);
void Update_Rotation_Data(){
	float dist=(CameraRot-LastRotationDataSent).length;
	if(dist>RotationDataSendDist){
		PlayerRotationPacketLayout packet;
		packet.rotation=cast(float[3])Players[LocalPlayerID].dir;
		Send_Packet(PlayerRotationPacketID, packet);
		LastRotationDataSent=CameraRot;
	}
}

immutable float PositionDataSendDist=.05;
Vector3_t LastPositionDataSent=Vector3_t(0.0);
void Update_Position_Data(){
	float dist=(Players[LocalPlayerID].pos-LastPositionDataSent).length;
	if(dist>PositionDataSendDist && 0){
		PlayerPositionPacketLayout packet;
		packet.position=cast(float[3])Players[LocalPlayerID].pos;
		Send_Packet(PlayerPositionPacketID, packet);
		LastPositionDataSent=CameraRot;
	}
}

void Join_Team(TeamID_t team_id){
	PlayerJoinPacketLayout packet;
	packet.team_id=team_id;
	Send_Packet(PlayerJoinPacketID, packet);
}

bool Joined_Game(){
	if(!JoinedGame)
		return false;
	return Players[LocalPlayerID].InGame;
}

void Join_Game(){
	JoinedGame=true;
	Players[LocalPlayerID].InGame=true;
}

void Send_Key_Presses(ubyte keypresses){
	PlayerKeyEventPacketLayout packet;
	packet.keys=keypresses;
	Send_Packet(PlayerKeyEventPacketID, packet);
}

void Send_Mouse_Click(bool left_click, bool right_click, int xpos, int ypos){
	MouseClickPacketLayout packet;
	packet.clicks=(cast(uint)left_click)*(1<<0)+(cast(uint)right_click)*(1<<1);
	packet.xpos=cast(ushort)(cast(float)(xpos)*65535.0/cast(float)(scrn_surface.w));
	packet.ypos=cast(ushort)(cast(float)(ypos)*65535.0/cast(float)(scrn_surface.h));
	Send_Packet(MouseClickPacketID, packet);
}
