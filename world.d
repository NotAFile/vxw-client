import derelict.sdl2.sdl;
import std.math;
import packettypes;
import vector;
import renderer;
import misc;
import gfx;
import protocol;

struct Player_t{
	PlayerID_t player_id;
	string name;
	bool spawned;
	bool InGame;
	Vector3_t pos, vel, acl;
	Vector3_t dir;
	TeamID_t team;
	bool Go_Forwards, Go_Back, Go_Left, Go_Right;
	bool Jump, Crouch;
	bool KeysChanged;
	int Model;
	void Init(string initname, PlayerID_t initplayer_id){
		name=initname;
		player_id=initplayer_id;
		spawned=false;
		InGame=true;
		KeysChanged=false;
		pos=Vector3_t(0.0); vel=Vector3_t(0.0); acl=Vector3_t(0.0); dir=Vector3_t(1.0, 0.0, 0.0);
		Model=-1;
	}
	void Spawn(Vector3_t location, TeamID_t spteam){
		pos=location;
		team=spteam;
	}
	void Update_Physics(){
		if(KeysChanged){
			acl=Vector3_t(0.0);
			if(Go_Forwards || Go_Back){
				acl+=dir*((!Go_Back) ? 1.0 : -1.0);
			}
			if(Go_Left || Go_Right){
				acl+=dir.rotate(Vector3_t(0.0, Go_Left ? 90.0 : -90.0, 0.0));
			}
			KeysChanged=false;
		}
		vel+=acl;
	/*	if(!Voxel_IsSolid(cast(uint)pos.x, (cast(uint)pos.y)+3, cast(uint)pos.z))
			vel.y+=.5;*/
		vel*=.97;
		CheckCollisionReturn_t coll;
		if(vel.length<1.0 || 1)
			coll=Check_Collisions_norc();
		else
			coll=Check_Collisions_rc();
		//WIP, unfinished, fucked up
		/*if(coll.Side){
			pos=coll.collpos;
			vel=vel.filter(!(coll.Side&1), !(coll.Side&2), !(coll.Side&4));
		}*/
		pos+=vel*.01;
		if(player_id==LocalPlayerID)
			Update_Position_Data();
	}
	bool Collides_At(T1, T2, T3)(T1 x, T2 y, T3 z){
		bool coll=false;
		for(uint py=cast(uint)y; py<(cast(uint)y)+3; py++){
			if(Voxel_IsSolid(cast(uint)x, py, cast(uint)z))
				return true;
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
	CheckCollisionReturn_t Check_Collisions_norc(){
		Vector3_t newpos=pos+vel;
		if(!Collides_At(newpos.x, newpos.y, newpos.z))
			return CheckCollisionReturn_t(Vector3_t(0.0), 0);
		uint collsides=0;
		int cx=cast(int)pos.x, cy=cast(int)pos.y, cz=cast(int)pos.z;
		int nx=cast(uint)newpos.x, ny=cast(uint)newpos.y, nz=cast(uint)newpos.z;
		Vector3_t collpos=pos;
		if(Collides_At(nx, cy, cz)){
			collsides|=1;
			collpos.x=pos.x+(cast(float)(vel.x>0.0));
		}
		if(Collides_At(cx, ny, cz)){
			collsides|=2;
			collpos.y=pos.y+(cast(float)(vel.y>0.0));
		}
		if(Collides_At(cx, cy, nz)){
			collsides|=4;
			collpos.z=pos.z+(cast(float)(vel.z>0.0));
		}
		return CheckCollisionReturn_t(collpos, collsides);
	}
	CheckCollisionReturn_t Check_Collisions_rc(){
		Vector3_t nvel=vel.abs;
		int x=cast(int)pos.x, y=cast(int)pos.y, z=cast(int)pos.z;
		int sx=x, sy=y, sz=z;
		int dstx=cast(int)(pos.x+vel.x), dsty=cast(int)(pos.y+vel.y), dstz=cast(int)(pos.z+vel.z);
		uint opsidex=cast(uint)(pos.x>0.0), opsidey=cast(uint)(pos.y>0.0), opsidez=cast(uint)(pos.z>0.0);
		int xsgn=cast(int)sgn(vel.x), ysgn=cast(int)sgn(vel.y), zsgn=cast(int)sgn(vel.z);
		//DDA physics "raycast"
		uint collface;
		while(x!=dstx && y!=dsty && z!=dstz){
			float xsd=(cast(float)(x+opsidex)-pos.x)/nvel.x;
			float ysd=(cast(float)(y+opsidey)-pos.y)/nvel.y;
			float zsd=(cast(float)(z+opsidez)-pos.z)/nvel.z;
			if(xsd<ysd){
				if(xsd<zsd){
					x+=xsgn;
					collface=1;
				}
				else{
					z+=zsgn;
					collface=4;
				}
			}
			else{
				if(ysd<zsd){
					y+=ysgn;
					collface=2;
				}
				else{
					z+=zsgn;
					collface=4;
				}
			}
			for(uint py=y; py<=y+3; y++)
				if(Voxel_IsSolid(x, py, z))
					break;
		}
		return CheckCollisionReturn_t(Vector3_t(x, y, z), collface);
	}
}

struct CheckCollisionReturn_t{
	Vector3_t collpos;
	uint Side;
}

Player_t[] Players;

struct Team_t{
	string name;
	ubyte[3] color;
}

Team_t[] Teams;

void Init_Player(string name, PlayerID_t id){
	if(id>=Players.length)
		Players.length=id+1;
	Player_t *plr=&Players[id];
	plr.Init(name, id);
}

float WorldSpeedRatio=.1;
float WorldSpeed=1.0;
uint Last_Tick;

void Update_World(){
	uint Current_Tick=SDL_GetTicks();
	if(Last_Tick){
		uint tdist=Current_Tick-Last_Tick;
		WorldSpeed=cast(float)(tdist)*WorldSpeedRatio;
	}
	else{
		WorldSpeed=(1.0/30.0)*WorldSpeedRatio;
	}
	foreach(ref p; Players)
		p.Update_Physics();
}
