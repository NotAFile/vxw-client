import std.conv;
import network;
import packettypes;
import ui;
import misc;

string LocalClientName;
ubyte LocalPlayerID;

uint Client_Version=1;

uint JoinedGameMaxPhases=4;
uint JoinedGamePhase=0;

void Send_Identification_Packet(){
	ubyte[] data;
	data.length=Client_Version.sizeof;
	*(cast(typeof(&Client_Version))data)=Client_Version;
	data~=cast(ubyte[])LocalClientName;
	Send_Data(data.ptr, data.length);
}

void Send_Chat_Packet(string line){
	char[] packet=new char[](line.length+1);
	packet[0]=ChatPacketID; packet[1..$]=line;
	Send_Data(packet.ptr, packet.length);
}

void On_Packet_Receive(ReceivedPacket_t packet){
	if(JoinedGamePhase>=JoinedGameMaxPhases){
		ubyte id=*(cast(ubyte*)packet.data);
		ubyte *contentptr=(cast(ubyte*)packet.data)+1;
		uint packetlength=packet.DataLength-1;
		switch(id){
			case ConnectPacketID:{
				char[] namebuf=cast(char[])contentptr[1..packetlength];
				string playername=to!string(namebuf);
				writeflnlog("Player with ID %d (%s) joined", *contentptr, playername);
				break;
			}
			case ChatPacketID:{
				char[] msgbuf=cast(char[])contentptr[0..packetlength];
				WriteMsg(to!string(msgbuf));
				break;
			}
			case DisconnectPacketID:{
				writeflnlog("Player with ID %d disconnected", *contentptr);
				break;
			}
			default:{
				writeflnlog("Invalid packet ID %d", id);
				break;
			}
		}
	}
	else{
		switch(JoinedGamePhase){
			case 0:{
				uint ServerVersion=*(cast(uint*)packet.data);
				writeflnlog("Server version %d", ServerVersion);
				JoinedGamePhase=JoinedGameMaxPhases-1;
				ubyte LocalPlayerID=(cast(ubyte*)packet.data)[4];
				writeflnlog("Player ID: %d", LocalPlayerID);
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
