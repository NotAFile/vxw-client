import derelict.enet.enet;
import std.stdio;
import std.string;
import misc;
version(LDC){
	import ldc_stdlib;
}

//Change this depending on your system's endianess
bool EnableByteFlip=true;

bool ServerDisconnected=false;

struct Connection_t{
	ENetHost *client;
	ENetPeer *peer;
	ENetAddress address;
	this(uint channels){
		client=enet_host_create(null, 1, channels, 0, 0);
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
					if(ret==1)
						writeflnlog("Connected to server!");
					else
						writeflnlog("[WARNING] ENet returned %d when trying to connect", ret);
					break;
				}
				case ENET_EVENT_TYPE_DISCONNECT:{
					writeflnlog("Server disconnected");
					ServerDisconnected=true;
					break;
				}
				default:{
					break;
				}
			}
			event.peer.data=cast(void*)toStringz("server");
		}
		else{
			writeflnlog("Couldn't connect to %s:%d", addr, port);
			if(addr!="localhost"){
				writeflnlog("Attempting to confirm server address and name...");
				char[256] addrbuf, namebuf;
				bool got_addr, got_name;
				got_addr=enet_address_get_host_ip(&address, addrbuf.ptr, addrbuf.length)>=0;
				got_name=enet_address_get_host(&address, namebuf.ptr, namebuf.length)>=0;
				if(got_addr || got_name){
					writeflnlog("Found server! [%s] (%s)", got_name ? fromStringz(namebuf.ptr) : "no name",
					got_addr ? fromStringz(addrbuf.ptr) : "no address");
					writeflnerr("Server probably misconfigured or crashed or wrong port");
				}
				else{
					writeflnerr("No such server found");
				}
			}
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
					ServerDisconnected=true;
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
		int ret=enet_host_service(client, &event, delay);
		if(ret>0){
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
					if(event.peer==peer){
						writeflnlog("Server disconnected");
						ServerDisconnected=true;
					}
					else{
						writeflnlog("Some peer disconnected: %s", *event.peer);
					}
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
		else
		if(ret<0){
			writeflnlog("Error: enet_host_service returned %d", ret);
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
	return connection.Connect(address, port, 5000, 69);
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
