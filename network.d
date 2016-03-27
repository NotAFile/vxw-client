import derelict.enet.enet;
import std.stdio;
import std.string;
import misc;

//Change this depending on your system's endianess
bool EnableByteFlip=true;

struct Connection_t{
	ENetHost *client;
	ENetPeer *peer;
	ENetAddress address;
	this(uint channels){
		client=enet_host_create(null, 1, 2, 0, 0);
		if(!client){
			writeflnerr("Couldn't create ENet host");
			return;
		}
		enet_host_compress_with_range_coder(client);
	}
	int Connect(string addr, ushort port, uint connect_time, uint connection_byte){
		if(!client)
			return -1;
		enet_address_set_host(&address, toStringz(addr));
		address.port=port;
		peer=enet_host_connect(client, &address, 2, connection_byte);
		ENetEvent event;
		int ret=enet_host_service(client, &event, connect_time);
		if(ret>0){
			switch(event.type){
				case ENET_EVENT_TYPE_CONNECT:{
					writeflnlog("ENet returned %d when trying to connect", ret);
					break;
				}
				case ENET_EVENT_TYPE_DISCONNECT:{
					writeflnlog("Server disconnected");
					break;
				}
				default:{
					event.peer.data=cast(void*)toStringz("server");
				}
			}
		}
		else{
			writeflnlog("Couldn't connect to %s:%d", addr, port);
			enet_peer_reset(peer);
		}
		return ret;
	}
	int Disconnect(){
		enet_peer_disconnect(peer, 0);
		ENetEvent event;
		while(enet_host_service(client, &event, 5)>0){
			switch(event.type){
				case ENET_EVENT_TYPE_RECEIVE:{
					Clean_Packet(event.packet);
					break;
				}
				case ENET_EVENT_TYPE_DISCONNECT:{
					writeflnlog("Disconnected");
					break;
				}
				default:{
					writeflnlog("Received ENet event %s while disconnecting", event.type);
					break;
				}
			}
		}
		enet_peer_reset(peer);
		return 1;
	}
	ENetEvent Update(int delay){
		ENetEvent event;
		if(enet_host_service(client, &event, delay)){
			switch(event.type){
				case ENET_EVENT_TYPE_NONE:{
					return event;
				}
				case ENET_EVENT_TYPE_RECEIVE:{
					return event;
				}
				case ENET_EVENT_TYPE_CONNECT:{
					writeflnlog("%s connected", event.peer.data);
					break;
				}
				case ENET_EVENT_TYPE_DISCONNECT:{
					writeflnlog("%s disconnected", event.peer.data);
					event.peer.data=null;
					enet_peer_reset(peer);
					break;
				}
				default:{
					writeflnlog("ENet returned invalid event %d", event.type);
					break;
				}
			}
		}
		return cast(ENetEvent)0;
	}
	void Clean_Packet(ENetPacket *packet){
		enet_packet_destroy(packet);
	}
	int Send(ubyte[] data){
		ENetPacket *packet=enet_packet_create(cast(void*)data.ptr, data.length, ENET_PACKET_FLAG_RELIABLE);
		int ret=enet_peer_send(peer, 0, packet);
		enet_host_flush(client);
		return ret;
	}
	/*~this(){
		enet_host_destroy(client);
	}*/
}

void Init_Netcode(){
	DerelictENet.load();
	int ret=enet_initialize();
	if(ret!=0){
		writeflnerr("Couldn't initialize ENet (%d)", ret);
		return;
	}
	connection=Connection_t(2);
}

void UnInit_Netcode(){
	enet_deinitialize();
}

Connection_t connection;

int Connect_To(string address, ushort port){
	return connection.Connect(address, port, 1000, 1);
}

int Disconnect(){
	return connection.Disconnect();
}

int Send_Data(T)(T *data, uint size){
	return connection.Send((cast(ubyte*)data)[0..size]);
}

int Send_Data(T)(T data){
	return connection.Send(cast(ubyte[])data);
}

struct ReceivedPacket_t{
	uint ConnectionID;
	ubyte[] data;
	this(uint connect_id, void *recvdata, uint datalen){
		data=(cast(ubyte*)recvdata)[0..datalen];
		ConnectionID=connect_id;
	}
	this(bool something){
		if(!something){
			ConnectionID=0;
			data.length=0;
		}
	}
}

ReceivedPacket_t Update_Network(){
	ENetEvent event=connection.Update(0);
	if(event.type==ENET_EVENT_TYPE_RECEIVE)
		return ReceivedPacket_t(event.peer.connectID, event.packet.data, event.packet.dataLength);
	return ReceivedPacket_t(0);
}
