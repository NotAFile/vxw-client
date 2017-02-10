version(LDC){
	import ldc_stdlib;
}
version(GNU){
	import gdc_stdlib;
}
import derelict.sdl2.sdl;
import derelict.sdl2.image;
import std.conv;
import std.algorithm;
import std.format;
import std.digest.crc;
import std.stdio;
import std.file;
import std.path;
import std.array;
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
import script;
version(DMD){
	import std.meta;
}

uint Server_Ping_Delay=0;
uint Ping_Overall_Delay=0;
uint Ping_LastSent=0;
uint Pings_Sent=0;


PlayerID_t LocalPlayerID;

string CurrentMapName;
bool LoadingMap=false;
uint MapLoadingSize=0;
uint MapTargetSize=0;

bool LoadedCompleteMap=false;

uint ModFileBytes=0;

ubyte[] CurrentLoadingMap;
ubyte MapEncoding;
uint MapXSize, MapYSize, MapZSize;

uint Protocol_Version=8;

uint JoinedGameMaxPhases=4;
uint JoinedGamePhase=0;
bool JoinedGame;

immutable bool[string] Freeze_Mod_Directories;

static this(){
	Freeze_Mod_Directories=[
		"Default":true,
	];
}

enum ModDataTypes{
	Picture=0, Model=1, Script=2
}

struct ModFile_t{
	ubyte type;
	ushort index;
	string name;
	uint size;
	ubyte[] data;
	uint hash;
	bool receiving_data;
	bool no_file;
	this(string initname, ushort initindex, ubyte inittype){
		name=initname; index=initindex; type=inittype;
		size=0; hash=0; receiving_data=false; no_file=false;
	}
	void Loading_Finished(){
		receiving_data=false;
		string current_path=getcwd();
		string fname="./Ressources/"~name;
		string[] nmdirs=cast(string[])pathSplitter(name).array;
		string[] dirs=["./Ressources/"]~nmdirs;
		dirs=dirs[0..$-1];
		foreach(ref dir; dirs){
			if(!exists(dir))
				mkdir(dir);
			chdir(dir);
		}
		chdir(current_path);
		bool preserve_file=false;
		if(dirs[1] in Freeze_Mod_Directories)
			if(Freeze_Mod_Directories[dirs[1]])
				preserve_file=true;
		if(!preserve_file || !no_file){
			File f=File(fname, "wb+");
			f.rawWrite(data);
			f.close();
		}
		data=[];
		switch(type){
			//On Linux, I probably could have used virtual files in RAM instead of physically re-loading them :d
			case ModDataTypes.Picture:{
				SDL_Surface *fsrfc;
				string error;
				switch(fname[$-4..$]){
					case ".bmp":{
						fsrfc=SDL_LoadBMP(toStringz(fname));
						if(!fsrfc)
							error=cast(string)fromStringz(SDL_GetError());
						break;
					}
					case ".png":{
						fsrfc=IMG_Load(toStringz(fname));
						if(!fsrfc)
							error=cast(string)fromStringz(IMG_GetError());
						break;
					}
					default:{
						fsrfc=null;
						error="Unknown image file format"~fname[$-4..$];
						break;
					}
				}
				if(!fsrfc){writeflnerr("Couldn't load %s: %s", fname, error); break;}
				SDL_SetColorKey(fsrfc, SDL_TRUE, SDL_MapRGB(fsrfc.format, 255, 0, 255));
				SDL_Surface *srfc=SDL_ConvertSurfaceFormat(fsrfc, SDL_PIXELFORMAT_ARGB8888, 0);
				RendererTexture_t tex=Renderer_TextureFromSurface(srfc);
				if(Mod_Pictures.length<=index){
					Mod_Pictures.length=index+1;
					Mod_Picture_Surfaces.length=index+1;
					Mod_Picture_Sizes.length=index+1;
				}
				Mod_Pictures[index]=tex;
				Mod_Picture_Surfaces[index]=srfc;
				Mod_Picture_Sizes[index]=[srfc.w, srfc.h];
				SDL_FreeSurface(fsrfc);
				break;
			}
			case ModDataTypes.Model:{
				Model_t *model=Load_KV6(fname);
				if(!model){
					writeflnerr("Couldn't load %s", fname);
					break;
				}
				if(Mod_Models.length<=index)
					Mod_Models.length=index+1;
				Mod_Models[index]=model;
				break;
			}
			case ModDataTypes.Script:{
				try{
					string script=std.file.readText(fname);
					if(Loaded_Scripts.length<=index){
						Loaded_Scripts.length=index+1;
					}
					else{
						if(Loaded_Scripts[index].initialized){
							Loaded_Scripts[index].Uninit();
						}
					}
					Loaded_Scripts[index]=Script_t(index, fname, script);
				}
				catch(FileException){
					writeflnerr("Couldn't load %s", fname);
				}
				break;
			}
			default:{writeflnerr("Server sent mod of unknown data type %s", type); break;}
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
					size=cast(uint)lfsize;
					f.rawRead(data);
					CRC32 context=makeDigest!CRC32();
					context.put(data);
					ubyte[4] hashbuf=context.finish();
					//RIP crc32Of() (used to work, great random number generator now)
					//ubyte[4] hashbuf=crc32Of(data);
					hash=*(cast(uint*)hashbuf.ptr);
					Loading_Finished();
					loaded_file=true;
				}
				else{
					writeflnerr("File %s is too large (%s)", fname, lfsize);
				}
				f.close();
			}
		}
		no_file=!loaded_file;
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

uint NonPlayerColor=0;

void Send_Identification_Packet(string requested_name){
	ClientVersionPacketLayout packet;
	packet.Protocol_Version=Protocol_Version;
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
		uint packetlength=cast(uint)recv_packet.data.length;
		ubyte[] PacketData=cast(ubyte[])recv_packet.data[1..$];
		debug{
			writeflnlog("Received packet with ID %s", id);
		}
		switch(id){
			case MapChangePacketID:{
				auto packet=UnpackPacketToStruct!(MapChangePacketLayout)(PacketData);
				MapXSize=packet.xsize; MapYSize=packet.ysize; MapZSize=packet.zsize;
				MapTargetSize=packet.datasize; MapEncoding=packet.encoding;
				CurrentMapName=packet.mapname;
				writeflnlog("Loading map %s of size %d and dimensions %dx%dx%d", CurrentMapName, MapTargetSize, MapXSize, MapYSize, MapZSize);
				LoadingMap=true;
				LoadedCompleteMap=false;
				JoinedGame=0;
				break;
			}
			case MapChunkPacketID:{
				auto packet=UnpackPacketToStruct!(MapChunkPacketLayout)(PacketData);
				/*if(!packet.data.length)
					break;*/
				CurrentLoadingMap~=packet.data;
				writeflnlog("Received map chunk of size %s (%s/%s)", packet.data.length, CurrentLoadingMap.length, MapTargetSize);
				if(CurrentLoadingMap.length==MapTargetSize){
					Set_MiniMap_Size(MapXSize, MapZSize);
					switch(MapEncoding){
						case DataEncodingTypes.raw:
						default: break;
						case DataEncodingTypes.gzip:{
							import std.zlib;
							CurrentLoadingMap=cast(ubyte[])uncompress(CurrentLoadingMap);
						}
					}
					Renderer_LoadMap(CurrentLoadingMap);
					TerrainOverview=Vector3_t(MapXSize/2, 0.0, MapZSize/2);
					LoadingMap=false;
					LoadedCompleteMap=true;
					CurrentLoadingMap=[];
					On_Map_Loaded();
				}
				break;
			}
			case PlayerJoinPacketID:{
				auto packet=UnpackPacketToStruct!(PlayerJoinPacketLayout)(PacketData);
				/*if(packet.team_id<255){
					writeflnlog("%s", packet.team_id);
					writeflnlog("Player #%d %s joined %s", packet.player_id, packet.name, Teams[packet.team_id].name);
				}
				else{
					writeflnlog("Player #%d %s joined the game", packet.player_id, packet.name);
				}*/
				Init_Player(packet.name, packet.player_id);
				if(packet.player_id==LocalPlayerID)
					Join_Game();
				break;
			}
			case TeamDataPacketID:{
				auto packet=UnpackPacketToStruct!(TeamDataPacketLayout)(PacketData);
				Init_Team(packet.name, packet.team_id, packet.col);
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
			case PlayerDisconnectPacketID:{
				auto packet=UnpackPacketToStruct!(PlayerDisconnectPacketLayout)(PacketData);
				if(packet.player_id!=LocalPlayerID){
					writeflnlog("Player with ID %d disconnected: %s", packet.player_id, packet.reason);
				}
				else{
					writeflnlog("You were disconnected from server: %s", packet.reason);
					QuitGame=true;
				}
				Players[packet.player_id].On_Disconnect();
				break;
			}
			case MapEnvironmentPacketID:{
				auto packet=UnpackPacketToStruct!(MapEnvironmentPacketLayout)(PacketData);
				//Set_Fog(packet.fog_color, packet.visibility_range);
				Base_Visibility_Range=packet.visibility_range;
				Base_Fog_Color=packet.fog_color;
				BaseBlurAmount=packet.base_blur;
				BaseShakeAmount=packet.base_shake;
				BlurAmountDecay=packet.blur_decay;
				ShakeAmountDecay=packet.shake_decay;
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
				ModFile_t mf=ModFile_t(packet.path, packet.index, packet.type);
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
				ModFileBytes+=packet.data.length;
				break;
			}
			case PlayerSpawnPacketID:{
				auto packet=UnpackPacketToStruct!(PlayerSpawnPacketLayout)(PacketData);
				Players[packet.player_id].Spawn(Vector3_t(packet.xpos, packet.ypos, packet.zpos), packet.team_id);
				break;
			}
			case PlayerRotationPacketID:{
				auto packet=UnpackPacketToStruct!(PlayerRotationPacketLayout)(PacketData);
				Players[packet.player_id].dir=Vector3_t(packet.xrot, packet.yrot, packet.zrot);
				if(packet.player_id==LocalPlayerID)
					MouseRot=Players[packet.player_id].dir.DirectionAsRotation;
				break;
			}
			case WorldUpdatePacketID:{
				ubyte player_bit_table_size=PacketData[0];
				PacketData=PacketData[1..$];
				ubyte[] player_bit_table=PacketData[0..player_bit_table_size];
				float[3][] positiondata=cast(float[3][])PacketData[player_bit_table_size+1..$];
				uint posdataindex=0;
				for(uint b=1; b<player_bit_table_size*8; b++){
					if(player_bit_table[b/8]&(1<<(b%8))){
						float[3] pos=positiondata[posdataindex];
						posdataindex++;
						if(EnableByteFlip){
							foreach(ref coord;pos){
								ubyte[4] content=ConvertVariableToArray(coord);
								proper_reverse_overwrite(content);
								coord=ConvertArrayToVariable!(float)(content);
							}
						}
						uint player_id=b-1;
						if(player_id!=LocalPlayerID){
							Players[player_id].pos=Vector3_t(pos);
						}
					}
				}
				break;
			}
			case PlayerKeyEventPacketID:{
				auto packet=UnpackPacketToStruct!(PlayerKeyEventPacketLayout)(PacketData);
				ushort keys=packet.keys;
				if(packet.player_id!=LocalPlayerID) {
					Player_t *plr=&Players[packet.player_id];
					plr.Go_Back=cast(bool)(keys&1);
					plr.Go_Forwards=cast(bool)(keys&2);
					plr.Go_Left=cast(bool)(keys&4);
					plr.Go_Right=cast(bool)(keys&8);
					plr.Jump=cast(bool)(keys&16);
					plr.Set_Crouch(cast(bool)(keys&32));
					plr.Use_Object=cast(bool)(keys&64);
					plr.Sprint=cast(bool)(keys&2048);
					plr.KeysChanged=true;
				}
				break;
			}
			case BindModelPacketID:{
				auto packet=UnpackPacketToStruct!(BindModelPacketLayout)(PacketData);
				Players[packet.player_id].Model=packet.model;
				Players[packet.player_id].Arm_Model=packet.arm_model;
				Players[packet.player_id].Gun_Model=packet.gun_model;
				break;
			}
			case PlayerPositionPacketID:{
				auto packet=UnpackPacketToStruct!(PlayerPositionPacketLayout)(PacketData);
				Players[LocalPlayerID].pos=Vector3_t(packet.xpos, packet.ypos, packet.zpos);
				break;
			}
			case WorldPhysicsPacketID:{
				auto packet=UnpackPacketToStruct!(WorldPhysicsPacketLayout)(PacketData);
				Gravity=packet.g; AirFriction=packet.airfriction; GroundFriction=packet.groundfriction; WaterFriction=packet.waterfriction;
				CrouchFriction=packet.crouchfriction;
				PlayerJumpPower=packet.player_jumppower; PlayerWalkSpeed=packet.player_walkspeed; PlayerSprintSpeed=packet.player_sprintspeed;
				WorldSpeedRatio=packet.world_speed;
				break;
			}
			case MenuElementPacketID:{
				auto packet=UnpackPacketToStruct!(MenuElementPacketLayout)(PacketData);
				if(packet.elementindex>=MenuElements.length){
					size_t oldlen=MenuElements.length;
					MenuElements.length=packet.elementindex+1;
					for(size_t i=oldlen; i<MenuElements.length; i++)
						MenuElements[i].picture_index=255;
				}
				MenuElements[packet.elementindex].set(packet.elementindex, packet.picindex, packet.zval, packet.xpos, packet.ypos, packet.xsize, 
				packet.ysize, packet.transparency);
				MenuElements[packet.elementindex].reserved=!MenuElements[packet.elementindex].inactive();
				break;
			}
			case ToggleMenuPacketID:{
				auto packet=UnpackPacketToStruct!(ToggleMenuPacketLayout)(PacketData);
				Set_Menu_Mode(cast(bool)packet.EnableMenu);
				break;
			}
			case ItemTypePacketID:{
				auto packet=UnpackPacketToStruct!(ItemTypePacketLayout)(PacketData);
				ItemType_t type;
				type.index=packet.weapon_id;
				type.use_delay=packet.use_delay;
				type.maxamount1=packet.maxamount1;
				type.maxamount2=packet.maxamount2;
				type.spread_c=packet.spread_c;
				type.spread_m=packet.spread_m;
				type.recoil_xc=packet.recoil_xc;
				type.recoil_xm=packet.recoil_xm;
				type.recoil_yc=packet.recoil_yc;
				type.recoil_ym=packet.recoil_ym;
				type.block_damage=packet.block_damage;
				type.block_damage_range=packet.block_damage_range;
				type.is_weapon=cast(bool)(packet.typeflags&ITEMTYPE_FLAGS_WEAPON);
				type.repeated_use=cast(bool)(packet.typeflags&ITEMTYPE_FLAGS_REPEATEDUSE);
				type.show_palette=cast(bool)(packet.typeflags&ITEMTYPE_FLAGS_SHOWPALETTE);
				type.color_mod=cast(bool)(packet.typeflags&ITEMTYPE_FLAGS_COLORMOD);
				type.power=packet.power;
				type.model_id=packet.model_id;
				if(packet.bullet_model_id!=VoidModelID){
					if(packet.bullet_model_id<Mod_Models.length){
						type.bullet_sprite.model=Mod_Models[packet.bullet_model_id];
						type.bullet_sprite.xdensity=1.0/32.0; type.bullet_sprite.ydensity=1.0/32.0; type.bullet_sprite.zdensity=1.0/32.0;
						type.bullet_sprite.color_mod=0; type.bullet_sprite.replace_black=0;
					}
					else{
						writeflnerr("Received invalid bullet model id %s %s", packet.bullet_model_id, Mod_Models.length);
					}
				}
				else{
					type.bullet_sprite.model=null;
				}
				if(type.index>=ItemTypes.length)
					ItemTypes.length=type.index+1;
				ItemTypes[type.index]=type;
				break;
			}
			case ItemReloadPacketID:{
				auto packet=UnpackPacketToStruct!(ItemReloadPacketLayout)(PacketData);
				Player_t *plr=&Players[LocalPlayerID];
				if(packet.amount1!=0xffffffff && packet.amount2!=0xffffffff){
					plr.items[packet.item_id].amount1=packet.amount1;
					plr.items[packet.item_id].amount2=packet.amount2;
					plr.items[packet.item_id].Reloading=false;
				}
				else{
					plr.items[packet.item_id].Reloading=true;
				}
				break;
			}
			case ToolSwitchPacketID:{
				auto packet=UnpackPacketToStruct!(ToolSwitchPacketLayout)(PacketData);
				Players[packet.player_id].Switch_Tool(packet.tool_id);
				break;
			}
			case BlockBreakPacketID:{
				auto packet=UnpackPacketToStruct!(BlockBreakPacketLayout)(PacketData);
				Break_Block(packet.player_id, packet.break_type, packet.x, packet.y, packet.z);
				break;
			}
			case SetPlayerColorPacketID:{
				auto packet=UnpackPacketToStruct!(SetPlayerColorPacketLayout)(PacketData);
				if(packet.player_id!=255)
					Players[packet.player_id].color=packet.color;
				else
					NonPlayerColor=packet.color;
				break;
			}
			case BlockBuildPacketID:{
				auto packet=UnpackPacketToStruct!(BlockBuildPacketLayout)(PacketData);
				if(packet.player_id!=255)
					Voxel_SetColor(packet.x, packet.y, packet.z, Players[packet.player_id].color);
				else
					Voxel_SetColor(packet.x, packet.y, packet.z, NonPlayerColor);
				break;
			}
			case PlayerItemsPacketID:{
				Player_t *plr=&Players[PacketData[0]];
				if(PacketData.length){
					plr.selected_item_types=PacketData[1..$];
				}
				else
					plr.selected_item_types.length=0;
				plr.items.length=plr.selected_item_types.length;
				break;
			}
			case SetTextBoxPacketID:{
				auto packet=UnpackPacketToStruct!(SetTextBoxPacketLayout)(PacketData);
				if(packet.box_id>=TextBoxes.length)
					TextBoxes.length=packet.box_id+1;
				TextBoxes[packet.box_id].set(packet.fontpic, packet.xpos, packet.ypos, packet.xsize, packet.ysize, packet.xsizeratio, packet.ysizeratio, packet.flags);
				break;
			}
			case SetTextBoxTextPacketID:{
				auto packet=UnpackPacketToStruct!(SetTextBoxTextPacketLayout)(PacketData);
				TextBoxes[packet.box_id].set_line(packet.line, packet.color, packet.text);
				break;
			}
			case SetObjectPacketID:{
				auto packet=UnpackPacketToStruct!(SetObjectPacketLayout)(PacketData);
				if(packet.obj_id>=Objects.length){
					uint oldlength=cast(uint)Objects.length;
					Objects.length=packet.obj_id+1;
					for(uint i=oldlength; i<Objects.length; i++)
						Objects[i].Init(i);
				}
				Object_t *obj=&Objects[packet.obj_id];
				obj.minimap_img=packet.minimap_img;
				obj.weightfactor=packet.weightfactor;
				obj.bouncefactor=packet.bouncefactor;
				obj.frictionfactor=packet.frictionfactor;
				bool was_solid=Solid_Objects.canFind(packet.obj_id);
				obj.Is_Solid=cast(bool)(packet.flags&SetObjectFlags.Solid);
				if(was_solid && !obj.Is_Solid)
					Solid_Objects.remove(Solid_Objects.countUntil(packet.obj_id));
				if(!was_solid && obj.Is_Solid)
					Solid_Objects~=packet.obj_id;
				obj.enable_bullet_holes=cast(bool)(packet.flags&SetObjectFlags.BulletHoles);
				obj.send_hits=cast(bool)(packet.flags&SetObjectFlags.SendHits);
				if(obj.enable_bullet_holes || obj.send_hits){
					if(!Hittable_Objects.canFind(packet.obj_id))
						Hittable_Objects~=packet.obj_id;
				}
				else{
					if(Hittable_Objects.canFind(packet.obj_id))
						Hittable_Objects.remove(packet.obj_id);
				}
				obj.modify_model=cast(bool)(packet.flags&SetObjectFlags.ModelModification);
				if(packet.model_id==255)
					obj.visible=false;
				else
					obj.visible=true;
				if(obj.visible){
					if(Enable_Object_Model_Modification && obj.modify_model){
						obj.model=Mod_Models[packet.model_id].copy();
					}
					else{
						obj.model=Mod_Models[packet.model_id];
					}
				}
				else{
					obj.model=null;
				}
				obj.color=packet.color;
				break;
			}
			case SetObjectPosPacketID:{
				auto packet=UnpackPacketToStruct!(SetObjectPosPacketLayout)(PacketData);
				Objects[packet.obj_id].pos=Vector3_t(packet.x, packet.y, packet.z);//+Objects[packet.obj_id].vel*tofloat(Get_Ping())/1000.0;
				for(uint i=0; i<tofloat(Get_Ping())/3.0; i++){
					Objects[packet.obj_id].Update();
				}
				break;
			}
			case SetObjectVelPacketID:{
				auto packet=UnpackPacketToStruct!(SetObjectVelPacketLayout)(PacketData);
				Objects[packet.obj_id].vel=Vector3_t(packet.x, packet.y, packet.z);
				break;
			}
			case SetObjectRotPacketID:{
				auto packet=UnpackPacketToStruct!(SetObjectRotPacketLayout)(PacketData);
				Objects[packet.obj_id].rot=Vector3_t(packet.x, packet.y, packet.z);
				break;
			}
			case SetObjectDensityPacketID:{
				auto packet=UnpackPacketToStruct!(SetObjectDensityPacketLayout)(PacketData);
				Objects[packet.obj_id].density=Vector3_t(packet.x, packet.y, packet.z);
				break;
			}
			case ExplosionEffectPacketID:{
				auto packet=UnpackPacketToStruct!(ExplosionEffectPacketLayout)(PacketData);
				Create_Explosion(Vector3_t(packet.xpos, packet.ypos, packet.zpos), Vector3_t(packet.xvel, packet.yvel, packet.zvel),
				packet.radius, packet.spread, packet.amount, packet.col);
				break;
			}
			case ChangeFOVPacketID:{
				auto packet=UnpackPacketToStruct!(ChangeFOVPacketLayout)(PacketData);
				X_FOV=packet.xfov; Y_FOV=packet.yfov;
				break;
			}
			case AssignBuiltinPacketID:{
				auto packet=UnpackPacketToStruct!(AssignBuiltinPacketLayout)(PacketData);
				switch(packet.type){
					case AssignBuiltinTypes.Model:{
						Model_t *model=null;
						if(packet.index<Mod_Models.length)
							model=Mod_Models[packet.index];
						switch(packet.target){
							case AssignBuiltinModelTypes.BlockBuild_Wireframe:{
								ProtocolBuiltin_BlockBuildWireframe=model;
								break;
							}
							default:break;
						}
						break;
					}
					case AssignBuiltinTypes.Picture:{
						RendererTexture_t dstpic=Mod_Pictures[packet.index];
						uint xsize=Mod_Picture_Sizes[packet.index][0], ysize=Mod_Picture_Sizes[packet.index][1];
						switch(packet.target){
							case AssignBuiltinPictureTypes.Font:{
								Set_ModFile_Font(packet.index);
								break;
							}
							default:break;
						}
						break;
					}
					case AssignBuiltinTypes.Sent_Image:{
						MenuElement_t *element=&MenuElements[packet.index];
						element.move_z(InvisibleZPos);
						switch(packet.target){
							case AssignBuiltinSentImageTypes.AmmoCounterBG:{
								ProtocolBuiltin_AmmoCounterBG=element;
								break;
							}
							case AssignBuiltinSentImageTypes.AmmoCounterBullet:{
								ProtocolBuiltin_AmmoCounterBullet=element;
								break;
							}
							case AssignBuiltinSentImageTypes.Palette_HFG:{
								ProtocolBuiltin_PaletteHFG=element;
								Palette_H_Colors=Mod_Picture_Surfaces[element.picture_index];
								Palette_Color_HIndex=ProtocolBuiltin_PaletteHFG.xsize/2;
								Palette_Color_HPos=tofloat(Palette_Color_HIndex);
								break;
							}
							case AssignBuiltinSentImageTypes.Palette_VFG:{
								ProtocolBuiltin_PaletteVFG=element;
								Palette_V_Colors=Mod_Picture_Surfaces[element.picture_index];
								Palette_Color_VIndex=ProtocolBuiltin_PaletteVFG.ysize/2;
								Palette_Color_VPos=tofloat(Palette_Color_VIndex);
								break;
							}
							case AssignBuiltinSentImageTypes.ScopeGfx:{
								ProtocolBuiltin_ScopePicture=element;
								break;
							}
							default:break;
						}
						break;
					}
					default:{
						break;
					}
				}
				break;
			}
			case SetObjectVerticesPacketID:{
				ushort obj_id;
				ubyte[2] obj_id_bytes=PacketData[0..2];
				if(EnableByteFlip)
					proper_reverse_overwrite(obj_id_bytes);
				obj_id=*(cast(ushort*)obj_id_bytes.ptr);
				uint vertices_count=cast(uint)(PacketData.length-2)/12;
				Vector3_t[] vertices;
				if(vertices_count){
					vertices.length=vertices_count;
					ubyte *xptr=&PacketData[2], yptr=&PacketData[2+4], zptr=&PacketData[2+8];
					for(uint v=0; v<vertices_count; v++){
						float xv=ConvertArrayToVariable!(float)(xptr[0..4]);
						float yv=ConvertArrayToVariable!(float)(yptr[0..4]);
						float zv=ConvertArrayToVariable!(float)(zptr[0..4]);
						vertices[v]=Vector3_t(xv, yv, zv);
						xptr+=4*3; yptr+=4*3; zptr+=4*3;
					}
					Objects[obj_id].Vertices=vertices;
				}
				else{
					Objects[obj_id].Vertices=[];
				}
				break;
			}
			case SetPlayerModelPacketID:{
				auto packet=UnpackPacketToStruct!(SetPlayerModelPacketLayout)(PacketData);
				Player_t *plr=&Players[packet.player_id];
				if(packet.playermodelindex>=plr.models.length)
					plr.models.length=packet.playermodelindex+1;
				PlayerModel_t *model=&plr.models[packet.playermodelindex];
				model.model_id=packet.modelfileindex;
				model.size=Vector3_t(packet.xsize, packet.ysize, packet.zsize);
				model.offset=Vector3_t(packet.xoffset, packet.yoffset, packet.zoffset);
				model.rotation=Vector3_t(packet.xrot, packet.yrot, packet.zrot);
				model.FirstPersonModel=!cast(bool)(packet.flags&SetPlayerModelPacketFlags.NonFirstPersonModel);
				model.Rotate=cast(bool)(packet.flags&SetPlayerModelPacketFlags.RotateModel);
				model.WalkRotate=packet.walk_rotate;
				break;
			}
			case PingPacketID:{
				ubyte packet_id=PingPacketID;
				Send_Data(&packet_id, 1);
				uint last_ping_t=Ping_LastSent;
				uint current_t=SDL_GetTicks();
				Ping_LastSent=current_t;
				if(Pings_Sent)
					Ping_Overall_Delay+=(current_t-last_ping_t)-Server_Ping_Delay;
				Pings_Sent++;
				if(Pings_Sent>30){
					Ping_Overall_Delay=(current_t-last_ping_t)-Server_Ping_Delay;
					Pings_Sent=0;
				}
				break;
			}
			case SetPlayerModePacketID:{
				auto packet=UnpackPacketToStruct!(SetPlayerModePacketLayout)(PacketData);
				Players[packet.player_id].Spawned=Players[packet.player_id].Spawned=cast(bool)packet.mode;
				break;
			}
			case SetBlurPacketID:{
				auto packet=UnpackPacketToStruct!(SetBlurPacketLayout)(PacketData);
				BlurAmount+=packet.blur;
				break;
			}
			case SetShakePacketID:{
				auto packet=UnpackPacketToStruct!(SetShakePacketLayout)(PacketData);
				ShakeAmount+=packet.shake;
				break;
			}
			case ToggleScriptPacketID:{
				auto packet=UnpackPacketToStruct!(ToggleScriptPacketLayout)(PacketData);
				Loaded_Scripts[packet.index].Set_Enabled(cast(bool)(packet.flags&ToggleScriptPacketFlags.Run),
				cast(bool)(packet.flags&ToggleScriptPacketFlags.Repeat), cast(bool)(packet.flags&ToggleScriptPacketFlags.MiniMap_Renderer));
				break;
			}
			case CustomScriptPacketID:{
				auto packet=UnpackPacketToStruct!(CustomScriptPacketLayout)(PacketData);
				Loaded_Scripts[packet.scr_index].Call_Func("On_Packet_Receive", cast(ubyte[])packet.data);
				break;
			}
			case SetObjectAclPacketID:{
				auto packet=UnpackPacketToStruct!(SetObjectAclPacketLayout)(PacketData);
				Objects[packet.obj_id].acl=Vector3_t(packet.x, packet.y, packet.z);
				break;
			}
			case SetScorePacketID:{
				auto packet=UnpackPacketToStruct!(SetScorePacketLayout)(PacketData);
				Players[packet.player_id].score=packet.score;
				break;
			}
			case PublicPlayerMouseClickPacketID:{
				auto packet=UnpackPacketToStruct!(PublicPlayerMouseClickPacketLayout)(PacketData);
				Players[packet.player_id].left_click=cast(bool)(packet.mouse_clicks&1);
				Players[packet.player_id].right_click=cast(bool)(packet.mouse_clicks&2);
				break;
			}
			case RunScriptPacketID:{
				auto packet=UnpackPacketToStruct!(RunScriptPacketLayout)(PacketData);
				auto script=Script_t(cast(ushort)Loaded_Scripts.length, "__temporary_script"~to!string(Loaded_Scripts.length), packet.script);
				script.Init();
				Loaded_Scripts~=script;
				script.Call_Func("RunScript");
				script.Uninit();
				Loaded_Scripts.length--;
				break;
			}
			case SetObjectPhysicsPacketID:{
				auto packet=UnpackPacketToStruct!(SetObjectPhysicsPacketLayout)(PacketData);
				Object_t *obj=&Objects[packet.obj_id];
				obj.physics_mode=to!ObjectPhysicsMode(packet.physics_mode);
				obj.physics_script=packet.script;
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
				if(PacketData[0]){
					auto packet=UnpackPacketToStruct!(ServerVersionPacketLayout)(PacketData);
					LocalPlayerID=packet.player_id;
					writeflnlog("Server version: %d, Player ID: %d", packet.server_version, LocalPlayerID);
					JoinedGamePhase=JoinedGameMaxPhases-1;
					Server_Ping_Delay=packet.ping_delay;
				}
				else{
					auto packet=UnpackPacketToStruct!(ServerConnectionDenyPacketLayout)(PacketData);
					writeflnlog("Server refused to connect! Reason: %s", packet.reason);
					QuitGame=1;
				}
				break;
			}
			default:{break;}
		}
		JoinedGamePhase++;
	}
}

void Send_Disconnect_Packet(){
	PlayerDisconnectPacketLayout packet;
	packet.player_id=LocalPlayerID; packet.reason="Disconnected";
	Send_Packet(PlayerDisconnectPacketID, packet);
}

void Send_Packet(T)(PacketID_t id, T packet){
	auto packetbytes=PackStructToPacket(packet);
	Send_Data(id~packetbytes);
}

immutable float RotationDataSendDist=.1;
Vector3_t LastRotationDataSent=Vector3_t(0.0);
void Update_Rotation_Data(bool force_update=false){
	float dist=(MouseRot-LastRotationDataSent).length;
	if(dist>RotationDataSendDist || (force_update && dist>10e-99)){
		PlayerRotationPacketLayout packet;
		Vector3_t dir=Players[LocalPlayerID].dir;
		packet.xrot=dir.x; packet.yrot=dir.y; packet.zrot=dir.z;
		Send_Packet(PlayerRotationPacketID, packet);
		uint data=Convert_Unit_Vec_To_NetFP(dir);
		/*writeflnlog("%s", dir);
		writeflnlog("%s", Convert_NetFP_To_Unit_Vec(data));*/
		LastRotationDataSent=MouseRot;
	}
}

immutable float PositionDataSendDist=2.0;
Vector3_t LastPositionDataSent=Vector3_t(0.0);
void Update_Position_Data(bool force_update=false){
	float dist=(Players[LocalPlayerID].pos-LastPositionDataSent).length;
	if(dist>PositionDataSendDist || (force_update && dist>10e-99)){
		PlayerPositionPacketLayout packet;
		Vector3_t pos=Players[LocalPlayerID].pos;
		packet.xpos=pos.x; packet.ypos=pos.y; packet.zpos=pos.z;
		Send_Packet(PlayerPositionPacketID, packet);
		LastPositionDataSent=pos;
	}
}

bool Joined_Game(){
	if(!JoinedGame)
		return false;
	return Players[LocalPlayerID].InGame;
}

void Join_Game(){
	JoinedGame=true;
	Players[LocalPlayerID].InGame=true;
	CameraRot=Vector3_t(0.0);
	writeflnlog("Loaded %s K bytes of mod files", tofloat(ModFileBytes)/1024.0);
}

void Send_Key_Presses(ushort keypresses){
	PlayerKeyEventPacketLayout packet;
	packet.keys=keypresses;
	Send_Packet(PlayerKeyEventPacketID, packet);
}

void Send_Mouse_Click(bool left_click, bool right_click, int xpos, int ypos){
	MouseClickPacketLayout packet;
	packet.clicks=(cast(uint)left_click)*(1<<0)+(cast(uint)right_click)*(1<<1);
	packet.xpos=cast(ushort)(cast(float)(xpos)*65535.0/cast(float)(ScreenXSize));
	packet.ypos=cast(ushort)(cast(float)(ypos)*65535.0/cast(float)(ScreenYSize));
	Send_Packet(MouseClickPacketID, packet);
	if(Joined_Game && !Menu_Mode)
		Players[LocalPlayerID].left_click=left_click;
}

uint Get_Ping(){
	return Ping_Overall_Delay/(Pings_Sent+1);
}

//We're using a packed format here. I think that 3 numbers after the comma is enough for orientation data transfer
//However, if I want to transfer signs, I'd have to use 11 bit variables. Since I can transfer 32 but not 33 bits,
//the poor Y coordinate will only have 10 bits
uint Convert_Unit_Vec_To_NetFP(Vector3_t vec){
	short x=(cast(short)(fabs(vec.x)*1024.0));
	short y=(cast(short)(fabs(vec.y)*512.0));
	short z=(cast(short)(fabs(vec.z)*1024.0));
	if(vec.x<0.0)
		x|=1<<10;
	if(vec.y<0.0)
		y|=1<<9;
	if(vec.z<0.0)
		z|=1<<10;
	return (x) | (y<<11) | (z<<22);
}

Vector3_t Convert_NetFP_To_Unit_Vec(uint fpvec){
	short x=cast(short)(fpvec&((1<<10)-1)), y=cast(short)((fpvec>>11)&((1<<9)-1)), z=cast(short)((fpvec>>22)&((1<<10)-1));
	uint xsign=fpvec&(1<<10), ysign=(fpvec>>11)&(1<<9), zsign=fpvec&(1<<31);
	return Vector3_t(tofloat(x)/1024.0*(xsign ? -1.0 : 1.0), tofloat(y)/512.0*(ysign ? -1.0 : 1.0), tofloat(z)/1024.0*(zsign ? -1.0 : 1.0));
}
