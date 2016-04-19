import derelict.sdl2.sdl;
import std.conv;
import std.math;
import std.random;
import packettypes;
import vector;
import renderer;
import misc;
import gfx;
import ui;
import protocol;

float Gravity=5.0;
float AirFriction=.24;
float GroundFriction=2.0;
float CrouchFriction=5.0;
//Inb4 SMB
float PlayerJumpPower=6.0;
float PlayerWalkSpeed=1.0;
float WorldSpeedRatio=.5;

struct Player_t{
	PlayerID_t player_id;
	string name;
	bool Spawned;
	bool InGame;
	Vector3_t pos, vel, acl;
	Vector3_t dir;
	TeamID_t team;
	bool Go_Forwards, Go_Back, Go_Left, Go_Right;
	bool Jump, Crouch;
	bool Use_Object;
	bool KeysChanged;
	bool[3] CollidingSides;
	//Remove the following line if you don't need it and replaced it with something better
	int Model; int Gun_Model; int Arm_Model;
	uint Gun_Timer;
	Item_t[] items;
	ubyte[] item_types;
	uint item;
	bool left_click, right_click;
	bool Reloading;
	uint color;
	void Init(string initname, PlayerID_t initplayer_id){
		name=initname;
		player_id=initplayer_id;
		Spawned=false;
		InGame=true;
		KeysChanged=false;
		pos=Vector3_t(0.0); vel=Vector3_t(0.0); acl=Vector3_t(0.0); dir=Vector3_t(1.0, 0.0, 0.0);
		Model=-1;
		Gun_Timer=0;
		Reloading=false;
	}
	void Spawn(Vector3_t location, TeamID_t spteam){
		pos=location;
		team=spteam;
		Spawned=true;
		items.length=item_types.length;
		foreach(uint i, type; item_types)
			items[i].Init(type);
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
		if(CollidingSides[1]){
			if(Go_Forwards || Go_Back){
				acl+=acdir*((!Go_Back) ? PlayerWalkSpeed : -PlayerWalkSpeed);
			}
			if(Go_Left || Go_Right){
				acl+=acdir.rotate(Vector3_t(0.0, Go_Left ? 90.0 : -90.0, 0.0))*PlayerWalkSpeed;
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
		if(Crouch){
			friction*=CrouchFriction;
		}
		if(KeysChanged)
			KeysChanged=false;
		vel+=acl*WorldSpeed*10.0;
		vel/=1.0+friction;
		CheckCollisionReturn_t coll;
		Vector3_t newpos=pos+vel*WorldSpeed;
		if(vel.length<1.0 || 1)
			coll=Check_Collisions_norc(newpos);
		else
			coll=Check_Collisions_rc(newpos);
		bool Climbed=false;
		if(coll.Collision){
			if((coll.Sides[0] || coll.Sides[2]) && !Crouch){
				Vector3_t climbpos=newpos; climbpos.y-=1.0;
				auto climbcoll=Check_Collisions_norc(climbpos);
				if(!climbcoll.Collision){
					pos.y=tofloat(toint(pos.y))-.01;
					Climbed=true;
				}
			}
			if(!Climbed)
				vel=vel.filter(!coll.Sides[0], !coll.Sides[1], !coll.Sides[2]);
		}
		pos+=vel*WorldSpeed;
		if(Climbed)
			vel*=.1;
		CollidingSides=coll.Sides;
		if(player_id==LocalPlayerID)
			Update_Position_Data();
	}
	bool Collides_At(T1, T2, T3)(T1 x, T2 y, T3 z){
		bool coll=false;
		int upx=cast(int)(x-.45), upz=cast(int)(z-.45);
		int lpx=cast(int)(x+.45), lpz=cast(int)(z+.45);
		for(uint py=cast(uint)y; py<(cast(uint)y)+3; py++){
			if(Voxel_IsSolid(cast(uint)x, py, cast(uint)z))
				return true;
			/*if(Voxel_IsSolid(upx, py, upz))
				return true;
			if(Voxel_IsSolid(upx, py, lpz))
				return true;
			if(Voxel_IsSolid(lpx, py, upz))
				return true;
			if(Voxel_IsSolid(lpx, py, lpz))
				return true;*/
		}
		return false;
	}
	uint Collides_Pos(T1, T2, T3)(T1 x, T2 y, T3 z){
		for(uint py=cast(uint)y; py<(cast(uint)y)+3; py++){
			if(Voxel_IsSolid(cast(uint)x, py, cast(uint)z))
				return py;
		}
		return 0;
	}
	//Works more or less
	CheckCollisionReturn_t Check_Collisions_norc(Vector3_t newpos){
		if(!Collides_At(newpos.x, newpos.y, newpos.z))
			return CheckCollisionReturn_t(Vector3_t(0.0), 0);
		bool[3] collsides=[false, false, false];
		int cx=cast(int)pos.x, cy=cast(int)pos.y, cz=cast(int)pos.z;
		int nx=cast(uint)newpos.x, ny=cast(uint)newpos.y, nz=cast(uint)newpos.z;
		Vector3_t collpos=pos;
		if(Collides_At(nx, cy, cz)){
			collsides[0]=true;
			collpos.x=pos.x+(cast(float)(vel.x>0.0));
		}
		if(Collides_At(cx, ny, cz)){
			collsides[1]=true;
			collpos.y=pos.y+(cast(float)(vel.y>0.0));
		}
		if(Collides_At(cx, cy, nz)){
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
			for(uint py=y; py<=y+3; y++)
				if(Voxel_IsSolid(x, py, z))
					break;
		}
		return CheckCollisionReturn_t(Vector3_t(x, y, z), collsides);
	}
	void Use_Item(){
		uint current_tick=SDL_GetTicks();
		Item_t *current_item=&items[item];
		if(current_tick-current_item.use_timer<ItemTypes[current_item.type].use_delay)
			return;
		current_item.use_timer=current_tick;
		if(!ItemTypes[current_item.type].is_weapon)
			return;
		if(Reloading || !current_item.amount1)
			return;
		ItemType_t *itemtype=&ItemTypes[current_item.type];
		foreach(PlayerID_t pid, ref plr; Players){
			if(pid==player_id)
				continue;
			KV6Sprite_t[] sprites=Get_Player_Sprites(pid);
			foreach(ubyte spindex, ref spr; sprites){
				//For future
				Vector3_t dummy1; KV6Voxel_t *dummy2;
				if(SpriteHitScan(&spr, pos, dir, dummy1, dummy2)){
					if(player_id==LocalPlayerID){
						//dummy2.color=0x00ff0000;
						PlayerHitPacketLayout packet;
						packet.player_id=pid;
						packet.hit_sprite=spindex;
						Send_Packet(PlayerHitPacketID, packet);
					}
				}
			}
		}
		if(ItemTypes[current_item.type].damage_blocks){
			auto rcp=RayCast(pos, dir, 128.0);
			if(rcp.collside){
				Damage_Block(rcp.x, rcp.y, rcp.z, .1);
			}
		}
		if(ItemTypes[current_item.type].repeated_use)
			current_item.use_timer=current_tick;
		float xrecoil=itemtype.recoil_xc+itemtype.recoil_xm*uniform01();
		float yrecoil=itemtype.recoil_yc+itemtype.recoil_ym*uniform01();
		if(player_id==LocalPlayerID){
			CameraRot.y+=yrecoil;
			CameraRot.x+=xrecoil;
		}
		dir.rotate(Vector3_t(0, yrecoil, xrecoil));
		current_item.amount1--;
	}
	void Switch_Tool(ubyte tool_id){
		item=tool_id;
	}
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
	void Init(string initname, TeamID_t team_id, ubyte[4] initcolor){
		id=team_id;
		name=initname;
		color=initcolor;
	}
}

Team_t[] Teams;

void Init_Team(string name, TeamID_t team_id, ubyte[4] color){
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
	bool is_weapon;
	bool damage_blocks;
	bool repeated_use;
	float spread_c, spread_m;
	float recoil_xc, recoil_xm;
	float recoil_yc, recoil_ym;
	ubyte model_id;
}
ItemType_t[] ItemTypes;

struct Item_t{
	ubyte type;
	uint amount1, amount2;
	uint use_timer;
	void Init(ubyte inittype){
		type=inittype;
		use_timer=0;
		amount1=ItemTypes[type].maxamount1;
		amount2=ItemTypes[type].maxamount2;
	}
}

void Update_World(){
	uint Current_Tick=SDL_GetTicks();
	if(Last_Tick){
		float delta_t=tofloat(Current_Tick-Last_Tick)/1000.0;
		WorldSpeed=delta_t*WorldSpeedRatio;
	}
	else{
		WorldSpeed=(1.0/30.0)*WorldSpeedRatio;
	}
	foreach(ref p; Players)
		p.Update();
	foreach(ref o; Objects)
		o.Update();
	Last_Tick=Current_Tick;
}

uint Hash_Coordinates(uint x, uint y, uint z){
	return x+y*MapXSize+z*MapXSize*MapYSize;
}

//immutable uint MaxDamageParticlesPerBlock=65536;
immutable uint MaxDamageParticlesPerBlock=4096;

struct BlockDamageParticle_t{
	float x, y, z;
	void Init(uint ix, uint iy, uint iz){
		float vx=tofloat(ix)+.5, vy=tofloat(iy)+.5, vz=tofloat(iz)+.5;
		uint side=uniform(0, 3);
		float sidesgn=tofloat(toint(uniform(0, 2))*2-1)*.5;
		x=vx+uniform01()-.5;
		y=vy+uniform01()-.5;
		z=vz+uniform01()-.5;
		switch(side){
			case 0: x=vx+sidesgn; break;
			case 1: y=vy+sidesgn; break;
			case 2: z=vz+sidesgn; break;
			default:break;
		}
	}
}

struct BlockDamage_t{
	uint x, y, z;
	float damage;
	BlockDamageParticle_t[] particles;
	this(uint ix, uint iy, uint iz){
		x=ix; y=iy; z=iz;
		damage=0.0;
	}
	void Damage(float val){
		damage+=val;
		uint newc=touint(damage*tofloat(MaxDamageParticlesPerBlock));
		if(newc!=particles.length){
			uint oldlen=particles.length;
			particles.length=newc;
			for(uint i=oldlen; i<newc; i++){
				particles[i].Init(x, y, z);
			}
		}
	}
}

BlockDamage_t[uint] BlockDamage;

void Damage_Block(uint x, uint y, uint z, float val){
	uint hash=Hash_Coordinates(x, y, z);
	BlockDamage_t *dmg=hash in BlockDamage;
	if(!dmg){
		BlockDamage[hash]=BlockDamage_t(x, y, z);
		dmg=hash in BlockDamage;
	}
	dmg.Damage(val);
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
	uint loops=0;
	while(x!=dstx || y!=dsty || z!=dstz){
		if(Voxel_IsSolid(x, y, z))
			break;
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
		loops++;
		if(loops>10000){
			writeflnlog("Warning: DDA raycasting results in an infinite loop (%s, %s)", dir, length);
			break;
		}
	}
	return RayCastResult_t(x, y, z, colldist, collside);
}

struct Object_t{
	ubyte model_id;
	ubyte minimap_img;
	bool visible;
	float weightfactor, bouncefactor, frictionfactor;
	Vector3_t pos, vel, rot, density;
	
	void Update(){
		vel.y+=Gravity*WorldSpeed*weightfactor;
		vel/=1.0+AirFriction*frictionfactor;
		Vector3_t newpos=pos+vel*WorldSpeed;
		auto coll=Check_Collisions_norc(newpos);
		if(coll.Sides[0] || coll.Sides[1] || coll.Sides[2]){
			if(coll.Sides[0])
				vel.x=-vel.x;
			if(coll.Sides[1])
				vel.y=-vel.y;
			if(coll.Sides[2])
				vel.z=-vel.z;
			vel*=bouncefactor;
		}
		pos+=vel*WorldSpeed;
	}
	CheckCollisionReturn_t Check_Collisions_norc(Vector3_t newpos){
		if(!Collides_At(newpos.x, newpos.y, newpos.z))
			return CheckCollisionReturn_t(Vector3_t(0.0), 0);
		bool[3] collsides=[false, false, false];
		int cx=cast(int)pos.x, cy=cast(int)pos.y, cz=cast(int)pos.z;
		int nx=cast(uint)newpos.x, ny=cast(uint)newpos.y, nz=cast(uint)newpos.z;
		Vector3_t collpos=pos;
		if(Collides_At(nx, cy, cz)){
			collsides[0]=true;
			collpos.x=pos.x+(cast(float)(vel.x>0.0));
		}
		if(Collides_At(cx, ny, cz)){
			collsides[1]=true;
			collpos.y=pos.y+(cast(float)(vel.y>0.0));
		}
		if(Collides_At(cx, cy, nz)){
			collsides[2]=true;
			collpos.z=pos.z+(cast(float)(vel.z>0.0));
		}
		return CheckCollisionReturn_t(collpos, collsides, collsides[0] || collsides[1] || collsides[2]);
	}
	bool Collides_At(T1, T2, T3)(T1 x, T2 y, T3 z){
		return Voxel_IsSolid(touint(x), touint(y), touint(z));
	}
	
	void Check_Visibility(){
		visible=(model_id!=255) && (density.length);
	}
}

Object_t[] Objects;

bool Valid_Coord(T)(T x, T y, T z){
	return x>=0 && x<MapXSize && y>=0 && y<MapYSize && z>=0 && z<MapZSize;
}
