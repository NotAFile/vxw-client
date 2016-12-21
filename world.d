import derelict.sdl2.sdl;
import std.conv;
import std.math;
import std.random;
import std.algorithm;
import packettypes;
import vector;
import renderer;
import misc;
import gfx;
import ui;
import protocol;
version(LDC){
	import ldc_stdlib;
}

float Gravity=9.81;
float AirFriction=.24;
float GroundFriction=2.0;
float WaterFriction=2.5;
float CrouchFriction=5.0;
//Inb4 SMB
float PlayerJumpPower=6.0;
float PlayerWalkSpeed=1.0;
float PlayerSprintSpeed=1.5;
float WorldSpeedRatio=2.0;

Vector3_t Sun_Vector, Sun_Position;

uint Base_Visibility_Range=128, Current_Visibility_Range=128;
uint Base_Fog_Color=0x0000ffff, Current_Fog_Color=0x0000ffff;

immutable float Player_Stand_Size=2.5;
immutable float Player_Crouch_Size=1.5;

Vector3_t Wind_Direction;

struct PlayerModel_t{
	ubyte model_id;
	Vector3_t size, offset, rotation;
	bool FirstPersonModel, Rotate;
	float WalkRotate;
}

struct Player_t{
	PlayerID_t player_id;
	string name;
	bool Spawned;
	bool InGame;
	uint score;
	
	PlayerModel_t[] models;
	
	Vector3_t pos, vel, acl;
	Vector3_t dir;
	TeamID_t team;
	bool Go_Forwards, Go_Back, Go_Left, Go_Right;
	bool Jump, Crouch, Sprint;
	bool Use_Object;
	bool KeysChanged;
	bool[3] CollidingSides;
	Vector3_t ColVel;
	//Remove the following line if you don't need it and replaced it with something better
	int Model; int Gun_Model; int Arm_Model;
	uint Gun_Timer;
	Item_t[] items;
	ubyte[] selected_item_types;
	uint item;
	bool left_click, right_click;
	uint color;
	Object_t *standing_on_obj, stood_on_obj;
	
	float Walk_Forwards_Timer, Walk_Sidewards_Timer;
	
	void Init(string initname, PlayerID_t initplayer_id){
		name=initname;
		player_id=initplayer_id;
		team=255;
		Spawned=false;
		InGame=true;
		KeysChanged=false;
		pos=Vector3_t(0.0); vel=Vector3_t(0.0); acl=Vector3_t(0.0); dir=Vector3_t(1.0, 0.0, 0.0);
		Model=-1;
		Gun_Timer=0;
	}
	Team_t *Get_Team(){
		if(team==255)
			return null;
		return &Teams[team];
	}
	void Spawn(Vector3_t location, TeamID_t spteam){
		if(player_id==LocalPlayerID)
			BlurAmount=0.0;
		pos=location;
		team=spteam;
		Spawned=true;
		InGame=true;
		items.length=selected_item_types.length;
		if(items.length){
			foreach(uint i, type; selected_item_types)
				items[i].Init(type);
		}
		Walk_Forwards_Timer=0.0;
		Walk_Sidewards_Timer=0.0;
	}
	void On_Disconnect(){
		InGame=false;
		Spawned=false;
		if(Players.length==this.player_id){
			Players.length--;
		}
	}
	void Update(){
		Update_Physics();
		if(left_click && Spawned){
			if(player_id!=LocalPlayerID || !Menu_Mode)
				Use_Item();
		}
	}
	void Update_Physics(){
		if(!Spawned)
			return;
		acl=Vector3_t(0.0);
		Vector3_t acdir=dir.filter(1, 0, 1);
		float friction=WorldSpeed;
		float walk_speed=!Sprint ? PlayerWalkSpeed : PlayerSprintSpeed;
		if(CollidingSides[1]){
			if(Go_Forwards || Go_Back){
				acl+=acdir*((!Go_Back) ? walk_speed : -walk_speed);
			}
			if(Go_Left || Go_Right){
				acl+=acdir.rotate(Vector3_t(0.0, Go_Left ? 90.0 : -90.0, 0.0))*walk_speed;
			}
			if(Jump){
				acl.y-=PlayerJumpPower;
			}
			friction*=GroundFriction;
		}
		else{
			acl.y+=WorldSpeed*Gravity;
			friction*=AirFriction;
		}
		if(In_Water)
			friction*=WaterFriction;
		if(Crouch){
			friction*=CrouchFriction;
		}
		if(KeysChanged)
			KeysChanged=false;
		vel+=acl*WorldSpeed*10.0;
		vel/=1.0+friction;
		Vector3_t delta=vel;
		if(CollidingSides[0] && !vel.x){
			delta.x=ColVel.x;
		}
		if(CollidingSides[1] && !vel.y){
			delta.y=ColVel.y;
		}
		if(CollidingSides[2] && !vel.z){
			delta.z=ColVel.z;
		}
		CheckCollisionReturn_t coll;
		Vector3_t newpos=pos+delta*WorldSpeed;
		if(vel.length<1.0 || 1)
			coll=Check_Collisions_norc(newpos);
		else
			coll=Check_Collisions_rc(newpos);
		bool Climbed=false;
		if(coll.Collision){
			if((coll.Sides[0] || coll.Sides[2]) && !Crouch){
				Vector3_t climbpos=pos+delta.filter(true, false, true)*WorldSpeed;
				if(In_Water() && !Crouch)
					climbpos.y-=1.0;
				climbpos.y-=1.0;
				auto climbcoll=Check_Collisions_norc(climbpos);
				if(!climbcoll.Collision){
					float delta_y=pos.y-climbpos.y;
					float ny=climbpos.y;
					while(Collides_At(pos.x, ny+delta_y, pos.z) && delta_y>.005){
						delta_y*=.5f;
					}
					pos.y=ny+delta_y;
					Climbed=true;
				}
			}
			if(!Climbed){
				CollidingSides=coll.Sides;
				if(coll.Sides[1]){
					//pos.y=coll.collpos.y-height-.01;
				}
				if(CollidingSides[0] && vel.x){
					ColVel.x=vel.x;
				}
				if(CollidingSides[1] && vel.y){
					ColVel.y=vel.y;
				}
				if(CollidingSides[2] && vel.z){
					ColVel.z=vel.z;
				}
				vel=vel.filter(!CollidingSides[0], !CollidingSides[1], !CollidingSides[2]);
			}
		}
		CollidingSides=coll.Sides;
		pos+=vel*WorldSpeed;
		//Note: I'm using a "dirty" trick here. Of course, the optimal way would be using something like a property
		//But these are such scrap on D :S (damn it D devs, when will you make proper properties at last!)
		stood_on_obj=standing_on_obj;
		standing_on_obj=Standing_On_Object();
		if(standing_on_obj){
			pos+=standing_on_obj.vel*WorldSpeed;
		}
		else{
			if(stood_on_obj)
				vel+=stood_on_obj.vel;
		}
		if(dir.length){
			float l=vel.filter(true, false, true).dot(dir.filter(true, false, true))*WorldSpeed*4.0;
			if(fabs(l)>.00001)
				Walk_Forwards_Timer+=l;
			else
				Walk_Forwards_Timer=0.0;
			l=vel.filter(true, false, true).dot(dir.rotate_raw(Vector3_t(0.0, 90.0, 0.0)).filter(true, false, true))*WorldSpeed*4.0;
			if(fabs(l)>.00001)
				Walk_Sidewards_Timer+=l;
			else
				Walk_Sidewards_Timer=0.0;
		}
		else{
			Walk_Forwards_Timer=0.0; Walk_Sidewards_Timer=0.0;
		}
		if(Climbed)
			vel*=.1;
		if(player_id==LocalPlayerID)
			Update_Position_Data();
	}
	bool Collides_At(T1, T2, T3)(T1 x, T2 y, T3 z){
		bool coll=false;
		/*int upx=(x-.45), upz=(z-.45);
		int lpx=(x+.45), lpz=(z+.45);*/
		immutable stepsize=.25;
		for(float py=y; py<y+height; py+=stepsize){
			if(Voxel_Collides(x, py, z)){
				return true;
			}
		}
		return false;
	}
	float Get_Collision_MinY(T1, T2, T3)(T1 x, T2 y, T3 z){
		bool coll=false;
		immutable stepsize=.25;
		for(float py=y; py<y+height; py+=stepsize){
			if(Voxel_Collides(x, py, z)){
				return CollidingVoxel_GetMinY(x, py, z);
			}
		}
		return false;
	}
	//Works more or less
	CheckCollisionReturn_t Check_Collisions_norc(Vector3_t newpos){
		if(!Collides_At(newpos.x, newpos.y, newpos.z))
			return CheckCollisionReturn_t(Vector3_t(0.0), 0);
		bool[3] collsides=[false, false, false];
		Vector3_t collpos=pos;
		if(Collides_At(newpos.x, pos.y, pos.z)){
			collsides[0]=true;
			collpos.x=pos.x+(cast(float)(vel.x>0.0));
		}
		if(Collides_At(pos.x, newpos.y, pos.z)){
			collsides[1]=true;
			float delta_y=newpos.y-pos.y;
			float ny=pos.y;
			while(Collides_At(pos.x, ny, pos.z) && fabs(delta_y)>.05){
				delta_y*=.5f;
				ny=pos.y+delta_y;
			}
			//collpos.y=pos.y+(cast(float)(vel.y>0.0));
			//collpos.y=Get_Collision_MinY(pos.x, newpos.y, pos.z);
		}
		if(Collides_At(pos.x, pos.y, newpos.z)){
			collsides[2]=true;
			collpos.z=pos.z+(cast(float)(vel.z>0.0));
		}
		return CheckCollisionReturn_t(collpos, collsides, collsides[0] || collsides[1] || collsides[2]);
	}
	//WIP (careful: works with player's velocity values)
	CheckCollisionReturn_t Check_Collisions_rc(Vector3_t newpos){
		Vector3_t nvel=vel.abs;
		int x=cast(int)pos.x, y=cast(int)pos.y, z=cast(int)pos.z;
		int sx=x, sy=y, sz=z;
		int dstx=cast(int)(newpos.x), dsty=cast(int)(newpos.y), dstz=cast(int)(newpos.z);
		uint opsidex=cast(uint)(pos.x>0.0), opsidey=cast(uint)(pos.y>0.0), opsidez=cast(uint)(pos.z>0.0);
		int xsgn=cast(int)sgn(vel.x), ysgn=cast(int)sgn(vel.y), zsgn=cast(int)sgn(vel.z);
		//DDA physics "raycast"
		bool[3] collsides=[false, false, false];
		while(x!=dstx && y!=dsty && z!=dstz){
			float xsd=(cast(float)(x+opsidex)-pos.x)/nvel.x;
			float ysd=(cast(float)(y+opsidey)-pos.y)/nvel.y;
			float zsd=(cast(float)(z+opsidez)-pos.z)/nvel.z;
			if(xsd<ysd){
				if(xsd<zsd){
					x+=xsgn;
					collsides[0]=true;
				}
				else{
					z+=zsgn;
					collsides[2]=true;
				}
			}
			else{
				if(ysd<zsd){
					y+=ysgn;
					collsides[1]=true;
				}
				else{
					z+=zsgn;
					collsides[2]=true;
				}
			}
			for(uint py=y; py<=y; y++)
				if(Voxel_IsSolid(x, py, z))
					break;
		}
		return CheckCollisionReturn_t(Vector3_t(x, y, z), collsides);
	}
	void Use_Item(){
		uint current_tick=SDL_GetTicks();
		Item_t *current_item=&items[item];
		int timediff=current_tick-current_item.use_timer;
		if(toint(timediff)<toint(ItemTypes[current_item.type].use_delay)-toint(Get_Ping())-toint(10)){
			Update_Position_Data(true);
		}
		if(timediff<ItemTypes[current_item.type].use_delay)
			return;
		current_item.use_timer=current_tick;
		ItemType_t *itemtype=&ItemTypes[current_item.type];
		if(current_item.Reloading || (!current_item.amount1 && itemtype.maxamount1))
			return;
		
		Vector3_t usepos, usedir;
		if(player_id==LocalPlayerID && MouseRightClick && itemtype.is_weapon){
			auto scp=Get_Player_Scope(player_id);
			usepos=scp.pos; usedir=scp.rot.RotationAsDirection();
		}
		else{
			usepos=pos;
			usedir=dir;
		}
		Vector3_t spreadeddir;
		float spreadfactor=itemtype.spread_c+itemtype.spread_m*uniform01();
		spreadeddir=usedir*(1.0-spreadfactor)+Vector3_t(uniform01(), uniform01(), uniform01())*spreadfactor;

		float block_hit_dist=10e99;
		Vector3_t block_hit_pos;
		if(itemtype.block_damage){
			short range=itemtype.block_damage_range;
			if(range<0)
				range=cast(short)Current_Visibility_Range;
			auto rcp=RayCast(usepos, spreadeddir, range);
			if(rcp.collside){
				block_hit_dist=rcp.colldist;
				block_hit_pos=Vector3_t(rcp.x, rcp.y, rcp.z);
			}
		}
		float player_hit_dist=10e99;
		PlayerID_t player_hit_id;
		ubyte player_hit_sprite;
		if(itemtype.is_weapon){
			bool hit_player=false;
			Vector3_t LastHitPos;
			ubyte LastHitSpriteIndex;
			PlayerID_t LastHitPlayer;
			float LastHitDist=block_hit_dist;
			Renderer_AddFlash(usepos, 4.0, 1.0);
			foreach(PlayerID_t pid, ref plr; Players){
				if(pid==player_id)
					continue;
				if(!plr.Spawned || !plr.InGame)
					continue;
				if((plr.pos-pos).length>min(Current_Visibility_Range+5, block_hit_dist+5))
					continue;
				Sprite_t[] sprites=Get_Player_Sprites(pid);
				foreach(ubyte spindex, ref spr; sprites){
					Vector3_t vxpos; ModelVoxel_t *vx;
					if(!Sprite_BoundHitCheck(&spr, usepos, spreadeddir))
						continue;
					if(SpriteHitScan(&spr, usepos, spreadeddir, vxpos, vx, 3.0)){
						//vx.color=0x00ff0000;
						if(player_id==LocalPlayerID){
							hit_player=true;
							float hitdist=(vxpos-usepos).length;
							if(hitdist<LastHitDist){
								LastHitPos=vxpos;
								LastHitSpriteIndex=spindex;
								LastHitPlayer=pid;
								LastHitDist=hitdist;
							}
						}
						Create_Particles(vxpos, Vector3_t(0.0), 0.0, .075, 10, [0x00ff0000]);
					}
				}
			}
			if(hit_player){
				player_hit_dist=LastHitDist;
				player_hit_id=LastHitPlayer;
				player_hit_sprite=LastHitSpriteIndex;
			}
		}
		float object_hit_dist=10e99;
		ushort object_hit_id;
		ModelVoxel_t *object_hit_vx;
		Vector3_t object_hit_pos;
		if(itemtype.is_weapon){
			bool hit_object=false;
			float LastHitDist=10e99;
			ushort LastHitID;
			foreach(obj_id; Hittable_Objects){
				Object_t *obj=&Objects[obj_id];
				Sprite_t objspr=Get_Object_Sprite(obj_id);
				ModelVoxel_t *vx;
				Vector3_t hit_pos;
				if(SpriteHitScan(&objspr, usepos, spreadeddir, hit_pos, vx)){
					float vxdist=(hit_pos-usepos).length;
					if(vxdist<LastHitDist){
						hit_object=true;
						object_hit_pos=hit_pos;
						LastHitDist=vxdist;
						LastHitID=cast(ushort)obj_id;
						object_hit_vx=vx;
					}
				}
			}
			if(hit_object){
				object_hit_dist=LastHitDist;
				object_hit_id=LastHitID;
			}
			if(itemtype.Is_Gun()){
				Create_Smoke(usepos+usedir*1.0, to!uint(10*itemtype.power), 0xff808080, 1.0*sqrt(itemtype.power), .1, .1, usedir*.1*sqrt(itemtype.power));
				Bullet_Shoot(usepos+usedir*.5, usedir*125.0, LastHitDist, &itemtype.bullet_sprite);
			}
		}
		if(block_hit_dist<player_hit_dist && block_hit_dist<object_hit_dist){
			uint dmgx=touint(block_hit_pos.x), dmgy=touint(block_hit_pos.y), dmgz=touint(block_hit_pos.z);
			if(itemtype.is_weapon){
				Vector3_t particle_pos=usepos+spreadeddir*block_hit_dist;
				Damage_Block(player_id, dmgx, dmgy, dmgz, itemtype.block_damage, &particle_pos);
			}
			else{
				Damage_Block(player_id, dmgx, dmgy, dmgz, itemtype.block_damage, null);
			}
		}
		if(player_hit_dist<block_hit_dist && player_hit_dist<object_hit_dist){
			PlayerHitPacketLayout packet;
			packet.player_id=player_hit_id;
			packet.hit_sprite=player_hit_sprite;
			Send_Packet(PlayerHitPacketID, packet);
		}
		if(object_hit_dist<player_hit_dist && object_hit_dist<block_hit_dist){
			if(Objects[object_hit_id].enable_bullet_holes)
				Objects[object_hit_id].Damage(usepos+spreadeddir*(object_hit_dist-.1));
			else
			if(Objects[object_hit_id].modify_model)
				object_hit_vx.color=0;
			if(Objects[object_hit_id].send_hits){
				ObjectHitPacketLayout packet;
				packet.object_index=object_hit_id;
				Send_Packet(ObjectHitPacketID, packet);
			}
		}
		if(itemtype.repeated_use)
			current_item.use_timer=current_tick;
		float xrecoil=(itemtype.recoil_xc+itemtype.recoil_xm*uniform01())*((uniform!int()&1)*2-1);
		float yrecoil=itemtype.recoil_yc+itemtype.recoil_ym*uniform01()*((uniform!int()&1)*2-1);
		if(player_id==LocalPlayerID){
			MouseRot.y+=yrecoil;
			MouseRot.x+=xrecoil;
		}
		current_item.last_recoil=yrecoil;
		dir.rotate(Vector3_t(0, yrecoil, xrecoil));
		if(itemtype.is_weapon)
			current_item.amount1--;
	}
	void Switch_Tool(ubyte tool_id){
		item=tool_id;
	}
	bool In_Water(){
		return Voxel_IsWater(pos.x, pos.y+height(), pos.z);
	}
	Object_t *Standing_On_Object(){
		Vector3_t floorpos=pos;
		floorpos.y+=height;
		foreach(index; Solid_Objects){
			if(Objects[index].Solid_At(floorpos.x, floorpos.y, floorpos.z))
				return &Objects[index];
		}
		return null;
	}
	float height(){
		if(!Crouch)
			return Player_Stand_Size;
		return Player_Crouch_Size;
	}
	bool HalfDiving(){
		return Voxel_IsWater(pos.x, pos.y+Player_Crouch_Size, pos.z);
	}
	void Set_Crouch(bool cr){
		if(Crouch && !cr){
			pos.y=pos.y+Player_Crouch_Size-Player_Stand_Size;
		}
		else
		if(!Crouch && cr){
			pos.y=pos.y+Player_Stand_Size-Player_Crouch_Size;
		}
		Crouch=cr;
	}
}

bool Voxel_IsWater(T1, T2, T3)(T1 x, T2 y, T3 z){
	return y>=MapYSize-1;
}

uint[] Solid_Objects;
uint[] Hittable_Objects;

bool Voxel_Collides(XT, YT, ZT)(XT x, YT y, ZT z, int exclude_obj_index=-1){
	if(x<0 || x>=MapXSize || z<0 || z>=MapZSize || y>=MapYSize)
		return true;
	if(y<0)
		return false;
	if(Voxel_IsWater(x, y, z))
		return false;
	if(Voxel_IsSolid(cast(uint)x, cast(uint)y, cast(uint)z))
		return true;
	foreach(index; Solid_Objects){
		if(index==exclude_obj_index)
			continue;
		if(Objects[index].Solid_At(x, y, z))
			return true;
	}
	return false;
}

float CollidingVoxel_GetMinY(TX, TY, TZ)(TX x, TY y, TZ z, int exclude_obj_index=-1){
	if(Voxel_Collides(cast(uint)x, cast(uint)y, cast(uint)z))
		return tofloat(touint(y));
	foreach(index; Solid_Objects){
		if(index==exclude_obj_index)
			continue;
		if(Objects[index].Solid_At(x, y, z)){
			return Objects[index].Collision_GetMinY(x, y, z)-.5;
		}
	}
	return NaN(0);
}

bool Voxel_IsSurface(int x, int y, int z){
	if(!y)
		return true;
	if(Valid_Coord(x-1, y, z)){
		if(!Voxel_IsSolid(x-1, y, z))
			return true;
	}
	if(Valid_Coord(x+1, y, z)){
		if(!Voxel_IsSolid(x+1, y, z))
			return true;
	}
	if(Valid_Coord(x, y-1, z)){
		if(!Voxel_IsSolid(x, y-1, z))
			return true;
	}
	if(Valid_Coord(x, y+1, z)){
		if(!Voxel_IsSolid(x, y+1, z))
			return true;
	}
	if(Valid_Coord(x, y, z-1)){
		if(!Voxel_IsSolid(x, y, z-1))
			return true;
	}
	if(Valid_Coord(x, y, z+1)){
		if(!Voxel_IsSolid(x, y, z+1))
			return true;
	}
	return false;
}

struct CheckCollisionReturn_t{
	Vector3_t collpos;
	bool[3] Sides;
	bool Collision;
}

Player_t[] Players;

void Init_Player(string name, PlayerID_t id){
	if(id>=Players.length)
		Players.length=id+1;
	Player_t *plr=&Players[id];
	plr.Init(name, id);
}

struct Team_t{
	TeamID_t id;
	string name;
	union{
		ubyte[4] color;
		uint icolor;
	}
	void Init(string initname, TeamID_t team_id, uint initcolor){
		id=team_id;
		name=initname;
		icolor=initcolor;
	}
}

Team_t[] Teams;

void Init_Team(string name, TeamID_t team_id, uint color){
	if(team_id>=Teams.length){
		Teams.length=team_id+1;
	}
	Team_t *team=&Teams[team_id];
	team.Init(name, team_id, color);
}

float WorldSpeed=1.0;
uint Last_Tick;

struct ItemType_t{
	ubyte index;
	uint use_delay;
	uint maxamount1, maxamount2;
	bool is_weapon, repeated_use, show_palette, color_mod;
	ubyte block_damage;
	short block_damage_range;
	float spread_c, spread_m;
	float recoil_xc, recoil_xm;
	float recoil_yc, recoil_ym;
	float power;
	ModelID_t model_id;
	Sprite_t bullet_sprite;
	bool Is_Gun(){
		return is_weapon && maxamount1 && bullet_sprite.model!=null;
	}
}
ItemType_t[] ItemTypes;

struct Item_t{
	ubyte type;
	uint amount1, amount2;
	uint use_timer;
	bool Reloading;
	float last_recoil;
	void Init(ubyte inittype){
		type=inittype;
		use_timer=0;
		amount1=ItemTypes[type].maxamount1;
		amount2=ItemTypes[type].maxamount2;
		Reloading=false;
		last_recoil=0.0;
	}
	bool Can_Use(){
		if(Reloading || (!amount1 && ItemTypes[type].maxamount1))
			return false;
		int timediff=SDL_GetTicks()-use_timer;
		if(timediff<ItemTypes[type].use_delay)
			return false;
		return true;
	}
}

float delta_time;
uint __Block_Damage_Check_Index=0;
immutable uint __Block_Damage_ChecksPerFrame=32;
immutable uint __BlockDamage_HealTimer=1000*5;
immutable ubyte __BlockDamage_HealAmount=16;
void Update_World(){
	uint Current_Tick=SDL_GetTicks();
	if(Last_Tick){
		delta_time=tofloat(Current_Tick-Last_Tick)/1000.0;
		WorldSpeed=delta_time*WorldSpeedRatio;
	}
	else{
		WorldSpeed=(1.0/30.0)*WorldSpeedRatio;
	}
	foreach(ref p; Players)
		p.Update();
	foreach(ref o; Objects)
		o.Update();
	if(BlockDamage.length){
		bool __dmgblock_removed=false;
		while(!__dmgblock_removed && BlockDamage.length){
			__dmgblock_removed=false;
			auto hashes=BlockDamage.keys();
			uint ind2=__Block_Damage_Check_Index+__Block_Damage_ChecksPerFrame;
			if(ind2>=hashes.length)
				ind2=hashes.length;
			foreach(ref hash; hashes[__Block_Damage_Check_Index..ind2]){
				auto bdmg=&BlockDamage[hash];
				if(Current_Tick-bdmg.timer>__BlockDamage_HealTimer){
					bdmg.timer=Current_Tick;
					if(bdmg.Heal(__BlockDamage_HealAmount)){			
						BlockDamage.remove(hash);
						__dmgblock_removed=true;
						break;
					}
				}
			}
			if(!__dmgblock_removed){
				if(ind2<hashes.length){
					__Block_Damage_Check_Index=ind2;
				}
				else{
					__Block_Damage_Check_Index=0;
					BlockDamage.rehash();
				}
				break;
			}
		}
	}
	Last_Tick=Current_Tick;
}

uint Hash_Coordinates(uint x, uint y, uint z){
	return x+y*MapXSize+z*MapXSize*MapYSize;
}

immutable uint MaxDamageParticlesPerBlock=256;

struct DamageParticle_t{
	float x, y, z;
	uint col;
	void Init(uint ix, uint iy, uint iz, uint icol, uint[] free_sides){
		float vx=tofloat(ix)+.5, vy=tofloat(iy)+.5, vz=tofloat(iz)+.5;
		/*uint side=uniform(0, 3);
		float sidesgn=tofloat(toint(uniform(0, 2))*2-1)*.5;*/
		uint side=free_sides[uniform(0, free_sides.length)];
		x=vx+uniform01()-.5;
		y=vy+uniform01()-.5;
		z=vz+uniform01()-.5;
		switch(side){
			case 0: x=vx+.5; break;
			case 1: x=vx-.5; break;
			case 2: y=vy+.5; break;
			case 3: y=vy-.5; break;
			case 4: z=vz+.5; break;
			case 5: z=vz-.5; break;
			default:break;
		}
		col=icol|0xff000000;
	}
}

struct BlockDamage_t{
	int x, y, z;
	ubyte damage;
	bool broken;
	ubyte orig_shade, new_shade;
	uint timer;
	DamageParticle_t[] particles;
	this(uint ix, uint iy, uint iz){
		x=ix; y=iy; z=iz;
		orig_shade=Voxel_GetShade(ix, iy, iz);
		damage=0;
		timer=SDL_GetTicks();
	}
	uint Get_DmgParticleCount(){
		return touint(tofloat(damage)*tofloat(MaxDamageParticlesPerBlock)/255.0);
	}
	bool Heal(ubyte val){
		if(val>=damage){
			damage=0;
			new_shade=orig_shade;
			UpdateVoxel();
			_Register_Lighting_BBox(x, y, z);
			return true;
		}
		damage-=val;
		new_shade=cast(ubyte)(orig_shade-orig_shade*damage/255);
		uint newc=Get_DmgParticleCount();
		if(particles.length>newc)
			particles.length=newc;
		UpdateVoxel();
		return false;
	}
	void Damage(ubyte val, Vector3_t *particle_pos){
		timer=SDL_GetTicks();
		uint[] free_sides;
		{
			for(uint side=0; side<6; side++){
				if(Valid_Coord(x+toint(side==0)-toint(side==1), y+toint(side==2)-toint(side==3), z+toint(side==4)-toint(side==5)))
					if(!Voxel_IsSolid(x+toint(side==0)-toint(side==1), y+toint(side==2)-toint(side==3), z+toint(side==4)-toint(side==5)))
						free_sides~=side;
			}
		}
		if(255-val<=damage){
			broken=true;
		}
		else{
			damage+=val;
		}
		if(!particle_pos){
			uint newc=Get_DmgParticleCount();
			if(newc!=particles.length){
				uint oldlen=cast(uint)particles.length;
				particles.length=newc;
				for(uint i=oldlen; i<newc; i++){
					particles[i].Init(x, y, z, 0, free_sides);
				}
			}
		}
		else{
			particles.length++;
			particles[$-1].x=particle_pos.x;
			particles[$-1].y=particle_pos.y;
			particles[$-1].z=particle_pos.z;
		}
		new_shade=cast(ubyte)(orig_shade-orig_shade*damage/255);
		UpdateVoxel();
	}
	version(LDC){
		void UpdateVoxel(){
			Voxel_SetShade(x, y, z, new_shade);
		}
	}
	else{
		pragma(inline)void UpdateVoxel(){
			Voxel_SetShade(x, y, z, new_shade);
		}
	}
}

BlockDamage_t[uint] BlockDamage;

void Damage_Block(PlayerID_t player_id, uint xpos, uint ypos, uint zpos, ubyte val, Vector3_t *particle_pos){
	uint col=Voxel_GetColor(xpos, ypos, zpos);
	uint hash=Hash_Coordinates(xpos, ypos, zpos);
	if(Voxel_IsWater(xpos, ypos, zpos)){
		for(uint side=0; side<4; side++){
			Create_Particles(Vector3_t(xpos+toint(cast(bool)(side&1)), ypos, zpos+toint(cast(bool)(side&2)))
			, Vector3_t(0.0), 1.0, .1, 1, [col], 25);
		}
		return;
	}
	BlockDamage_t *dmg=hash in BlockDamage;
	if(!dmg){
		BlockDamage[hash]=BlockDamage_t(xpos, ypos, zpos);
		dmg=hash in BlockDamage;
	}
	uint old_dmg=dmg.damage;
	dmg.Damage(val, particle_pos);
	uint dmgdiff=dmg.damage-old_dmg;
	for(uint side=0; side<6; side++){
		Create_Particles(Vector3_t(xpos+toint(cast(bool)(side&1)), ypos+toint(cast(bool)(side&2)), zpos+toint(cast(bool)(side&4)))
		, Vector3_t(0.0), 1.0, .1, dmgdiff/3/6, [col]);
	}
	if(dmg.broken){
		if(player_id==LocalPlayerID){
			BlockBreakPacketLayout packet;
			packet.player_id=LocalPlayerID;
			packet.break_type=0;
			packet.x=cast(ushort)xpos; packet.y=cast(ushort)ypos; packet.z=cast(ushort)zpos;
			Send_Packet(BlockBreakPacketID, packet);
		}
	}
}

void Break_Block(PlayerID_t player_id, ubyte break_type, uint xpos, uint ypos, uint zpos){
	if(!break_type){
		uint col=Voxel_GetColor(xpos, ypos, zpos);
		uint x, y, z;
		uint particle_amount=touint(1.0/BlockBreakParticleSize)+1;
		for(x=0; x<particle_amount; x++){
			for(y=0; y<particle_amount; y++){
				for(z=0; z<particle_amount; z++){
					BlockBreakParticles.length++;
					Particle_t *p=&BlockBreakParticles[$-1];
					p.vel=Vector3_t(uniform01()*(uniform(0, 2)?1.0:-1.0)*.075, 0.0, uniform01()*(uniform(0, 2)?1.0:-1.0)*.075);
					p.pos=Vector3_t(tofloat(xpos)+tofloat(x)*BlockBreakParticleSize,
					tofloat(ypos)+tofloat(y)*BlockBreakParticleSize,
					tofloat(zpos)+tofloat(z)*BlockBreakParticleSize);
					p.col=col;
					p.timer=uniform(550, 650);
				}
			}
		}
	}
	Voxel_Remove(xpos, ypos, zpos);
	uint hash=Hash_Coordinates(xpos, ypos, zpos);
	if(hash in BlockDamage)
		BlockDamage.remove(hash);
}

struct RayCastResult_t{
	int x, y, z;
	float colldist;
	uint collside;
}

float rcsgn(float val){
	if(val>0.0)
		return 1.0;
	if(val<0.0)
		return -1.0;
	return 1.0;
}

RayCastResult_t RayCast(Vector3_t pos, Vector3_t dir, float length){
	Vector3_t dst=pos+dir*length;
	int x=cast(int)pos.x, y=cast(int)pos.y, z=cast(int)pos.z;
	int dstx=cast(int)dst.x, dsty=cast(int)dst.y, dstz=cast(int)dst.z;
	int opxd=cast(int)(dir.x>0.0), opyd=cast(int)(dir.y>0.0), opzd=cast(int)(dir.z>0.0);
	float invxd=dir.x ? 1.0/dir.x : (10e10), invyd=dir.y ? 1.0/dir.y : (10e10), invzd=dir.z ? 1.0/dir.z : (10e10);
	int xdsgn=cast(int)rcsgn(dir.x), ydsgn=cast(int)rcsgn(dir.y), zdsgn=cast(int)rcsgn(dir.z);
	uint collside=0; float colldist=0.0;
	bool hit_voxel=false;
	uint loops=cast(uint)(length*5.0);
	while(x!=dstx || y!=dsty || z!=dstz){
		if(!Valid_Coord(x, y, z)){
			hit_voxel=true;
			break;
		}
		if(Voxel_IsSolid(x, y, z)){
			hit_voxel=true;
			break;
		}
		float xdist=(cast(float)(x+opxd)-pos.x)*invxd;
		float ydist=(cast(float)(y+opyd)-pos.y)*invyd;
		float zdist=(cast(float)(z+opzd)-pos.z)*invzd;
		if(xdist<ydist){
			if(xdist<zdist){
				collside=1;
				colldist=xdist;
				x+=xdsgn;
			}
			else{
				collside=3;
				colldist=zdist;
				z+=zdsgn;
			}
		}
		else{
			if(ydist<zdist){
				collside=2;
				colldist=ydist;
				y+=ydsgn;
			}
			else{
				collside=3;
				colldist=zdist;
				z+=zdsgn;
			}
		}
		if(!loops){
			writeflnlog("Warning: DDA raycasting results in an infinite loop (%s, %s)", dir, length);
			break;
		}
		loops--;
	}
	if(!hit_voxel)
		collside=0;
	return RayCastResult_t(x, y, z, colldist, collside);
}

struct Object_t{
	uint index;
	Model_t *model;
	ubyte minimap_img;
	uint color;
	bool modify_model, enable_bullet_holes, send_hits;
	bool visible;
	bool Is_Solid;
	float weightfactor, bouncefactor, frictionfactor;
	Vector3_t acl, pos, vel, rot, density;
	//Maybe move this in its own struct - I'm planning even more advanced vertex stuff
	Vector3_t[] Vertices;
	bool[3][] Vertex_Collisions;
	bool[3] Collision;

	DamageParticle_t[] particles;
	
	void Init(uint initindex){
		index=initindex;
		Vertices=[Vector3_t(0.0, 0.0, 0.0)];
		Vertex_Collisions.length=1;
		if(DamagedObjects.canFind(index))
			DamagedObjects.remove(index);
		if(Solid_Objects.canFind(index))
			Solid_Objects.remove(index);
		if(Hittable_Objects.canFind(index))
			Hittable_Objects.remove(index);
		vel=Vector3_t(0.0, 0.0, 0.0); rot=vel; acl=vel;
	}
	
	void Update(){
		if(Vertex_Collisions.length!=Vertices.length)
			Vertex_Collisions.length=Vertices.length;
		Vector3_t deltapos=Check_Vertex_Collisions();
		Update_Position(deltapos);
	}
	
	void Update_Position(Vector3_t deltapos){
		bool collision=false;
		if(!Collision[0]){
			pos.x+=deltapos.x;
			vel.x+=acl.x;
		}
		else{
			vel.x*=-bouncefactor;
			collision=true;
		}
		if(!Collision[1]){
			pos.y+=deltapos.y;
			vel.y+=acl.y;
			vel.y+=(1.0+weightfactor*.001)*WorldSpeed*Gravity*(weightfactor!=0);
		}
		else{
			vel.y*=-bouncefactor;
			collision=true;
		}
		if(!Collision[2]){
			pos.z+=deltapos.z;
			vel.z+=acl.z;
		}
		else{
			vel.z*=-bouncefactor;
			collision=true;
		}
		if(collision)
			vel*=bouncefactor;
		else
			vel/=1.0+frictionfactor*WorldSpeed;
	}
	
	Vector3_t Check_Vertex_Collisions(){
		Vector3_t deltapos=vel*WorldSpeed;
		bool[3] collision=[false, false, false];
		foreach(uint i, ref model_vertex; Vertices){
			Vector3_t worldvertex=model_vertex.rotate_raw(rot)+pos;
			Vector3_t vertexdelta=deltapos;
			Vertex_Collisions[i]=Check_Vertex_Collision(worldvertex, &vertexdelta);
			bool[3] coll=Vertex_Collisions[i];
			if(vertexdelta.length<deltapos.length)
				deltapos=vertexdelta;
			collision[0]|=coll[0];
			collision[1]|=coll[1];
			collision[2]|=coll[2];
		}
		Collision=collision;
		return deltapos;
	}
	
	bool[3] Check_Vertex_Collision(Vector3_t vertex, Vector3_t *deltapos){
		Vector3_t vpos=vertex;
		float poslen=deltapos.length;
		Vector3_t deltadir=deltapos.abs();
		Vector3_t npos=vertex;
		for(uint i=0; i<max(toint(poslen), 1); i++){
			if(poslen<1.0)
				deltadir*=poslen;
			npos=vpos+deltadir;
			bool[3] coll=Check_Lowv_Vertex_Collision(vpos, npos);
			if(coll[0] || coll[1] || coll[2]){
				*deltapos=vpos-vertex;
				return coll;
			}
			vpos=npos;
		}
		*deltapos=npos-vertex;
		return [false, false, false];
	}
	
	bool[3] Check_Lowv_Vertex_Collision(Vector3_t oldpos, Vector3_t newpos){
		if(!Collides_At(newpos.x, newpos.y, newpos.z))
			return [false, false, false];
		bool[3] collsides=[false, false, false];
		int cx=toint(oldpos.x), cy=toint(oldpos.y), cz=toint(oldpos.z);
		int nx=toint(newpos.x), ny=toint(newpos.y), nz=toint(newpos.z);
		collsides[0]|=Collides_At(nx, cy, cz);
		collsides[1]|=Collides_At(cx, ny, cz);
		collsides[2]|=Collides_At(cx, cy, nz);
		return collsides;
	}

	bool Collides_At(T1, T2, T3)(T1 x, T2 y, T3 z){
		return Voxel_Collides(touint(x), touint(y), touint(z), index);
	}
	bool Solid_At(XT, YT, ZT)(XT x, YT y, ZT z){
		return Contains(x, y, z);
	}
	bool Contains(XT, YT, ZT)(XT x, YT y, ZT z){
		if(!visible)
			return false;
		Vector3_t size=density*Vector3_t(model.xsize, model.ysize, model.zsize);
		Vector3_t startpos=pos-size/2.0, endpos=pos+size/2.0;
		return x>=startpos.x && x<endpos.x && y>=startpos.y && y<endpos.y && z>=startpos.z && z<endpos.z;
	}
	void Damage(Vector3_t particle_pos){
		particles.length++;
		DamageParticle_t *prtcl=&particles[$-1];
		prtcl.x=particle_pos.x; prtcl.y=particle_pos.y; prtcl.z=particle_pos.z; prtcl.col=0;
		if(!DamagedObjects.canFind(index))
			DamagedObjects~=index;
	}
	
	float Collision_GetMinY(TX, TY, TZ)(TX x, TY y, TZ z){
		return pos.y-density.y*tofloat(model.ysize)/2.0;
	}
}

Object_t[] Objects;
uint[] DamagedObjects;

bool Valid_Coord(T)(T x, T y, T z){
	return x>=0 && x<MapXSize && y>=0 && y<MapYSize && z>=0 && z<MapZSize;
}

Vector3_t Validate_Coord(immutable in Vector3_t coord){
	return Vector3_t(max(min(coord.x, MapXSize-1), 0), max(min(coord.y, MapYSize-1), 0), max(min(coord.z, MapZSize-1), 0));
}

void On_Map_Loaded(){
	Set_Sun(Vector3_t(MapXSize, MapYSize, MapZSize)/2.0+Vector3_t(60.0, 15.0, 0.0).RotationAsDirection(), 1.0);
}
