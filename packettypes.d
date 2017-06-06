import network;
import misc;
import protocol;
import std.conv;
version(LDC){
	import ldc_stdlib;
}
version(GNU){
	import gdc_stdlib;
}

alias PlayerID_t=ubyte; immutable PlayerID_t VoidPlayerID=255;
alias PacketID_t=ubyte;
alias TeamID_t=ubyte;
alias ModelID_t=ubyte; immutable ModelID_t VoidModelID=255;
alias SoundID_t=ubyte; immutable SoundID_t VoidSoundID=255;
alias ObjectID_t=ushort; immutable ObjectID_t VoidObjectID=65535;
alias ItemID_t=ubyte; immutable ItemID_t VoidItemID=255;
alias ItemTypeID_t=ubyte; immutable ItemTypeID_t VoidItemTypeID=255;

struct ClientVersionPacketLayout{
	uint Protocol_Version;
	string name;
}

struct ServerVersionPacketLayout{
	ubyte may_connect;
	uint server_version;
	uint ping_delay;
	PlayerID_t player_id;
}

struct ServerConnectionDenyPacketLayout{
	ubyte may_connect;
	string reason;
}

enum DataEncodingTypes{
	raw=0, gzip=1
}

//TODO: Make an array/enum/sth out of all these packets; D can do lots of wonderful things in that direction
//NOTE: Importance approved
struct MapChangePacketLayout{
	uint xsize, ysize, zsize;
	uint datasize;
	ubyte encoding;
	string mapname;
}
immutable PacketID_t MapChangePacketID=0;

//NOTE: Importance approved
struct MapChunkPacketLayout{
	string data;
}
immutable PacketID_t MapChunkPacketID=1;

//NOTE: Importance approved
struct PlayerJoinPacketLayout{
	PlayerID_t player_id;
	string name;
}
immutable PacketID_t PlayerJoinPacketID=2;

//NOTE: Importance approved
struct ChatMessagePacketLayout{
	uint color;
	string message;
}
immutable PacketID_t ChatPacketID=3;

//NOTE: Importance approved
struct PlayerDisconnectPacketLayout{
	PlayerID_t player_id;
	string reason;
}
immutable PacketID_t PlayerDisconnectPacketID=4;

//NOTE: Importance: meh
struct MapEnvironmentPacketLayout{
	uint fog_color;
	uint visibility_range;
	float base_blur;
	float base_shake;
	float blur_decay, shake_decay;
}
immutable PacketID_t MapEnvironmentPacketID=5;

//NOTE: No idea what this is even for
struct ExistingPlayerPacketLayout{
	PlayerID_t player_id;
	string name;
}
immutable PacketID_t ExistingPlayerPacketID=6;

//Client behaviour: Client initializes a mod structure (necessary). A copy of that packet is sent back, with hash changed if client could calculate it
//Server behaviour: Should send this first each time a mod is sent to the client. On receiving, server compares the hash and sends ModData when needed
//NOTE: Importance approved
struct ModRequirementPacketLayout{
	ubyte type;
	ushort index;
	uint hash;
	uint size;
	string path;
}
immutable PacketID_t ModRequirementPacketID=7;

//NOTE: Importance approved
struct ModDataPacketLayout{
	ubyte type;
	ushort index;
	string data;
}
immutable PacketID_t ModDataPacketID=8;

//NOTE: Importance approved
//(creates a player world object in comparison to the player join packet, which just notifies of a new unjoined player)
struct PlayerSpawnPacketLayout{
	PlayerID_t player_id;
	TeamID_t team_id;
	float xpos, ypos, zpos;
}
immutable PacketID_t PlayerSpawnPacketID=9;

//NOTE: Importance unsure: could be done by scripts? (Far far future)
struct TeamDataPacketLayout{
	TeamID_t team_id;
	uint col;
	ubyte flags;
	string name;
}
immutable PacketID_t TeamDataPacketID=10;

enum TeamDataPacketFlags{
	NonPlaying=(1<<0)
}

//NOTE: Importance approved
//NOTE: You can never compress this one enough
struct PlayerRotationPacketLayout{
	PlayerID_t player_id;
	float xrot, yrot, zrot;
}
immutable PacketID_t PlayerRotationPacketID=11;

//NOTE: Importance approved
//NOTE: You can never compress this one enough
immutable PacketID_t WorldUpdatePacketID=12;

//WIP and TEMPORARY-ONLY packet. This will be removed and replaced by key press handling in future.
//This only exists for testing the physics and to quickly create a game from the engine
struct PlayerKeyEventPacketLayout{
	PlayerID_t player_id;
	ushort keys;
}
immutable PacketID_t PlayerKeyEventPacketID=13;

//Deprecated and unused
struct BindModelPacketLayout{
	PlayerID_t player_id;
	ushort model;
	ushort arm_model;
	ushort gun_model;
}
immutable PacketID_t BindModelPacketID=14;

//NOTE: Importance approved
//NOTE: You can never compress this one enough
struct PlayerPositionPacketLayout{
	float xpos, ypos, zpos;
}
immutable PacketID_t PlayerPositionPacketID=15;

enum WorldPhysicsPacketFlags{
	FallingBlocks=(1<<0)
}

//NOTE: Importance is meh, once we will have a scripted engine instead of hardcoded one,
//we can remove this
struct WorldPhysicsPacketLayout{
	float g, airfriction, groundfriction, waterfriction, crouchfriction, player_jumppower, player_walkspeed, player_sprintspeed, world_speed;
	ubyte flags;
}
immutable PacketID_t WorldPhysicsPacketID=16;

//NOTE: Is way better off being done by scripts (sending every tiny detail sux)
struct MenuElementPacketLayout{
	ubyte elementindex;
	ubyte picindex;
	ubyte zval;
	ubyte transparency;
	float xpos, ypos;
	float xsize, ysize;
}
immutable PacketID_t MenuElementPacketID=17;

//NOTE: See above
struct ToggleMenuPacketLayout{
	ubyte EnableMenu;
}
immutable PacketID_t ToggleMenuPacketID=18;

//NOTE: Will be modified/removed with the introduction of scripts
struct MouseClickPacketLayout{
	ubyte clicks;
	ushort xpos, ypos;
}
immutable PacketID_t MouseClickPacketID=19;

struct PlayerHitPacketLayout{
	PlayerID_t player_id;
	ubyte hit_sprite;
}
immutable PacketID_t PlayerHitPacketID=20;

enum ItemTypeFlags : ubyte{
	Weapon=1<<0, RepeatedUse=1<<1, ShowPalette=1<<2, ColorMod=1<<3, AltAni=1<<4
};

enum{
	ITEMTYPE_FLAGS_WEAPON=(1<<0), ITEMTYPE_FLAGS_REPEATEDUSE=(1<<1), ITEMTYPE_FLAGS_SHOWPALETTE=(1<<2), ITEMTYPE_FLAGS_COLORMOD=(1<<3)
};

//NOTE: TODO: Scripted weapons and throw this out
struct ItemTypePacketLayout{
	ItemID_t item_id;
	ushort use_delay;
	uint maxamount1, maxamount2;
	float spread_c, spread_m;
	float recoil_xc, recoil_xm;
	float recoil_yc, recoil_ym;
	ubyte block_damage;
	short use_range;
	float power;
	float cooling;
	ItemTypeFlags typeflags;
	ModelID_t model_id;
	ModelID_t bullet_model_id;
	SoundID_t use_sound_id;
}
immutable PacketID_t ItemTypePacketID=21;

//NOTE: TODO: Scripted items and throw this out
struct ItemReloadPacketLayout{
	ubyte item_id;
	uint amount1, amount2;
}
immutable PacketID_t ItemReloadPacketID=22;

//NOTE: Maybe let this
struct ToolSwitchPacketLayout{
	PlayerID_t player_id;
	ubyte tool_id;
}
immutable PacketID_t ToolSwitchPacketID=23;

//NOTE: Script this and throw this out
struct BlockBreakPacketLayout{
	PlayerID_t player_id;
	ubyte break_type;
	ushort x, y, z;
}
immutable PacketID_t BlockBreakPacketID=24;

struct SetPlayerColorPacketLayout{
	PlayerID_t player_id;
	uint color;
}
immutable PacketID_t SetPlayerColorPacketID=25;

//NOTE: Script this and throw this out
struct BlockBuildPacketLayout{
	PlayerID_t player_id;
	ubyte build_type;
	ushort x, y, z;
}
immutable PacketID_t BlockBuildPacketID=26;

immutable PacketID_t PlayerItemsPacketID=27;

enum{
	TEXTBOX_FLAG_WRAP=(1<<0), TEXTBOX_FLAG_MOVELINESDOWN=(1<<1), TEXTBOX_FLAG_MOVELINESUP=(1<<2)
};

struct SetTextBoxPacketLayout{
	ubyte box_id;
	float xpos, ypos;
	float xsize, ysize;
	float xsizeratio, ysizeratio;
	ubyte fontpic;
	ubyte flags;
}
immutable PacketID_t SetTextBoxPacketID=28;

struct SetTextBoxTextPacketLayout{
	ubyte box_id;
	uint color;
	ubyte line;
	string text;
}
immutable PacketID_t SetTextBoxTextPacketID=29;

enum SetObjectFlags{
	Solid=(1<<0), ModelModification=(1<<1), BulletHoles=(1<<2), SendHits=(1<<3)
}

struct SetObjectPacketLayout{
	ushort obj_id;
	ubyte model_id;
	ubyte minimap_img;
	ubyte flags;
	uint color;
	float weightfactor;
	float bouncefactor;
	float frictionfactor;
}
immutable PacketID_t SetObjectPacketID=30;

struct SetObjectPosPacketLayout{
	ushort obj_id;
	float x, y, z;
}
immutable PacketID_t SetObjectPosPacketID=31;

struct SetObjectVelPacketLayout{
	ushort obj_id;
	float x, y, z;
}
immutable PacketID_t SetObjectVelPacketID=32;

struct SetObjectRotPacketLayout{
	ushort obj_id;
	float x, y, z;
}
immutable PacketID_t SetObjectRotPacketID=33;

struct SetObjectDensityPacketLayout{
	ushort obj_id;
	float x, y, z;
}
immutable PacketID_t SetObjectDensityPacketID=34;

struct ExplosionEffectPacketLayout{
	float xpos, ypos, zpos;
	float xvel, yvel, zvel;
	float radius;
	float spread;
	uint amount;
	uint col;
}
immutable PacketID_t ExplosionEffectPacketID=35;

struct ChangeFOVPacketLayout{
	float xfov, yfov;
}
immutable PacketID_t ChangeFOVPacketID=36;

//Sent_Image is deprecated
enum AssignBuiltinTypes : ubyte{
	Model=0, Picture=1, Sent_Image=2, Sound=3, MenuElement=Sent_Image
}

enum AssignBuiltinModelTypes{
	BlockBuild_Wireframe=0, Bullet_Tracer=1
}

enum AssignBuiltinPictureTypes{
	Font=0
}

enum AssignBuiltinSentImageTypes{
	AmmoCounterBG=0, AmmoCounterBullet=1, Palette_HBorder=2, Palette_HFG=3, Palette_VBorder=4, Palette_VFG=5, ScopeGfx=6
}
alias AssignBuiltinMenuElementTypes=AssignBuiltinSentImageTypes;

enum AssignBuiltinSoundTypes{
	Step=0, Explosion=1, Block_Break=2
}

struct AssignBuiltinPacketLayout{
	ubyte type;
	ubyte target;
	ubyte index;
}
immutable PacketID_t AssignBuiltinPacketID=37;

immutable PacketID_t SetObjectVerticesPacketID=38;

enum SetPlayerModelPacketFlags{
	NonFirstPersonModel=(1<<0), RotateModel=(1<<1)
}

//WIP
struct SetPlayerModelPacketLayout{
	PlayerID_t player_id;
	ubyte playermodelindex, modelfileindex;
	float xsize, ysize, zsize;
	float xoffset, yoffset, zoffset;
	float xrot, yrot, zrot;
	ubyte flags;
	float walk_rotate;
}
immutable PacketID_t SetPlayerModelPacketID=39;

immutable PacketID_t PingPacketID=40;

struct SetPlayerModePacketLayout{
	PlayerID_t player_id;
	ubyte mode;
}

immutable PacketID_t SetPlayerModePacketID=41;

struct SetBlurPacketLayout{
	float blur;
}

immutable PacketID_t SetBlurPacketID=42;

struct SetShakePacketLayout{
	float shake;
}

immutable PacketID_t SetShakePacketID=43;

enum ToggleScriptPacketFlags{
	Run=(1<<0), Repeat=(1<<1), MiniMap_Renderer=(1<<2)
}

struct ToggleScriptPacketLayout{
	ushort index;
	ubyte flags;
}

immutable PacketID_t ToggleScriptPacketID=44;

struct CustomScriptPacketLayout{
	ushort scr_index;
	string data;
}

immutable PacketID_t CustomScriptPacketID=45;

struct SetObjectAclPacketLayout{
	ushort obj_id;
	float x, y, z;
}
immutable PacketID_t SetObjectAclPacketID=46;

struct ObjectHitPacketLayout{
	ushort object_index;
}
immutable PacketID_t ObjectHitPacketID=47;

struct SetScorePacketLayout{
	PlayerID_t player_id;
	int score;
}
immutable PacketID_t SetScorePacketID=48;

struct PublicPlayerMouseClickPacketLayout{
	PlayerID_t player_id;
	ubyte mouse_clicks;
}
immutable PacketID_t PublicPlayerMouseClickPacketID=49;

struct RunScriptPacketLayout{
	string script;
}
immutable PacketID_t RunScriptPacketID=50;

//Standard = hardcoded physics; Scripted = hardcoded physics + script hook called
//Full_Scripted = script hook called + only collision code (fdeltapos = movement vector)
//Script_Override = no hardcoded physics and object update call = only script hook call
enum ObjectPhysicsMode{
	Standard=0, Scripted=1, Full_Scripted=2, Script_Override=3
}

struct SetObjectPhysicsPacketLayout{
	ObjectID_t obj_id;
	ubyte physics_mode;
	ubyte script;
}
immutable PacketID_t SetObjectPhysicsPacketID=51;


struct SetGMScorePacketLayout{
	PlayerID_t player_id;
	int score;
}
immutable PacketID_t SetGMScorePacketID=52;

enum ProtocolPlaySoundFlags : ubyte{
	Repeat=(1<<0), Stop=(1<<1)
}

struct PlaySoundPacketLayout{
	float xpos, ypos, zpos;
	ubyte volume;
	SoundID_t sound;
}
immutable PacketID_t PlaySoundPacketID=53;

struct SetObjectSmokePacketLayout{
	ObjectID_t obj_id;
	float amount;
	uint color;
}
immutable PacketID_t SetObjectSmokePacketID=54;

enum ObjectAttachmentFlags : ubyte{
	FreeRotation=(1<<0)
}

struct SetObjectAttachmentPacketLayout{
	ObjectID_t obj_id;
	ObjectID_t attached_to_obj;
	float xoffset, yoffset, zoffset;
	ObjectAttachmentFlags flags;
}
immutable PacketID_t SetObjectAttachmentPacketID=55;

struct AssignObjectItemPacketLayout{
	ObjectID_t obj_id;
	ItemTypeID_t itemtype_id;
}
immutable PacketID_t AssignObjectItemPacketID=56;

struct EquipObjectItemPacketLayout{
	PlayerID_t player_id;
	ObjectID_t obj_id;
}
immutable PacketID_t EquipObjectItemPacketID=57;

struct SetObjectSoundPacketLayout{
	ObjectID_t obj_id;
	SoundID_t snd_id;
	ProtocolPlaySoundFlags flags;
}

immutable PacketID_t SetObjectSoundPacketID=58;

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
		proper_reverse_overwrite(unionvar.array);
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
		proper_reverse_overwrite(ret);
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
