import network;
import misc;
import protocol;
import std.conv;
import std.meta;

alias PlayerID_t=ubyte;
alias PacketID_t=ubyte;
alias TeamID_t=ubyte;

struct ClientVersionPacketLayout{
	uint client_version;
	string name;
}

struct ServerVersionPacketLayout{
	uint server_version;
	PlayerID_t player_id;
}

struct MapChangePacketLayout{
	uint xsize, ysize, zsize;
	uint datasize;
	string mapname;
}
immutable PacketID_t MapChangePacketID=0;

struct MapChunkPacketLayout{
	string data; //Cast to ubyte
}
immutable PacketID_t MapChunkPacketID=1;

struct PlayerJoinPacketLayout{
	PlayerID_t player_id;
	TeamID_t team_id;
	string name;
}
immutable PacketID_t PlayerJoinPacketID=2;

struct ChatMessagePacketLayout{
	uint color;
	string message;
}
immutable PacketID_t ChatPacketID=3;

struct PlayerDisconnectPacketLayout{
	PlayerID_t player_id;
}
immutable PacketID_t DisconnectPacketID=4;

struct MapEnvironmentPacketLayout{
	uint fog_color;
	uint visibility_range;
}
immutable PacketID_t MapEnvironmentPacketID=5;

struct ExistingPlayerPacketLayout{
	PlayerID_t player_id;
	string name;
}
immutable PacketID_t ExistingPlayerPacketID=6;

//Client behaviour: Client initializes a mod structure (necessary). A copy of that packet is sent back, with hash changed if client could calculate it
//Server behaviour: Should send this first each time a mod is sent to the client. On receiving, server compares the hash and sends ModData when needed
struct ModRequirementPacketLayout{
	ubyte type;
	ushort index;
	uint hash;
	uint size;
	string path;
}
immutable PacketID_t ModRequirementPacketID=7;

struct ModDataPacketLayout{
	ubyte type;
	ushort index;
	string data;
}
immutable PacketID_t ModDataPacketID=8;

struct PlayerSpawnPacketLayout{
	PlayerID_t player_id;
	TeamID_t team_id;
	float[3] pos;
}
immutable PacketID_t PlayerSpawnPacketID=9;

struct TeamDataPacketLayout{
	TeamID_t team_id;
	ubyte[4] color;
	string name;
}
immutable PacketID_t TeamDataPacketID=10;

struct PlayerRotationPacketLayout{
	PlayerID_t player_id;
	float[3] rotation;
}
immutable PacketID_t PlayerRotationPacketID=11;

immutable PacketID_t WorldUpdatePacketID=12;

//WIP and TEMPORARY-ONLY packet. This will be removed and replaced by key press handling in future.
//This only exists for testing the physics and to quickly create a game from the engine
struct PlayerKeyEventPacketLayout{
	PlayerID_t player_id;
	ubyte keys;
}
immutable PacketID_t PlayerKeyEventPacketID=13;

struct BindModelPacketLayout{
	PlayerID_t player_id;
	ushort model;
}
immutable PacketID_t BindModelPacketID=14;

struct PlayerPositionPacketLayout{
	float[3] position;
}
immutable PacketID_t PlayerPositionPacketID=15;

struct WorldPhysicsPacketLayout{
	float g, airfriction, groundfriction, player_jumppower, player_walkspeed, world_speed;
}
immutable PacketID_t WorldPhysicsPacketID=16;

struct MenuElementPacketLayout{
	ubyte elementindex;
	ubyte picindex;
	float xpos, ypos;
	float xsize, ysize;
}
immutable PacketID_t MenuElementPacketID=17;

struct ToggleMenuPacketLayout{
	ubyte EnableMenu;
}
immutable PacketID_t ToggleMenuPacketID=18;

struct MouseClickPacketLayout{
	ubyte clicks;
	ushort xpos, ypos;
}
immutable PacketID_t MouseClickPacketID=19;

//This is one of the reasons why I chose D. I can simply write functions which automatically
//unpack received packets into structs and reverse byte order when needed (byte order is the reason why I can't simply lay struct ptrs over packets)

union ArrayVariableAssignUnion(T){
	T variable;
	ubyte[T.sizeof] array;
}

T ConvertArrayToVariable(T)(ubyte[] array){
	ArrayVariableAssignUnion!(T) unionvar;
	unionvar.array[]=array[];
	if(EnableByteFlip)
		unionvar.array.reverse;
	return unionvar.variable;
}

T UnpackPacketToStruct(T)(ubyte[] data){
	T newobj;
	enum members=__traits(derivedMembers, T);
	uint index=0;
	foreach(member; members){
		static if(__traits(compiles, typeof(__traits(getMember, newobj, member)))){
			static if(!is(typeof(__traits(getMember, newobj, member)) == function)){
				static if(is(typeof(__traits(getMember, newobj, member)) == string)){
					__traits(getMember, newobj, member)=to!string(cast(char[])data[index..$]);
					break;
				}
				uint size=__traits(getMember, newobj, member).sizeof;
				__traits(getMember, newobj, member)=ConvertArrayToVariable!(typeof(__traits(getMember, newobj, member)))(data[index..(index+size)]);
				index+=size;
			}
		}
	}
	return newobj;
}

ubyte[] ConvertVariableToArray(T)(T var){
	ArrayVariableAssignUnion!(T) unionvar;
	unionvar.variable=var;
	ubyte[] ret;
	ret.length=T.sizeof;
	ret[]=unionvar.array[];
	if(EnableByteFlip)
		ret.reverse;
	return ret;
}

ubyte[] PackStructToPacket(T)(T packetobj){
	ubyte[] data;
	enum members=__traits(derivedMembers, T);
	foreach(member; members){
		static if(__traits(compiles, typeof(__traits(getMember, packetobj, member)))){
			static if(!is(typeof(__traits(getMember, packetobj, member)) == function)){
				static if(is(typeof(__traits(getMember, packetobj, member)) == string)){
					data~=__traits(getMember, packetobj, member);
					break;
				}
				ubyte[] arr=ConvertVariableToArray!(typeof(__traits(getMember, packetobj, member)))(__traits(getMember, packetobj, member));
				data~=arr;
			}
		}
	}
	return data;
}
