import network;
import misc;
import protocol;
import std.conv;
import std.meta;

struct ClientVersionPacketLayout{
	uint client_version;
	string name;
}

struct ServerVersionPacketLayout{
	uint server_version;
	ubyte player_id;
}

struct MapChangePacketLayout{
	uint xsize, ysize, zsize;
	uint datasize;
	string mapname;
}
immutable ubyte MapChangePacketID=0;

struct MapChunkPacketLayout{
	string data; //Cast to ubyte
}
immutable ubyte MapChunkPacketID=1;

struct PlayerJoinPacketLayout{
	ubyte player_id;
	string name;
}
immutable ubyte PlayerJoinPacketID=2;

struct ChatMessagePacketLayout{
	uint color;
	string message;
}
immutable ubyte ChatPacketID=3;

struct PlayerDisconnectPacketLayout{
	ubyte player_id;
}
immutable ubyte DisconnectPacketID=4;

struct MapEnvironmentPacketLayout{
	uint fog_color;
	uint visibility_range;
}
immutable ubyte MapEnvironmentPacketID=5;


//This is one of the reasons why I chose D. I can simply write functions which automatically
//unpack received packets into structs and reverse byte order when needed.

union ArrayVariableAssignUnion(T){
	T variable;
	ubyte[T.sizeof] array;
}

T ConvertArrayToVariable(T)(ubyte[] array){
	ArrayVariableAssignUnion!(T) unionvar;
	if(EnableByteFlip)
		unionvar.array[]=array.reverse[];
	else
		unionvar.array[]=array[];
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
	if(EnableByteFlip && 0)
		ret=ret.reverse;
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
