import std.conv;
import std.format;
import network;
import renderer;
import packettypes;
import ui;
import misc;

string LocalClientName;
ubyte LocalPlayerID;

string CurrentMapName;
bool LoadingMap=false;
uint MapLoadingSize=0;
uint MapTargetSize=0;

ubyte[] CurrentLoadingMap;

uint MapXSize, MapYSize, MapZSize;

uint Client_Version=1;

uint JoinedGameMaxPhases=4;
uint JoinedGamePhase=0;
bool JoinedGame=false;

void Send_Identification_Packet(){
	ClientVersionPacketLayout packet;
	packet.client_version=Client_Version;
	packet.name=LocalClientName;
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
		switch(id){
			case MapChangePacketID:{
				auto packet=UnpackPacketToStruct!(MapChangePacketLayout)(PacketData);
				MapXSize=packet.xsize; MapYSize=packet.ysize; MapZSize=packet.zsize;
				MapTargetSize=packet.datasize;
				CurrentMapName=packet.mapname;
				WriteMsg(format("Loading map %s of size %d and dimensions %dx%dx%d", CurrentMapName, MapTargetSize, MapXSize, MapYSize, MapZSize),
				0x00000000);
				CurrentLoadingMap=[];
				break;
			}
			case MapChunkPacketID:{
				auto packet=UnpackPacketToStruct!(MapChunkPacketLayout)(PacketData);
				if(!packet.data.length)
					break;
				CurrentLoadingMap~=packet.data;
				WriteMsg(format("Received map chunk of size %d - (%d/%d)", packet.data.length, CurrentLoadingMap.length, MapTargetSize),
				0x00000000);
				if(CurrentLoadingMap.length==MapTargetSize)
					Load_Map(CurrentLoadingMap);
				break;
			}
			case PlayerJoinPacketID:{
				auto packet=UnpackPacketToStruct!(PlayerJoinPacketLayout)(PacketData);
				writeflnlog("Player with ID %d (%s) joined", packet.player_id, packet.name);
				if(packet.player_id==LocalPlayerID)
					JoinedGame=true;
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
				if(packet.player_id==LocalPlayerID)
					JoinedGame=false;
				break;
			}
			case MapEnvironmentPacketID:{
				auto packet=UnpackPacketToStruct!(MapEnvironmentPacketLayout)(PacketData);
				Set_Fog(packet.fog_color, packet.visibility_range);
				break;
			}
			default:{
				writeflnlog("Invalid packet ID %d", id);
				break;
			}
		}
	}
	else{
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
