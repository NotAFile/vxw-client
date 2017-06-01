import core.stdc.stdio;

version(LDC){
	import ldc_stdlib;
}
version(GNU){
	import gdc_stdlib;
}
import derelict.sdl2.sdl;
import std.conv;
import std.math;
import std.random;
import std.algorithm;
import std.traits;
import packettypes;
import vector;
import renderer;
import renderer_templates;
import misc;
import gfx;
import snd;
import ui;
import script;
import protocol;

float Gravity=9.81/0.64;
float AirFriction=.24;
float GroundFriction=2.0;
float WaterFriction=2.5;
float CrouchFriction=5.0;
//Inb4 SMB
float PlayerJumpPower=10.0;
float PlayerWalkSpeed=1.0;
float PlayerSprintSpeed=1.5;
float WorldSpeedRatio=2.0;

Vector3_t Sun_Vector, Sun_Position;

uint Base_Visibility_Range=128, Current_Visibility_Range=128;
uint Base_Fog_Color=0x0000ffff, Current_Fog_Color=0x0000ffff;

immutable float Player_Stand_Size=2.8;
immutable float Player_Stand_Size_Eye=2.3;
immutable float Player_Crouch_Size=1.8;
immutable float Player_Crouch_Size_Eye=1.3;
immutable float Crouch_Height_Change_Speed = 0.375; //in secounds

Vector3_t Wind_Direction;

immutable uint ticks_ps = 60;

void Init_World(){
}

void UnInit_World(){
	foreach(ref p; Players)
		p.Delete();
	foreach(ref obj; Objects)
		obj.Delete();
	Players.length=0;
}

struct PlayerModel_t{
	ubyte model_id;
	Vector3_t size, offset, rotation;
	bool FirstPersonModel, Rotate;
	float WalkRotate;
}

//Coming soon: changing it to duck typing
struct AABB_t {
	union{
		struct{
			float min_x = 0.0F, min_y = 0.0F, min_z = 0.0F;
		}
		Vector3_t minvec;
	}
	union{
		struct{
			float max_x = 0.0F, max_y = 0.0F, max_z = 0.0F;
		}
		Vector3_t maxvec;
	}
	
	this(T1, T2)(T1 vec1, T2 vec2){
		static if(isVectorLike!T1 && isVectorLike!T2){
			minvec=Vector3_t(min(vec1.x, vec2.x), min(vec1.y, vec2.y), min(vec1.z, vec2.z));
			maxvec=Vector3_t(max(vec1.x, vec2.x), max(vec1.y, vec2.y), max(vec1.z, vec2.z));
		}
	}
	this(TX1, TY1, TZ1, TX2, TY2, TZ2)(TX1 x1, TY1 y1, TZ1 z1, TX2 x2, TY2 y2, TZ2 z2){
		min_x=min(x1, x2); max_x=max(x1, x2);
		min_y=min(y1, y2); max_y=max(y1, y2);
		min_z=min(z1, z2); max_z=max(z1, z2);
	}
	
	/*Taken from (public domain code) (btw really great code, gj guys):
	    "Fast Ray-Axis Aligned Bounding Box Overlap Tests With Pluecker Coordinates" by
		Jeffrey Mahovsky and Brian Wyvill
		Department of Computer Science, University of Calgary
	*/
	TR Intersect(TP, TD, TR=real)(TP pos, TD dir){
		if(!dir.x && ((pos.x<minvec.x) || (pos.x>maxvec.x)))
			return TR.nan;
		if(!dir.y && ((pos.y<minvec.y) || (pos.y>maxvec.y)))
			return TR.nan;
		if(!dir.z && ((pos.z<minvec.z) || (pos.z>maxvec.z)))
			return TR.nan;
		return Intersect_invdir(pos, TD(1.0)/dir);
	}
	
	TR Intersect_invdir2(TP, TD, TR=real)(TP pos, TD dir){
		auto tmin=(minvec-pos)*dir, tmax=(maxvec-pos)*dir;
		if(tmin.x>tmax.x)swap(tmin.x, tmax.x);
		if(tmin.y>tmax.y)swap(tmin.y, tmax.y);
		if(tmin.z>tmax.z)swap(tmin.z, tmax.z);
		if(tmin.x>tmax.y || tmin.y>tmax.x)
			return TR.nan;
		if(min(tmin.x, tmin.y)>tmax.z || max(tmax.x, tmax.y)<tmin.z)
			return TR.nan;
		return min(tmin.x, tmin.y, tmin.z);
	}
	
	TR Intersect_invdir(TP, TD, TR=real)(TP pos, TD dir){
		TR tnear=-TR.max, tfar=TR.max;
		if(!dir.x){
			if((pos.x<minvec.x) || (pos.x>maxvec.x))
				return TR.nan;
		}
		else{
			TR t1=(minvec.x-pos.x)*dir.x;
			TR t2=(maxvec.x-pos.x)*dir.x;
			if(t1>t2)
				swap(t1, t2);
			if(t1>tnear)
				tnear=t1;
			if(t2<tfar)
				tfar=t2;
			if(tnear>tfar)
				return TR.nan;
			if(tfar<0.0)
				return TR.nan;
		}
		if(!dir.y){
			if((pos.y<minvec.y) || (pos.y>maxvec.y))
				return TR.nan;
		}
		else{
			TR t1=(minvec.y-pos.y)*dir.y;
			TR t2=(maxvec.y-pos.y)*dir.y;
			if(t1>t2)
				swap(t1, t2);
			if(t1>tnear)
				tnear=t1;
			if(t2<tfar)
				tfar=t2;
			if(tnear>tfar)
				return TR.nan;
			if(tfar<0.0)
				return TR.nan;
		}
		if(!dir.z){
			if((pos.z<minvec.z) || (pos.z>maxvec.z))
				return TR.nan;
		}
		else{
			TR t1=(minvec.z-pos.z)*dir.z;
			TR t2=(maxvec.z-pos.z)*dir.z;
			if(t1>t2)
				swap(t1, t2);
			if(t1>tnear)
				tnear=t1;
			if(t2<tfar)
				tfar=t2;
			if(tnear>tfar)
				return TR.nan;
			if(tfar<0.0)
				return TR.nan;
		}
		return tnear;
	}
	
	void set_center(float x, float y, float z) {
		float size_x = max_x-min_x;
		float size_y = max_y-min_y;
		float size_z = max_z-min_z;
		min_x = x-size_x/2;
		min_y = y-size_y/2;
		min_z = z-size_z/2;
		max_x = x+size_x/2;
		max_y = y+size_y/2;
		max_z = z+size_z/2;
	}
	
	void set_bottom_center(float x, float y, float z) {
		float size_x = max_x-min_x;
		float size_y = max_y-min_y;
		float size_z = max_z-min_z;
		min_x = x-size_x/2;
		min_y = y-size_y;
		min_z = z-size_z/2;
		max_x = x+size_x/2;
		max_y = y;
		max_z = z+size_z/2;
	}
	
	void set_size(float x, float y, float z) {
		max_x = min_x+x;
		max_y = min_y+y;
		max_z = min_z+z;
	}
	
	bool intersection(AABB_t* b) {
		return (min_x <= b.max_x && b.min_x <= max_x) && (min_y <= b.max_y && b.min_y <= max_y) && (min_z <= b.max_z && b.min_z <= max_z);
	}
	
	bool intersection_terrain(alias is_player=false)() {
		AABB_t terrain_cube;

		int min_x = cast(int)floor(min_x);
		int min_y = cast(int)floor(min_y);
		int min_z = cast(int)floor(min_z);

		int max_x = cast(int)ceil(max_x);
		int max_y = cast(int)ceil(max_y);
		int max_z = cast(int)ceil(max_z);

		for(int x=min_x;x<max_x;x++) {
			for(int z=min_z;z<max_z;z++) {
				for(int y=min_y;y<max_y;y++) {
					static if(is_player){
						if(y<0)
							continue;
					}
					if(x<0 || z<0 || x>=MapXSize || z>=MapZSize || y>=MapYSize || (y!=MapYSize-1 && Coord_Collides(x,y,z))) {
						terrain_cube.min_x = x;
						terrain_cube.min_y = y;
						terrain_cube.min_z = z;
						terrain_cube.max_x = x+1;
						terrain_cube.max_y = y+1;
						terrain_cube.max_z = z+1;
						if(intersection(&terrain_cube)) {
							return true;
						}
					}
				}
			}
		}
		return false;
	}
	bool Contains(T)(T vec) if(isVector_t!T){
		return vec.x>=minvec.x && vec.y>=minvec.y && vec.z>=minvec.z && vec.x<maxvec.x && vec.y<maxvec.y && vec.z<maxvec.z;
	}

	const R[8] Edges(R=Vector3_t)(){
		return[
			R(minvec.x, minvec.y, minvec.z), R(maxvec.x, minvec.y, minvec.z), R(minvec.x, maxvec.y, minvec.z), R(maxvec.x, maxvec.y, minvec.z),
			R(minvec.x, minvec.y, maxvec.z), R(maxvec.x, minvec.y, maxvec.z), R(minvec.x, maxvec.y, maxvec.z), R(maxvec.x, maxvec.y, maxvec.z)
		];
	}
}

template ArrayBaseType(T : T[])
{
  alias T ArrayBaseType;
}

struct Player_t{
	PlayerID_t player_id;
	string name;
	bool Spawned;
	bool InGame;
	uint score, gmscore;
	
	PlayerModel_t[] models;
	
	Vector3_t pos, vel;
	Vector3_t dir;
	TeamID_t team;
	bool Go_Forwards, Go_Back, Go_Left, Go_Right;
	bool Jump, LastJump, Crouch, TryUnCrouch, Sprint;
	bool Use_Object;
	bool KeysChanged;
	bool[3] CollidingSides;
	Vector3_t ColVel;
	//Remove the following line if you don't need it and replaced it with something better
	int Model; int Gun_Model; int Arm_Model;
	uint Gun_Timer;
	Item_t[] items;
	Item_t *equipped_item;
	ubyte[] selected_item_types;
	uint item_animation_counter;
	Vector3_t current_item_offset;
	bool left_click, right_click;
	uint color;
	Object_t *standing_on_obj, stood_on_obj;
	
	float Walk_Forwards_Timer, Walk_Sidewards_Timer;
	float prev_fwalk_sign, prev_swalk_sign;
	
	bool airborne, airborne_old;
	float airborne_start = 0.0F;
	uint physics_start;
	uint ticks = 0;
	uint last_climb = 0;
	float crouch_offset = 0.0;
	
	SoundSource_t sndsource;
	
	this(PlayerID_t pid){
		player_id=pid;
		sndsource=SoundSource_t(0);
	}

	void Init(string initname){
		name=initname;
		team=255;
		Spawned=false;
		InGame=true;
		KeysChanged=false;
		pos=Vector3_t(0.0); vel=Vector3_t(0.0); dir=Vector3_t(1.0, 0.0, 0.0);
		Model=-1;
		Gun_Timer=0;
		current_item_offset=Vector3_t(0.0);
		score=0; gmscore=0;
		Walk_Forwards_Timer=0.0; Walk_Sidewards_Timer=0.0;
		if(items.length)
			equipped_item=&items[0];
		else
			equipped_item=null;
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
		airborne = false;
        airborne_old = false;
        airborne_start = 0.0F;
        ticks = 0;
        last_climb = 0;
        crouch_offset = 0.0;
        Crouch = false;
        TryUnCrouch = false;
        vel.x = vel.y = vel.z = 0.0F;
		physics_start = PreciseClock_ToMSecs(PreciseClock());
	}
	
	void On_Disconnect(){
		InGame=false;
		Spawned=false;
		if(Players.length==this.player_id){
			Players.length--;
		}
	}
	
	void Delete(){
		if(equipped_item)
			equipped_item.equipped=VoidPlayerID;
		sndsource.UnInit();
	}
	
	//Code by ByteBit (edited by lecom)
	void Update(float dt=WorldSpeed){
		if(Spawned){
			uint ticks_should_have = cast(uint)floor((PreciseClock_ToMSecs(PreciseClock())-physics_start)/1000.0F*ticks_ps);
			if(ticks<ticks_should_have) {
				while(ticks<ticks_should_have) {
					Update_Physics();
				}
				if(player_id==LocalPlayerID) {
					Update_Position_Data();
				}
			}
			if(left_click){
				if(player_id!=LocalPlayerID || !Menu_Mode)
					Use_Item();
			}
			if(equipped_item){
				if(PreciseClock_ToMSecs(PreciseClock())-equipped_item.use_timer>ItemTypes[equipped_item.type].use_delay){
					equipped_item.last_recoil=0.0;
				}
			}
			foreach(ref item; items){
				item.Update(dt);
			}
			if(dir.length){
				float l=vel.filter(true, false, true).dot(dir.filter(true, false, true))*WorldSpeed;
				if(fabs(l)>.00001){
					Walk_Forwards_Timer+=l;
				}
				else{
					Walk_Forwards_Timer=0.0;
				}
				l=vel.filter(true, false, true).dot(dir.rotate_raw(Vector3_t(0.0, 90.0, 0.0)).filter(true, false, true))*WorldSpeed;
				if(fabs(l)>.00001){
					Walk_Sidewards_Timer+=l;
				}
				else{
					Walk_Sidewards_Timer=0.0;
				}
			}
			else{
				Walk_Forwards_Timer=0.0; Walk_Sidewards_Timer=0.0;
			}
			sndsource.SetPos(pos);
			sndsource.SetVel(vel);
			float fwalk_sign=sgn(sin(Walk_Forwards_Timer)), swalk_sign=sgn(sin(Walk_Sidewards_Timer));
			if(((fwalk_sign!=prev_fwalk_sign && fwalk_sign && prev_fwalk_sign) || (swalk_sign!=prev_swalk_sign && swalk_sign && prev_swalk_sign)) && !airborne){
				if(ProtocolBuiltin_StepSound!=VoidSoundID)
					sndsource.Play_Sound(Mod_Sounds[ProtocolBuiltin_StepSound]);
			}
			if(fwalk_sign)
				prev_fwalk_sign=fwalk_sign;
			if(swalk_sign)
				prev_swalk_sign=swalk_sign;
			if(!Walk_Forwards_Timer)
				prev_fwalk_sign=0.0;
			if(!Walk_Sidewards_Timer)
				prev_swalk_sign=0.0;
		} else {
			physics_start = PreciseClock_ToMSecs(PreciseClock());
		}
	}
	
	Vector3_t CameraPos() {
		Vector3_t ret = Vector3_t(pos);
		ret.y -= Player_Crouch_Size_Eye;
		ret.y += crouch_offset*(Player_Stand_Size_Eye-Player_Crouch_Size_Eye);
		if(PreciseClock_ToMSecs(PreciseClock())-last_climb<150) {
			ret.y += 1.0F-(PreciseClock_ToMSecs(PreciseClock())-last_climb)/150.0F;
		}
		return ret;
	}
	
	//Code by ByteBit (edited by lecom)
	void Update_Physics() {
		Vector3_t prev_pos=CameraPos();
		float dt = 1.0F/(cast(float)ticks_ps);
		AABB_t player_aabb;
		
		if(Crouch && TryUnCrouch) {
			player_aabb.set_size(0.75F,Player_Stand_Size,0.75F);
			player_aabb.set_bottom_center(pos.x,pos.y,pos.z);
			if(!player_aabb.intersection_terrain!true()) {
				Crouch = TryUnCrouch = false;
			} else {
				player_aabb.set_bottom_center(pos.x,pos.y+0.9F,pos.z);
				if(!player_aabb.intersection_terrain!true()) {
					pos.y += 0.9F;
					Crouch = TryUnCrouch = false;
				}
			}
		}
		
		crouch_offset += ((Crouch && crouch_offset<0.0)?dt/Crouch_Height_Change_Speed:0.0) + ((!Crouch && crouch_offset>-1.0)?-dt/Crouch_Height_Change_Speed:0.0);
		
		player_aabb.set_size(0.75F,Crouch?Player_Crouch_Size:Player_Stand_Size,0.75F);
		
		player_aabb.set_bottom_center(pos.x,pos.y+vel.y*dt,pos.z);
		if(!player_aabb.intersection_terrain!true()) {
			pos.y += vel.y*dt;
			vel.y += dt*Gravity*2.0F;
		} else {
			vel.y = 0.0F;
		}
		
		player_aabb.set_bottom_center(pos.x,pos.y+0.1F,pos.z);
		airborne_old = airborne;
		airborne = !player_aabb.intersection_terrain!true();
		
		if(airborne && !airborne_old) { //fall or jump start
			airborne_start = pos.y;
		} else {
			if(!airborne && airborne_old) { //fall or jump end
				float d = pos.y-airborne_start;
				if(ProtocolBuiltin_StepSound!=VoidSoundID)
					sndsource.Play_Sound(Mod_Sounds[ProtocolBuiltin_StepSound]);
				debug{
					if(d>0.0F) {
						printf("Fall distance: %f\n",d);
					}
				}
			}
		}
		
		if(!airborne && Jump && !LastJump) {
			vel.y = -(PlayerJumpPower - ( Crouch ? 2.0f : 0.0f));
			LastJump = true;
		} else {
			if(!Jump) {
				LastJump = false;
			}
		}
		
		float max_speed = 7.5F;
		if(airborne) {
			max_speed *= 0.2F;
		} else {
			if(Crouch) {
				max_speed *= 0.3F;
			} else {
				if(Sprint) {
					max_speed *= 1.3F;
				}
			}
		}
		
		float l2 = sqrt(dir.x*dir.x+dir.z*dir.z);
		float d_x2 = dir.x/l2;
		float d_z2 = dir.z/l2;
		float x = 0.0F, z = 0.0F;
		if(Go_Forwards) {
			x += d_x2;
			z += d_z2;
		} else {
			if(Go_Back) {
				x -= d_x2;
				z -= d_z2;
			}
		}
		
		if(Go_Left) {
			x += d_z2;
			z -= d_x2;
		} else {
			if(Go_Right) {
				x -= d_z2;
				z += d_x2;
			}
		}
		
		x *= 30.0F*dt;
		z *= 30.0F*dt;
		if((Go_Forwards || Go_Back) && (Go_Left || Go_Right)) {
			x *= 1.4142F;
			z *= 1.4142F;
		}
		
		if((vel.x+x)*(vel.x+x)+(vel.z+z)*(vel.z+z)<=max_speed*max_speed) {
			vel.x += x;
			vel.z += z;
		}
		
		if(vel.x*vel.x+vel.z*vel.z<0.02F) {
			vel.x = vel.z = 0.0F;
		}
		
		
		if(vel.x*vel.x+vel.z*vel.z>0.0F) {
			float l = sqrt(vel.x*vel.x+vel.z*vel.z);
			float d_x = vel.x/l;
			float d_z = vel.z/l;
			if((Go_Forwards || Go_Back || Go_Left || Go_Right)) {
				vel.x -= 1.6F*Gravity*d_x*dt/(airborne?4:1);
				vel.z -= 1.6F*Gravity*d_z*dt/(airborne?4:1);
			} else {
				vel.x -= 2.0F*Gravity*d_x*dt/(airborne?4:1);
				vel.z -= 2.0F*Gravity*d_z*dt/(airborne?4:1);
			}
		}
		
		bool blocked_in_x = false, blocked_in_z = false;
		
		//movement in x and y direction by velocity
		player_aabb.set_bottom_center(pos.x+vel.x*dt,pos.y,pos.z);
		if(player_aabb.intersection_terrain!true()) {
			blocked_in_x = true;
		}
		player_aabb.set_bottom_center(pos.x,pos.y,pos.z+vel.z*dt);
		if(player_aabb.intersection_terrain!true()) {
			blocked_in_z = true;
		}
		  
		if(!airborne && !Jump && !Crouch && !TryUnCrouch && !Sprint) {
			bool climb = false;
			
			player_aabb.set_bottom_center(pos.x+vel.x*dt,pos.y-1.0F,pos.z);
			if(!player_aabb.intersection_terrain!true() && blocked_in_x) {
				climb = true;
				blocked_in_x = false;
			}
			
			player_aabb.set_bottom_center(pos.x,pos.y-1.0F,pos.z+vel.z*dt);
			if(!player_aabb.intersection_terrain!true() && blocked_in_z) {
				climb = true;
				blocked_in_z = false;
			}
			
			if(climb) {
				pos.y--;
				last_climb = PreciseClock_ToMSecs(PreciseClock());
			}
		}
		
		if(blocked_in_x) {
			vel.x = 0.0F;
		} else {
			pos.x += vel.x*dt;
		}
		
		if(blocked_in_z) {
			vel.z = 0.0F;
		} else {
			pos.z += vel.z*dt;
		}
		ticks++;
		if(player_id==LocalPlayerID){
			if(LocalPlayerScoping()){
				float v=(CameraPos()-prev_pos).length*300.0*dt;
				MouseRot.x+=v*(uniform01()*2.0-1.0);
				MouseRot.y+=v*(uniform01()*2.0-1.0);
			}
		}
	}
	void Use_Item(){
		if(!equipped_item)
			return;
		auto current_tick=PreciseClock_ToMSecs(PreciseClock());
		Item_t *current_item=equipped_item;
		ItemType_t *itemtype=&ItemTypes[current_item.type];
		auto timediff=current_tick-current_item.use_timer;
		if(!current_item.Can_Use())
			return;
		if(player_id==LocalPlayerID){
			Update_Position_Data(true);
			Update_Rotation_Data(true);
		}
		current_item.use_timer=current_tick;
		
		Vector3_t usepos, usedir;
		if((player_id==LocalPlayerID && LocalPlayerScoping())){
			auto scp=Get_Player_Scope(player_id);
			usepos=scp.pos;
			usedir=scp.rot.RotationAsDirection();
		}
		else{
			usepos=CameraPos();
			usedir=dir;
		}
		if(current_item.container_type!=ItemContainerType_t.Player){
			usepos=Objects[current_item.container_obj].pos;
		}
		Vector3_t spreadeddir;
		float spreadfactor=itemtype.spread_c+itemtype.spread_m*uniform01()*(1.0+pow(current_item.heat, 2.0));
		spreadeddir=usedir*(1.0-spreadfactor)+Vector3_t(uniform01(), uniform01(), uniform01()).abs()*spreadfactor;

		float block_hit_dist=10e99;
		Vector3_t block_hit_pos;
		Vector3_t block_build_pos;
		
		if(itemtype.block_damage){
			short range=itemtype.use_range;
			if(range<0)
				range=cast(short)Current_Visibility_Range;
			auto rcp=RayCast(usepos, spreadeddir, range);
			if(rcp.collside && Valid_Coord(rcp)){
				block_hit_dist=rcp.colldist;
				block_hit_pos=Vector3_t(rcp.x, rcp.y, rcp.z);
				block_build_pos=Vector3_t(rcp.x, rcp.y, rcp.z)-spreadeddir.sgn().filter(rcp.collside==1, rcp.collside==2, rcp.collside==3);
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
			if(Config_Read!bool("gun_flashes") && itemtype.Is_Gun())
				Renderer_AddFlash(usepos, 4.0, 1.0);
			foreach(PlayerID_t pid, const plr; Players){
				if(pid==player_id)
					continue;
				if(!plr.Spawned || !plr.InGame)
					continue;
				if((pos-plr.pos).length>(min(Current_Visibility_Range, block_hit_dist)+5))
					continue;
				Sprite_t[] sprites=Get_Player_Sprites(pid);
				foreach(ubyte spindex, ref spr; sprites){
					Vector3_t vxpos; ModelVoxel_t *vx;
					if(SpriteHitScan(spr, usepos, spreadeddir, vxpos, vx)){
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
						Create_Particles(vxpos, Vector3_t(0.0), 0.0, .05, 3, [0x00ff0000], .2);
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
				if(!obj.visible)
					continue;
				ModelVoxel_t *vx;
				Vector3_t hit_pos;
				if(SpriteHitScan(obj.toSprite(), usepos, spreadeddir, hit_pos, vx)){
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
				/*immutable bullet_exit_pos=usepos+spreadeddir*Mod_Models[ItemTypes[equipped_item.type].model_id].size.z
				*Get_Player_Attached_Sprites(player_id)[0].density.z;*/
				immutable bullet_exit_pos=current_item.bullet_exit_pos;
				Create_Smoke(bullet_exit_pos, 2.0*itemtype.power, 0xff808080, 2.0*sqrt(itemtype.power), .1, .1, spreadeddir*.1*sqrt(itemtype.power));
				Bullet_Shoot(bullet_exit_pos+Vector3_t(-.04, .04, 0.0).rotate(spreadeddir.RotationAsDirection), spreadeddir*200.0, LastHitDist, &itemtype.bullet_sprite);
			}
		}
		if(block_hit_dist<player_hit_dist && block_hit_dist<object_hit_dist){
			uint dmgx=touint(block_hit_pos.x), dmgy=touint(block_hit_pos.y), dmgz=touint(block_hit_pos.z);
			if(itemtype.Is_Gun()){
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
		if(player_id==LocalPlayerID && itemtype.Is_Gun()){
			if(LocalPlayerScoping()){
				MouseRot.x+=xrecoil*.5;
				MouseRot.y+=yrecoil*.5;
			}
			else{
				MouseRot.y+=yrecoil;
				MouseRot.x+=xrecoil;
			}
		}
		current_item.last_recoil=(1.0-1.0/(1.0+abs(yrecoil)))*2.0*sgn(yrecoil);
		dir.rotate(Vector3_t(0, yrecoil, xrecoil));
		if(itemtype.is_weapon)
			current_item.amount1--;
		if(itemtype.use_sound_id!=VoidSoundID){
			sndsource.Play_Sound(Mod_Sounds[itemtype.use_sound_id]);
		}
		if(itemtype.Is_Gun)
			current_item.heat+=itemtype.power;
	}
	void Switch_Item(ItemID_t item_id){
		if(equipped_item)
			equipped_item.equipped=VoidPlayerID;
		if(item_id!=VoidItemID)
			equipped_item=&items[item_id];
		else
			equipped_item=null;
		if(equipped_item)
			equipped_item.equipped=player_id;
	}
	void Equip_ObjectItem(Object_t *obj){
		if(equipped_item)
			equipped_item.equipped=VoidPlayerID;
		equipped_item=obj.item;
		if(equipped_item)
			equipped_item.equipped=player_id;
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
	void Set_Crouch(bool cr) {
		if(cr) {
			Crouch = true;
		} else {
			if(Crouch) {
				TryUnCrouch = true;
			}
		}
	}
}

bool Voxel_IsWater(T1, T2, T3)(T1 x, T2 y, T3 z){
	return y>=MapYSize-1;
}

uint[] Solid_Objects;
uint[] Hittable_Objects;

//ASSUMPTION: START COORD IS NON-SOLID
Vector3_t Line_NonCollPos(alias allow_negative_length=false)(Vector3_t start, Vector3_t end){
	return start;
	if(end.y>0){
		if(end.x>0 && end.x<MapXSize && end.z>0 && end.z<MapZSize && end.y<MapYSize){
			if(Voxel_IsSolid(end)){
				Vector3_t diff=start-end;
				auto ray=RCRay_t(start, -diff, diff.length);
				while(!ray.hit)
					ray.Advance();
				float colldist=(diff.length-ray.lastdist)*.9;
				static if(!allow_negative_length){
					if(colldist>0.0)
						return end+diff.abs()*colldist;
					return start;
				}
				else{
					return end+diff.abs()*colldist;
				}
			}
		}
		else{
			Vector3_t diff=end-start;
			float length;
			if(end.x<0)
				length=end.x/diff.x;
			else if(end.x>=MapXSize)
				length=(MapXSize-.001-end.x)/diff.x;
			if(end.z<0)
				length=min(length, end.z/diff.z);
			else if(end.z>=MapZSize)
				length=min(length, (MapZSize-.001-end.z)/diff.z);
			if(end.y>=MapYSize)
				length=min(length, (MapYSize-.001-end.y)/diff.y);
			return start+diff*(length)*.9;
		}
	}
	else{
		return end;
	}
	return end;
}

bool Coord_Collides(Tx, Ty, Tz)(Tx x, Ty y, Tz z, int exclude_obj_index=-1){
	if(y<0)
		return false;
	if(x<0 || x>=MapXSize || z<0 || z>=MapZSize || y>=MapYSize)
		return true;
	if(Voxel_IsWater(x, y, z))
		return false;
	if(Voxel_IsSolid(x, y, z))
		return true;
	foreach(index; Solid_Objects){
		if(index==exclude_obj_index)
			continue;
		if(Objects[index].Solid_At(x, y, z))
			return true;
	}
	return false;
}

bool Coord_Collides(T)(T val) if(__traits(hasMember, T, "x") && __traits(hasMember, T, "y") && __traits(hasMember, T, "z")){
	return Coord_Collides(val.x, val.y, val.z);
}

bool Coord_Collides(T)(T val) if(isArray!T){
	return Coord_Collides(val[0], val[1], val[2]);
}

float CollidingVoxel_GetMinY(TX, TY, TZ)(TX x, TY y, TZ z, int exclude_obj_index=-1){
	if(Coord_Collides(cast(uint)x, cast(uint)y, cast(uint)z))
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
	if(id>=Players.length){
		size_t oldlen=Players.length;
		Players.length=id+1;
		foreach(i; oldlen..Players.length)
			Players[i]=Player_t(to!PlayerID_t(i));
	}
	Player_t *plr=&Players[id];
	plr.Init(name);
}

struct Team_t{
	TeamID_t id;
	string name;
	bool playing;
	union{
		ubyte[4] color;
		uint icolor;
	}
	void Init(string initname, TeamID_t team_id, uint initcolor, bool iplaying){
		id=team_id;
		name=initname;
		icolor=initcolor;
		playing=iplaying;
	}
}

Team_t[] Teams;

void Init_Team(string name, TeamID_t team_id, uint color, bool playing){
	if(team_id>=Teams.length){
		Teams.length=team_id+1;
	}
	Team_t *team=&Teams[team_id];
	team.Init(name, team_id, color, playing);
}

float WorldSpeed=1.0;
uint Last_Tick;

struct ItemType_t{
	ubyte index;
	uint use_delay;
	uint maxamount1, maxamount2;
	bool is_weapon, repeated_use, show_palette, color_mod;
	ubyte block_damage;
	short use_range;
	float spread_c, spread_m;
	float recoil_xc, recoil_xm;
	float recoil_yc, recoil_ym;
	float power;
	float cooling;
	ModelID_t model_id;
	SoundID_t use_sound_id;
	Sprite_t bullet_sprite;
	bool Is_Gun(){
		return is_weapon && maxamount1 && bullet_sprite.model!=null;
	}
}
ItemType_t[] ItemTypes;

enum ItemContainerType_t{
	Player, Object
}

struct Item_t{
	ItemTypeID_t type;
	ItemContainerType_t container_type;
	union{
		PlayerID_t container_plr;
		ObjectID_t container_obj;
	}
	uint amount1, amount2;
	uint use_timer;
	bool Reloading;
	float last_recoil;
	float heat;
	PlayerID_t equipped;
	this(ubyte inittype, ItemContainerType_t icontainer){
		Init(inittype);
		container_type=icontainer;
		equipped=VoidPlayerID;
	}
	void Init(ubyte inittype){
		type=inittype;
		use_timer=0;
		amount1=ItemTypes[type].maxamount1;
		amount2=ItemTypes[type].maxamount2;
		Reloading=false;
		last_recoil=0.0;
		heat=0.0;
		container_type=ItemContainerType_t.Player;
		equipped=VoidPlayerID;
	}
	bool Can_Use(){
		if(Reloading || (!amount1 && ItemTypes[type].maxamount1) || !Use_Ready())
			return false;
		return true;
	}
	void Update(float dt){
		if(heat){
			heat-=dt*ItemTypes[type].cooling;
			if(heat<0.0){
				heat=0.0;
			}
			if(heat && Visible){
				Create_Smoke(bullet_exit_pos, pow(heat*.1, .3), 0x80000000, pow(heat*.03, .3), .1, .1, Vector3_t(0.0, -.01, 0.0));
			}
		}
	}
	bool Use_Ready(){
		int timediff=PreciseClock_ToMSecs(PreciseClock())-use_timer;
		if(timediff<ItemTypes[type].use_delay)
			return false;
		return true;
	}
	Vector3_t bullet_exit_pos(){
		return spr.RelativeCoordinates_To_AbsoluteCoordinates!float(Vector3_t(.5, 0.0, 0.0));
	}
	const Sprite_t spr(){
		if(equipped!=VoidPlayerID){
			auto plr_sprites=Get_Player_Attached_Sprites(equipped);
			if(plr_sprites.length)
				return plr_sprites[0];
			return Sprite_Void();
		}
		final switch(container_type){
			case ItemContainerType_t.Player:{
				auto plr_sprites=Get_Player_Attached_Sprites(container_plr);
				if(plr_sprites.length)
					return plr_sprites[0];
				return Sprite_Void();
			}
			case ItemContainerType_t.Object:{
				return Objects[container_obj].toSprite();
			}
		}
	}
	bool Visible(){
		final switch(container_type){
			case ItemContainerType_t.Player:{
				return equipped!=VoidPlayerID;
			}
			case ItemContainerType_t.Object:{
				return true;
			}
		}
	}
}

float delta_time;
size_t __Block_Damage_Check_Index=0;
immutable uint __Block_Damage_ChecksPerFrame=32;
immutable uint __BlockDamage_HealDelay=1000*5;
immutable ubyte __BlockDamage_HealAmount=16;
void Update_World(){
	uint Current_Tick=PreciseClock_ToMSecs(PreciseClock());
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
	Current_Tick=PreciseClock_ToMSecs(PreciseClock());
	if(FloatingBlockScan_Blocks.length){
		iVector3_t minpos=int.max, maxpos=int.min;
		foreach(block; FloatingBlockScan_Blocks){
			minpos=vmin(minpos, block);
			maxpos=vmax(maxpos, block);
		}
		minpos-=1;
		maxpos+=1;
		minpos=vmax(minpos, typeof(minpos)(0));
		maxpos=vmin(maxpos, typeof(maxpos)(MapXSize, MapYSize, MapZSize));
		FloatingBlocks_Detect(uVector3_t(minpos), uVector3_t(maxpos));
		FloatingBlockScan_Blocks.length=0;
	}
	if(BlockDamage.length){
		bool __dmgblock_removed=false;
		while(!__dmgblock_removed && BlockDamage.length){
			__dmgblock_removed=false;
			auto hashes=BlockDamage.keys();
			size_t ind2=__Block_Damage_Check_Index+__Block_Damage_ChecksPerFrame;
			if(ind2>=hashes.length)
				ind2=hashes.length;
			foreach(ref hash; hashes[__Block_Damage_Check_Index..ind2]){
				auto bdmg=&BlockDamage[hash];
				if(Current_Tick-bdmg.timer>__BlockDamage_HealDelay){
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
	union{
		struct{
			float x, y, z;
		}
		Vector3_t pos;
	}
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
		timer=PreciseClock_ToMSecs(PreciseClock());
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
		timer=PreciseClock_ToMSecs(PreciseClock());
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
		if(!broken){
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
		}
		new_shade=cast(ubyte)(orig_shade-orig_shade*damage/255);
		UpdateVoxel();
	}
	version(DMD){
		pragma(inline)void UpdateVoxel(){
			Voxel_SetShade(x, y, z, new_shade);
		}
	}
	else{
		void UpdateVoxel(){
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
	if(particle_pos){
		Create_Particles(*particle_pos, (*particle_pos-(Vector3_t(xpos, ypos, zpos)+.5)).normal()*.2, 1.0, .1, dmgdiff/3, [col]);
	}
	else{
		/*for(uint side=0; side<8; side++){
			//Create_Particles(Vector3_t(xpos+to!float(cast(bool)(side&1)),
			//ypos+to!float(cast(bool)(side&2)), zpos+to!float(cast(bool)(side&4)))
			//, Vector3_t(0.0), 1.0, .1, dmgdiff/3/6, [col]);
			Create_Particles(Vector3_t(xpos+uniform01(),ypos+uniform01(), zpos+uniform01())
			, Vector3_t(0.0), 1.0, .1, dmgdiff/3/6, [col]);
		}*/
		for(uint side=0; side<12; side++){
			float y;
			if(side<4)y=0.0; else if(side<9)y=.5; else y=1.0;
			float x, z;
			if((side%4)<2){
				x=(side%2) ? 1.0 : 0.0;
				z=.5;
			}
			else{
				x=.5;
				z=(side%2) ? 1.0 : 0.0;
			}
			Create_Particles(Vector3_t(xpos+x, ypos+y, zpos+z)
			, Vector3_t(0.0), 1.0, .1, dmgdiff/2/12, [col]);
		}
	}
	if(dmg.broken){
		if(ProtocolBuiltin_BlockBreakSound!=VoidSoundID){
			auto src=SoundSource_t(Vector3_t(xpos, ypos, zpos));
			src.Play_Sound(Mod_Sounds[ProtocolBuiltin_BlockBreakSound], [SoundPlayOptions.Volume : 1.0]);
			EnvironmentSoundSources~=src;
		}
		if(player_id==LocalPlayerID){
			BlockBreakPacketLayout packet;
			packet.player_id=LocalPlayerID;
			packet.break_type=0;
			packet.x=cast(ushort)xpos; packet.y=cast(ushort)ypos; packet.z=cast(ushort)zpos;
			Send_Packet(BlockBreakPacketID, packet);
		}
	}
}

uVector3_t[] FloatingBlockScan_Blocks;

void Player_BreakBlock(PlayerID_t player_id, ubyte break_type, uint xpos, uint ypos, uint zpos){
	Break_Block(xpos, ypos, zpos);
}

void Break_Block(alias check_floating=true, alias create_particles=true)(uint xpos, uint ypos, uint zpos){
	uint hash=Hash_Coordinates(xpos, ypos, zpos);
	bool block_was_damaged=false;
	if(hash in BlockDamage){
		block_was_damaged=true;
		BlockDamage.remove(hash);
	}
	static if(create_particles){
		uint col=Voxel_GetColor(xpos, ypos, zpos);
		uint x, y, z;
		uint particle_amount=touint(1.0/BlockBreakParticleSize*.5)/(2-block_was_damaged)+1;
		for(x=0; x<particle_amount; x++){
			for(y=0; y<particle_amount; y++){
				for(z=0; z<particle_amount; z++){
					BlockBreakParticles.length++;
					Particle_t *p=&BlockBreakParticles[$-1];
					p.vel=Vector3_t(uniform01()*(uniform(0, 2)?1.0:-1.0)*.075, 0.0, uniform01()*(uniform(0, 2)?1.0:-1.0)*.075);
					p.pos=Vector3_t(to!float(xpos)+to!float(x)*BlockBreakParticleSize,
					to!float(ypos)+to!float(y)*BlockBreakParticleSize,
					to!float(zpos)+to!float(z)*BlockBreakParticleSize)+RandomVector()*.3;
					p.col=col;
					p.timer=uniform(550, 650);
				}
			}
		}
	}
	Voxel_Remove(xpos, ypos, zpos);
	//EVERYONE TO HIS STARTING POSITION, FLOATING BLOCK DETECTION INCOMING
	static if(check_floating){
		if(FloatingBlockDetection_Enabled)
			FloatingBlockScan_Blocks~=uVector3_t(xpos, ypos, zpos);
	}
}

struct RCRay_t{
	int rayx, rayy, rayz;
	int dstx, dsty, dstz;
	int xdsgn, ydsgn, zdsgn;
	uint opxd, opyd, opzd;
	Vector3_t pos, dir, invdir;
	float maxlength;
	bool hit;
	ubyte lastside;
	float lastdist;
	uint loops;
	this(Vector3_t ipos, Vector3_t idir, float imaxlength){
		pos=ipos; dir=idir.normal(); maxlength=imaxlength;
		Vector3_t dst=pos+dir*maxlength;
		rayx=cast(int)pos.x; rayy=cast(int)pos.y; rayz=cast(int)pos.z;
		dstx=cast(int)dst.x; dsty=cast(int)dst.y; dstz=cast(int)dst.z;
		opxd=dir.x>0.0; opyd=dir.y>0.0; opzd=dir.z>0.0;
		invdir.x=dir.x ? 1.0/dir.x : float.infinity; invdir.y=dir.y ? 1.0/dir.y : float.infinity; invdir.z=dir.z ? 1.0/dir.z : float.infinity;
		xdsgn=cast(int)rcsgn(dir.x); ydsgn=cast(int)rcsgn(dir.y); zdsgn=cast(int)rcsgn(dir.z);
		hit=false; lastside=0; loops=cast(int)(maxlength*5.0);
	}
	void Advance(alias until_hit=false)(){
		while(!hit){
			float xdist=(cast(float)(rayx+opxd)-pos.x)*invdir.x;
			float ydist=(cast(float)(rayy+opyd)-pos.y)*invdir.y;
			float zdist=(cast(float)(rayz+opzd)-pos.z)*invdir.z;
			if(xdist<ydist){
				if(xdist<zdist){
					lastside=1;
					lastdist=xdist;
					rayx+=xdsgn;
				}
				else{
					lastside=3;
					lastdist=zdist;
					rayz+=zdsgn;
				}
			}
			else{
				if(ydist<zdist){
					lastside=2;
					lastdist=ydist;
					rayy+=ydsgn;
				}
				else{
					lastside=3;
					lastdist=zdist;
					rayz+=zdsgn;
				}
			}
			//If there's issues with raycasting skipping voxels, the next line might be related to it
			if(lastdist>maxlength)
				break;
			if(!loops){
				writeflnlog("Warning: DDA raycasting results in an infinite loop (%s) (rare?)", this);
				break;
			}
			loops--;
			hit=!Valid_Coord(rayx, rayy, rayz) || Voxel_IsSolid(rayx, rayy, rayz);
			static if(!until_hit)
				break;
		}
	}
}

struct RayCastResult_t{
	int x, y, z;
	float colldist;
	ubyte collside;
}

float rcsgn(float val){
	return sgn(val);
}

RayCastResult_t RayCast(Vector3_t pos, Vector3_t dir, float length){
	auto ray=RCRay_t(pos, dir, length);
	ray.Advance!true();
	ray.lastside*=ray.hit;
	if(ray.lastdist>length)
		ray.lastside=0;
	return RayCastResult_t(ray.rayx, ray.rayy, ray.rayz, ray.lastdist, ray.lastside);
}

string __StructDefToString(T)(){
	string ret="";
	alias st_types=Fields!T;
	alias st_names=FieldNameTuple!T;
	foreach(uint i, name; st_names){
		ret~=TypeName!(st_types[i])()~" "~name~";";
	}
	return ret;
}

struct Object_t{
	uint index;
	ubyte minimap_img;
	bool modify_model, enable_bullet_holes, send_hits, no_map_bound_checks;
	bool visible;
	bool Is_Solid;
	float weightfactor, frictionfactor;
	Vector3_t acl;
	ObjectPhysicsMode physics_mode;
	ScriptIndex_t physics_script;
	Vector3_t attached_offset;
	ObjectID_t attached_to_obj;
	bool attached_freerotation;
	union{
		PhysicalObject_t obj;
		struct{mixin(__StructDefToString!PhysicalObject_t());}
	}
	float smoke_amount;
	uint smoke_color;
	DamageParticle_t[] particles;
	
	Item_t *item;
	
	SoundSource_t sndsource;
	SoundID_t[] loop_sounds;

	@property Model_t *model(){return obj.spr.model;} @property void model(Model_t *m){obj.spr.model=m;}
	@property uint color(){return obj.spr.color_mod;} @property void color(uint c){obj.spr.color_mod=c;}
	
	//ctor: when newly created; Init(): when object exists and gets reinitialized via packet
	
	this(uint initindex){
		this.index=initindex;
		physics_mode=ObjectPhysicsMode.Standard;
		acl=Vector3_t(0.0);
		obj=PhysicalObject_t([Vector3_t(0.0, 0.0, 0.0)]);
		smoke_amount=0.0;
		attached_to_obj=VoidObjectID;
		item=null;
		sndsource=SoundSource_t(0);
	}

	void Init(){
		smoke_amount=0.0;
		if(visible)
			UnInit();
		particles=[];
		attached_to_obj=VoidObjectID;
		visible=true;
		item=null;
	}
	
	void Play(SoundID_t snd, bool repeat){
		if(repeat){
			if(!loop_sounds.canFind(snd)){
				loop_sounds~=snd;
			}
		}
		sndsource.Play_Sound(Mod_Sounds[snd]);
	}
	
	void UnInit(){
		if(DamagedObjects.canFind(index))
			DamagedObjects.remove(DamagedObjects.countUntil(index));
		if(Solid_Objects.canFind(index))
			Solid_Objects.remove(Solid_Objects.countUntil(index));
		if(Hittable_Objects.canFind(index))
			Hittable_Objects.remove(Hittable_Objects.countUntil(index));
		particles=[];
		visible=false;
		item=null;
		
	}
	
	void Delete(){
		sndsource.UnInit();
	}
	
	void Update(float dt=WorldSpeed){
		if(!visible)
			return;
		if(item)
			item.Update(dt);
		if(attached_to_obj!=VoidObjectID && attached_to_obj<Objects.length){
			Object_t *obj=&Objects[attached_to_obj];
			vel=obj.vel;
			if(!attached_freerotation)
				rot=obj.rot;
			pos=(attached_offset.normal().DirectionAsRotation()+obj.rot).RotationAsDirection()*attached_offset.length+obj.pos;
			return;
		}
		immutable oldpos=pos, oldrot=rot;
		if(physics_mode==ObjectPhysicsMode.Standard || physics_mode==ObjectPhysicsMode.Scripted){
			if(physics_mode==ObjectPhysicsMode.Scripted){
				Vector3_t deltapos=obj.Vertices_CheckCollisions(vel*dt);
				bool[3] inv_coll=[!Collision[0], !Collision[1], !Collision[2]];
				Vector3_t fdeltapos=deltapos.filter(inv_coll);
				uint[3] _coll=[Collision[0], Collision[1], Collision[2]];
				Loaded_Scripts[physics_script].Call_Func("Update_Position", &_coll, &fdeltapos, &pos, &vel, &acl, &rot, WorldSpeed);
			}
			vel.y+=weightfactor ? (1.0-.05/weightfactor)*dt*Gravity : 0.0;
			obj.Update(dt);
			if(!Collision[0] && !Collision[1] && !Collision[2]){
				vel/=1.0+frictionfactor*dt;
			}
		}
		else{
			Vector3_t deltapos=obj.Vertices_CheckCollisions(vel*dt);
			bool[3] inv_coll=[!Collision[0], !Collision[1], !Collision[2]];
			Vector3_t fdeltapos=deltapos.filter(inv_coll);
			uint[3] _coll=[Collision[0], Collision[1], Collision[2]];
			Loaded_Scripts[physics_script].Call_Func("Update_Position", &_coll, &fdeltapos, &pos, &vel, &acl, &rot, WorldSpeed);
			if(physics_mode==ObjectPhysicsMode.Script_Override)
				return;
			if(physics_mode==ObjectPhysicsMode.Full_Scripted){
				pos+=fdeltapos;
			}
		}
		immutable deltarot=rot-oldrot;
		immutable deltapos=pos-oldpos;
		if(deltarot){
			foreach(ref particle; particles){
				immutable vdist=particle.pos-pos;
				immutable rot=vdist.DirectionAsRotation();
				particle.pos=pos+vdist.length+(rot+deltarot).RotationAsDirection();
			}
		}
		if(deltapos){
			foreach(ref particle; particles){
				particle.pos+=deltapos;
			}
		}
		if(smoke_amount){
			Create_Smoke(pos, smoke_amount*dt, smoke_color, pow(smoke_amount, .75), .2, .75, vel*.01);
		}
		sndsource.SetPos(pos);
		sndsource.SetVel(vel);
		foreach(lsound; loop_sounds){
			if(!sndsource.Sound_Playing(Mod_Sounds[lsound]))
				sndsource.Play_Sound(Mod_Sounds[lsound]);
		}
	}

	bool Collides_At(T1, T2, T3)(T1 x, T2 y, T3 z){
		return Coord_Collides(toint(x), toint(y), toint(z), index);
	}
	bool Solid_At(XT, YT, ZT)(XT x, YT y, ZT z){
		return Contains(x, y, z);
	}
	bool Contains(XT, YT, ZT)(XT x, YT y, ZT z){
		if(!visible)
			return false;
		Vector3_t startpos=pos-spr.size/2.0, endpos=pos+spr.size/2.0;
		return x>=startpos.x && x<endpos.x && y>=startpos.y && y<endpos.y && z>=startpos.z && z<endpos.z;
	}
	void Damage(Vector3_t particle_pos){
		particles.length++;
		DamageParticle_t *prtcl=&particles[$-1];
		prtcl.x=particle_pos.x; prtcl.y=particle_pos.y; prtcl.z=particle_pos.z; prtcl.col=0;
		if(!DamagedObjects.canFind(index))
			DamagedObjects~=index;
	}
	Sprite_t toSprite(){
		Sprite_t ret;
		ret.rti=rot.y; ret.rhe=rot.x; ret.rst=rot.z;
		ret.density=spr.size/Vector3_t(spr.model.size);
		ret.pos=pos;
		ret.model=model;
		ret.color_mod=0; ret.replace_black=0;
		if(color){
			if(color&0xff000000){
				ret.color_mod=color;
			}
			ret.replace_black=color;
		}
		return ret;
	}
	void Render(){
		if(item){
			if(item.equipped!=VoidPlayerID)
				return;
		}
		return obj.Render();
	}
}

Object_t[] Objects;
uint[] DamagedObjects;

struct PhysicalObject_t{
	Vector3_t pos, vel, rot, rotvel;
	Vector3_t bouncefactor;
	Vector3_t[] Vertices;
	bool[3] Collision;
	bool is_stuck;
	SpriteRenderData_t spr;
	
	this(Vector3_t[] ivertices){
		Init(ivertices);
	}
	
	void Init(Vector3_t[] ivertices=[Vector3_t(0.0)]){
		Vertices=ivertices;
		Collision[]=false;
		pos=vel=rot=rotvel=bouncefactor=Vector3_t(0.0);
	}

	void Update(T)(T delta_ticks){
		is_stuck=false;
		Vector3_t deltapos=Vertices_CheckCollisions(vel*delta_ticks);
		if(rotvel){
			if(Try_Rotate(rot+rotvel*WorldSpeed))
				rot+=rotvel*WorldSpeed;
			else
				rotvel*=.1;
			rotvel/=1.0+WorldSpeed;
		}
		if(!is_stuck){
			if(Collision[0] || Collision[1] || Collision[2]){
				if(Collision[0])
					vel.x*=-1.0;
				if(Collision[1])
					vel.y*=-1.0;
				if(Collision[2])
					vel.z*=-1.0;
				vel*=bouncefactor;
			}
			pos+=deltapos;
		}
		else{
			vel=Vector3_t(0.0);
			pos.y-=delta_ticks;
		}
	}

	Vector3_t Vertices_CheckCollisions(Vector3_t delta_pos){
		Collision[]=false;
		foreach(uint i, ref vertex; Vertices){
			Vector3_t vdelta_pos;
			bool[3] coll=Vertex_CheckCollision(vertex, delta_pos, vdelta_pos);
			if(coll[0] || coll[1] || coll[2]){
				delta_pos=delta_pos.vecabs().min(vdelta_pos.vecabs())*delta_pos.sgn();
				Collision[]|=coll[];
				if(is_stuck)
					return Vector3_t(0.0);
			}
		}
		if(fabs(delta_pos.x)<.00001)
			delta_pos.x=0.0;
		if(fabs(delta_pos.y)<.00001)
			delta_pos.y=0.0;
		if(fabs(delta_pos.z)<.00001)
			delta_pos.z=0.0;
		return delta_pos;
	}
	
	bool[3] Vertex_CheckCollision(Vector3_t vertex, Vector3_t delta_pos, out Vector3_t min_collision_delta){
		Vector3_t rvert=vertex.rotate(rot);
		Vector3_t vpos=rvert+pos;
		Vector3_t newpos=vpos+delta_pos;
		if(!Coord_Collides(newpos)){
			min_collision_delta=delta_pos;
			return [false, false, false];
		}
		if(Coord_Collides(vpos)){
			min_collision_delta=Vector3_t(0.0);
			is_stuck=true;
			return [true, true, true];
		}
		bool[3] coll=[Coord_Collides(newpos.x, vpos.y, vpos.z),
		Coord_Collides(vpos.x, newpos.y, vpos.z), Coord_Collides(vpos.x, vpos.y, newpos.z)];
		min_collision_delta=Line_NonCollPos!(true)(vpos, vpos+delta_pos.filter(coll))-vpos;
		if(Coord_Collides(vpos+min_collision_delta))
			min_collision_delta=Vector3_t(0.0);
		/*Vector3_t advance_pos=pos+delta_pos;
		rotvel-=(vpos-pos).normal().RotationAsDirection()-(vpos-advance_pos).normal().DirectionAsRotation();*/
		return coll;
	}
	
	bool Try_Rotate(Vector3_t newrot){
		foreach(uint i, ref vertex; Vertices){
			if(Coord_Collides(vertex.rotate(newrot)+pos))
				return false;
		}
		return true;
	}
	
	void Render(){
		spr.motion_blur=min(vel.length/299_792_458.0, 1.0);
		Renderer_DrawSprite(&spr, pos, rot);
		static if(0){
			foreach(vertex; Vertices){
				Vector3_t vpos=vertex.rotate(rot)+pos;
				int scrx, scry;
				float dist;
				if(Project2D(vpos.x, vpos.y, vpos.z, scrx, scry, dist)){
					immutable float inv_renddist=1.0/dist;
					immutable int w=cast(int)(10*inv_renddist)+1, h=cast(int)(10*inv_renddist)+1;
					scrx-=w>>1; scry-=h>>1;
					if(scrx+w<0 || scry+h<0 || scrx>=vxrend_framebuf_w || scry>=vxrend_framebuf_h)
						continue;
					Renderer_DrawRect2D(scrx, scry, w, h, 0xff00ff00, 0);
				}
			}
		}
	}
}

bool Valid_Coord(Tx, Ty, Tz)(Tx x, Ty y, Tz z){
	return x>=0 && x<MapXSize && y>=0 && y<MapYSize && z>=0 && z<MapZSize;
}

bool Valid_Coord(T)(T coord) if(__traits(hasMember, coord, "x") && __traits(hasMember, coord, "y") && __traits(hasMember, coord, "z")){
	return Valid_Coord(coord.x, coord.y, coord.z);
}

Vector3_t Validate_Coord(immutable in Vector3_t coord){
	return Vector3_t(max(min(coord.x, MapXSize-1), 0), max(min(coord.y, MapYSize-1), 0), max(min(coord.z, MapZSize-1), 0));
}

void On_Map_Loaded(){
	Set_Sun(Vector3_t(MapXSize, MapYSize, MapZSize)/2.0+Vector3_t(60.0, 15.0, 0.0).RotationAsDirection(), 1.0);
}

bool FloatingBlockDetection_Enabled=true;

//PySnip approach - a kind of 3D flood fill, and then see if it hits the ground or not (not used, and not recommended either)
//(works well for single voxels but a killer for large holes)
uVector3_t[] FloatingBlockDetectionSingle(T=uint)(Vector_t!(3, T) starting_coords) if(isIntegral!T){
	uVector3_t[] blocks_checked;
	uVector3_t[] blocks_to_check=[uVector3_t(starting_coords)];
	while(blocks_to_check.length){
		bool block_added=false;
		immutable nearby_vox=[
			iVector3_t(-1, 0, 0), iVector3_t(1, 0, 0), iVector3_t(0, -1, 0), iVector3_t(0, 0, -1), iVector3_t(0, 0, 1), iVector3_t(0, 1, 0)
		];
		immutable nearby_vox_cancel=[
			"block.x==1", "block.x==MapXSize-2", "", "block.z==1", "block.z==MapZSize-2", "block.y==MapYSize-1"
		];
		immutable string __voxel_check_mixin(immutable uint ind){
			immutable string vox_varname="vox_"~to!string(ind);
			return "immutable "~vox_varname~"=block+nearby_vox["~to!string(ind)~"]; if(!blocks_checked.canFind("~vox_varname~")"~
			"&&!_new_blocks.canFind("~vox_varname~")){if(Voxel_IsSolid("~vox_varname~")){"~(nearby_vox_cancel[ind].length ?
			"if("~nearby_vox_cancel[ind]~")return[];" : "")~"_new_blocks~="~vox_varname~";}}";
		}
		uVector3_t[] _new_blocks;
		foreach_reverse(immutable block; blocks_to_check){
			mixin(__voxel_check_mixin(2));
			mixin(__voxel_check_mixin(0));
			mixin(__voxel_check_mixin(1));
			mixin(__voxel_check_mixin(3));
			mixin(__voxel_check_mixin(4));
			{
				auto _block=block+iVector3_t(0, 1, 0);
				while(Voxel_IsSolid(_block)){
					if(_block.y==MapYSize-1){
						return [];
					}
					_block.y++;
				}
				_block.y--;
				if(Voxel_IsSolid(_block)){
					if(!_new_blocks.canFind(_block) && !blocks_checked.canFind(_block))
						_new_blocks~=_block;
				}
			}
			blocks_checked~=block;
		}
		blocks_to_check=_new_blocks;
	}
	return blocks_checked;
}

struct VoxelPillar_t{
	uint y1, y2;
	size_t group_index;
}

struct VoxelPillarArr_t{
	bool extracted;
	VoxelPillar_t[] pillars;
}

struct VoxelPillarGroup_t{
	size_t index;
	size_t[3][] pillars;
	bool grounded;
}

struct VoxelPillarSlice_t{
	VoxelPillarArr_t[][] pillars; //THE PILLARS ARE YOUR BEST FRIENDS
	bool[][] pillars_extracted;
	uVector3_t startpos, endpos;
	this(uVector3_t coord1, uVector3_t coord2){
		coord1.y=0; coord2.y=MapYSize;
		startpos=vmin(coord1, coord2);
		endpos=vmax(coord1, coord2);
		pillars=new VoxelPillarArr_t[][](MapXSize, MapZSize);
		pillars_extracted=new bool[][](MapXSize, MapZSize);
		foreach(x; startpos.x..endpos.x){
			foreach(z; startpos.z..endpos.z){
				Pillars_Extract(x, z);
			}
		}
	}
	void Pillars_Extract(size_t xpos, size_t zpos){
		bool current_vox=false;
		VoxelPillar_t current_pillar;
		foreach(y; 0..MapYSize){
			if(Voxel_IsSolid(xpos, y, zpos)){
				if(current_vox){
					continue;
				}
				else{
					current_vox=true;
					current_pillar.y1=y;
					continue;
//TRUST THE PILLARS YOUR INFORMATION
				}
			}
			else{
				if(current_vox){
					current_pillar.y2=y-1;
					pillars[xpos][zpos].pillars~=current_pillar;//THE PILLARS ARE TRUSTWORTHY
					current_vox=false;
					continue;
				}
				else{
					continue;
				}
			}
		}
		if(current_vox){
			current_pillar.y2=MapYSize-1;
			pillars[xpos][zpos].pillars~=current_pillar;
		}
		pillars_extracted[xpos][zpos]=true;
	}
	VoxelPillarGroup_t[] GroupPillars(){
		VoxelPillarGroup_t[] ret;
		while(1){//TELL SAMUEL EVERYTHING ABOUT YOUR PLANE OF EXISTENCE
			VoxelPillarGroup_t group;
			group.index=ret.length+1;
			foreach(x; startpos.x..endpos.x){
				foreach(z; startpos.z..endpos.z){
					foreach(ind, ref pillar; pillars[x][z].pillars){
						if(!pillar.group_index){
							group.pillars~=[x, z, ind];
							group.grounded|=pillar.y2==MapYSize-1;
							pillar.group_index=group.index;
							break;
						}
					}
					if(group.pillars.length)
						break;
				}
				if(group.pillars.length)
					break;
			}
			if(!group.pillars.length)
				break;//THE PILLARS ARE COMING FOR YOUR SECRETS
			for(size_t ind1=0; ind1<group.pillars.length; ind1++){
				auto pillar1=pillars[group.pillars[ind1][0]][group.pillars[ind1][1]].pillars[group.pillars[ind1][2]];
				foreach(nearby_pos_ind, nearby_pos; [[-1, 0], [1, 0], [0, -1], [0, 1]]){
					if((!nearby_pos_ind && !group.pillars[ind1][0]) || (nearby_pos_ind==1 && group.pillars[ind1][0]==MapXSize-1)){
						group.grounded=true;
						continue;
					}
					if((nearby_pos_ind==2 && !group.pillars[ind1][1]) || (nearby_pos_ind==3 && group.pillars[ind1][1]==MapZSize-1)){
						group.grounded=true;
						continue;
					}
					size_t pillar_xpos=group.pillars[ind1][0]+nearby_pos[0], pillar_zpos=group.pillars[ind1][1]+nearby_pos[1];
					if(group.grounded && (pillar_xpos<startpos.x || pillar_xpos>endpos.x || pillar_zpos<startpos.z || pillar_zpos>startpos.z))
						continue;
					if(!pillars_extracted[pillar_xpos][pillar_zpos]){
						Pillars_Extract(pillar_xpos, pillar_zpos);
					}
					foreach(ind2, ref pillar2; pillars[pillar_xpos][pillar_zpos].pillars){
						if(pillar2.group_index!=group.index && !(pillar2.y2<pillar1.y1) && !(pillar2.y1>pillar1.y2)){
							if(pillar2.group_index){
								if(ret[pillar2.group_index-1].grounded)
									group.grounded=true;
							}
							else{
								group.pillars~=[pillar_xpos, pillar_zpos, ind2];
								pillar2.group_index=group.index;
							}
							group.grounded|=pillar2.y2==MapYSize-1;
							if(group.grounded)
								break;
						}
					}
					if(group.grounded)
						break;
				}
				if(group.grounded)
					break;
			}//THE PILLARS TRANSCEND INFORMATION
			ret~=group;
		}
		return ret;
	}
	void CheckFloatingGroups(VoxelPillarGroup_t[] groups){
		foreach(group; groups){
			if(group.grounded)
				continue;
			foreach(pillar; group.pillars){
				foreach(y; pillars[pillar[0]][pillar[1]].pillars[pillar[2]].y1..pillars[pillar[0]][pillar[1]].pillars[pillar[2]].y2+1){
					Break_Block!(false, true)(cast(uint)pillar[0], y, cast(uint)pillar[1]);
				}
			}
		}
	}
}

void FloatingBlocks_Detect(uVector3_t coord1, uVector3_t coord2){
	auto slice=VoxelPillarSlice_t(coord1, coord2+1);
	slice.CheckFloatingGroups(slice.GroupPillars());
}

//Works perfectly, but lags cause wrong targetting
/*
void _FloatingBlocks_Detect(iVector3_t coord1, iVector3_t coord2){
	uVector3_t chunk_size=coord2-coord1;
	FloatingBlockPillarArr_t[][] pillars=new FloatingBlockPillarArr_t[][](chunk_size.x, chunk_size.z);
	FloatingBlockPillar_t current_pillar;
	size_t pillar_count=0;
	size_t grounded_pillars_count=0;
	foreach(x; coord1.x..coord2.x){
		foreach(z; coord1.z..coord2.z){
			bool current_vox=false;
			foreach(y; 0..MapYSize){
				if(Voxel_IsSolid(x, y, z)){
					if(current_vox){
						continue;
					}
					else{
						current_vox=true;
						current_pillar.y1=y;
						continue;
					}
				}
				else{
					if(current_vox){
						current_pillar.y2=y-1;
						pillars[x-coord1.x][z-coord1.z]~=current_pillar;
						current_vox=false;
						continue;
					}
					else{
						continue;
					}
				}
			}
			if(current_vox){
				current_pillar.y2=coord2.y-1;
			}
			current_pillar.grounded=true;
			pillars[x-coord1.x][z-coord1.z]~=current_pillar;
			current_pillar.grounded=false;
			pillar_count+=pillars[x-coord1.x][z-coord1.z].length;
		}
	}
	size_t[3][] grounded_pillars;
	foreach(size_t x; coord1.x..coord2.x){
		foreach(size_t z; coord1.z..coord2.z){
			foreach(size_t ind, pillar; pillars[x-coord1.x][z-coord1.z]){
				if(!pillar.grounded)
					continue;
				grounded_pillars~=[x-coord1.x, z-coord1.z, ind];
			}
		}
	}
	for(size_t i=0; i<grounded_pillars.length; i++){
		auto pillar=pillars[grounded_pillars[i][0]][grounded_pillars[i][1]][grounded_pillars[i][2]];
		immutable pos_add=[[-1, 0], [1, 0], [0, -1], [0, 1]];
		foreach(ind, nearby_coord; pos_add){
			if((!grounded_pillars[i][0] && !ind) || (grounded_pillars[i][0]>=chunk_size.x-1 && ind==1))
				continue;
			if((!grounded_pillars[i][1] && ind==2) || (grounded_pillars[i][1]>=chunk_size.z-1 && ind==3))
				continue;
			size_t x=grounded_pillars[i][0]+nearby_coord[0], z=grounded_pillars[i][1]+nearby_coord[1];
			foreach(size_t ind2, ref pillar2; pillars[x][z]){
				if(!pillar2.grounded && !(pillar2.y2<pillar.y1) && !(pillar2.y1>pillar.y2)){
					pillar2.grounded=true;
					grounded_pillars~=[x, z, ind2];
				}
			}
		}
	}
	if(grounded_pillars.length==pillar_count)
		return;
	size_t[3][] ungrounded_pillars;
	foreach(size_t x; coord1.x..coord2.x){
		foreach(size_t z; coord1.z..coord2.z){
			foreach(size_t ind, pillar; pillars[x-coord1.x][z-coord1.z]){
				if(!pillar.grounded){
					ungrounded_pillars~=[x-coord1.x, z-coord1.z, ind];
					if(x==coord1.x || x==coord2.x || z==coord1.z || z==coord2.z){
						if(pow(coord2.x-coord1.x, 2)+pow(coord2.z-coord1.z, 2)<128*128+128*128)
							return FloatingBlocks_Detect(coord1-16, coord2+16);
						return;
					}
				}
			}
		}
	}
	//uint[3][] debris_blocks;
	foreach(pillar_pos; ungrounded_pillars){
		auto pillar=pillars[pillar_pos[0]][pillar_pos[1]][pillar_pos[2]];
		foreach(y; pillar.y1..pillar.y2+1){
			//debris_blocks~=[pillar_pos[0]+coord1.x, y, pillar_pos[1]+coord1.z];
			//Voxel_Remove(pillar_pos[0]+coord1.x, y, pillar_pos[1]+coord1.z);
			Break_Block!(false, true)(pillar_pos[0]+coord1.x, y, pillar_pos[1]+coord1.z);
		}
	}
	//Blocks_ToDebris(debris_blocks);
}
*/
