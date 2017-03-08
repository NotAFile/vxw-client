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
import ui;
import script;
import protocol;

float Gravity=9.81/0.64;
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

immutable float Player_Stand_Size=2.8;
immutable float Player_Stand_Size_Eye=2.3;
immutable float Player_Crouch_Size=1.8;
immutable float Player_Crouch_Size_Eye=1.3;
immutable float Crouch_Height_Change_Speed = 0.375; //in secounds

Vector3_t Wind_Direction;

immutable uint ticks_ps = 60;

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
		static if(isVector3Like!T1() && isVector3Like!T2()){
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
		TR tnear=-TR.max, tfar=TR.max;
		if(!dir.x){
			if((pos.x<minvec.x) || (pos.x>maxvec.x))
				return TR.nan;
		}
		else{
			TR t1=(minvec.x-pos.x)/dir.x;
			TR t2=(maxvec.x-pos.x)/dir.x;
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
			TR t1=(minvec.y-pos.y)/dir.y;
			TR t2=(maxvec.y-pos.y)/dir.y;
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
			TR t1=(minvec.z-pos.z)/dir.z;
			TR t2=(maxvec.z-pos.z)/dir.z;
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
	
	bool intersection_terrain() {
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
	ubyte[] selected_item_types;
	uint item;
	uint item_animation_counter;
	Vector3_t current_item_offset;
	bool left_click, right_click;
	uint color;
	Object_t *standing_on_obj, stood_on_obj;
	
	float Walk_Forwards_Timer, Walk_Sidewards_Timer;
	
	bool airborne, airborne_old;
	float airborne_start = 0.0F;
	uint physics_start;
	uint ticks = 0;
	uint last_climb = 0;
	float crouch_offset = 0.0;
	
	void Init(string initname, PlayerID_t initplayer_id){
		name=initname;
		player_id=initplayer_id;
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
	}
	Team_t *Get_Team(){
		if(team==255)
			return null;
		return &Teams[team];
	}
	Item_t *Equipped_Item(){
		return &items[item];
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
	
	void Update(){
		if(Spawned) {
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
			if(Equipped_Item()){
				if(PreciseClock_ToMSecs(PreciseClock())-Equipped_Item().use_timer>ItemTypes[Equipped_Item().type].use_delay){
					Equipped_Item.last_recoil=0.0;
				}
			}
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
	
	void Update_Physics() {
		Vector3_t prev_pos=CameraPos();
		float dt = 1.0F/(cast(float)ticks_ps);
		AABB_t player_aabb;
		
		if(Crouch && TryUnCrouch) {
			player_aabb.set_size(0.75F,Player_Stand_Size,0.75F);
			player_aabb.set_bottom_center(pos.x,pos.y,pos.z);
			if(!player_aabb.intersection_terrain()) {
				Crouch = TryUnCrouch = false;
			} else {
				player_aabb.set_bottom_center(pos.x,pos.y+0.9F,pos.z);
				if(!player_aabb.intersection_terrain()) {
					pos.y += 0.9F;
					Crouch = TryUnCrouch = false;
				}
			}
		}
		
		crouch_offset += ((Crouch && crouch_offset<0.0)?dt/Crouch_Height_Change_Speed:0.0) + ((!Crouch && crouch_offset>-1.0)?-dt/Crouch_Height_Change_Speed:0.0);
		
		player_aabb.set_size(0.75F,Crouch?Player_Crouch_Size:Player_Stand_Size,0.75F);
		
		player_aabb.set_bottom_center(pos.x,pos.y+vel.y*dt,pos.z);
		if(!player_aabb.intersection_terrain()) {
			pos.y += vel.y*dt;
			vel.y += dt*Gravity*2.0F;
		} else {
			vel.y = 0.0F;
		}
		
		player_aabb.set_bottom_center(pos.x,pos.y+0.1F,pos.z);
		airborne_old = airborne;
		airborne = !player_aabb.intersection_terrain();
		
		if(airborne && !airborne_old) { //fall or jump start
			airborne_start = pos.y;
		} else {
			if(!airborne && airborne_old) { //fall or jump end
				float d = pos.y-airborne_start;
				debug{
					if(d>0.0F) {
						printf("Fall distance: %f\n",d);
					}
				}
			}
		}
		
		if(!airborne && Jump && !LastJump) {
			vel.y = Crouch?-8.0F:-10.0F;
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
		if(player_aabb.intersection_terrain()) {
			blocked_in_x = true;
		}
		player_aabb.set_bottom_center(pos.x,pos.y,pos.z+vel.z*dt);
		if(player_aabb.intersection_terrain()) {
			blocked_in_z = true;
		}
		  
		if(!airborne && !Jump && !Crouch && !TryUnCrouch && !Sprint) {
			bool climb = false;
			
			player_aabb.set_bottom_center(pos.x+vel.x*dt,pos.y-1.0F,pos.z);
			if(!player_aabb.intersection_terrain() && blocked_in_x) {
				climb = true;
				blocked_in_x = false;
			}
			
			player_aabb.set_bottom_center(pos.x,pos.y-1.0F,pos.z+vel.z*dt);
			if(!player_aabb.intersection_terrain() && blocked_in_z) {
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
		auto current_tick=PreciseClock_ToMSecs(PreciseClock());
		Item_t *current_item=&items[item];
		ItemType_t *itemtype=&ItemTypes[current_item.type];
		auto timediff=current_tick-current_item.use_timer;
		if(timediff<ItemTypes[current_item.type].use_delay || current_item.Reloading || (!current_item.amount1 && itemtype.maxamount1 && player_id==LocalPlayerID))
			return;
		Update_Position_Data(true);
		Update_Rotation_Data(true);
		current_item.use_timer=current_tick;
		
		Vector3_t usepos, usedir;
		if(player_id==LocalPlayerID && LocalPlayerScoping()){
			auto scp=Get_Player_Scope(player_id);
			usepos=scp.pos; usedir=scp.rot.RotationAsDirection();
		}
		else{
			usepos=CameraPos();
			usedir=dir;
		}
		Vector3_t spreadeddir;
		float spreadfactor=itemtype.spread_c+itemtype.spread_m*uniform01();
		spreadeddir=usedir*(1.0-spreadfactor)+Vector3_t(uniform01(), uniform01(), uniform01()).abs()*spreadfactor;

		float block_hit_dist=10e99;
		Vector3_t block_hit_pos;
		Vector3_t block_build_pos;
		
		if(itemtype.block_damage){
			short range=itemtype.block_damage_range;
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
			if(Config_Read!bool("gun_flashes"))
				Renderer_AddFlash(usepos, 4.0, 1.0);
			foreach(PlayerID_t pid, const plr; Players){
				if(pid==player_id)
					continue;
				if(!plr.Spawned || !plr.InGame)
					continue;
				if((pos-plr.pos).length>min(Current_Visibility_Range+5, block_hit_dist+5))
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
				Create_Smoke(usepos+spreadeddir*1.0, to!uint(2*itemtype.power), 0xff808080, 1.0*sqrt(itemtype.power), .1, .1, spreadeddir*.1*sqrt(itemtype.power));
				if(itemtype.bullet_sprite.model!=null)
					Bullet_Shoot(usepos+spreadeddir*.5, spreadeddir*200.0, LastHitDist, &itemtype.bullet_sprite);
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
		if(player_id==LocalPlayerID && itemtype.is_weapon){
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
	if(id>=Players.length)
		Players.length=id+1;
	Player_t *plr=&Players[id];
	plr.Init(name, id);
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
		int timediff=PreciseClock_ToMSecs(PreciseClock())-use_timer;
		if(timediff<ItemTypes[type].use_delay)
			return false;
		return true;
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
		for(uint side=0; side<6; side++){
			Create_Particles(Vector3_t(xpos+to!float(cast(bool)(side&1))*uniform01(),
			ypos+to!float(cast(bool)(side&2))*uniform01(), zpos+to!float(cast(bool)(side&4))*uniform01())
			, Vector3_t(0.0), 1.0, .1, dmgdiff/3/6, [col]);
		}
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
		uint particle_amount=touint(1.0/BlockBreakParticleSize*.5)+1;
		for(x=0; x<particle_amount; x++){
			for(y=0; y<particle_amount; y++){
				for(z=0; z<particle_amount; z++){
					BlockBreakParticles.length++;
					Particle_t *p=&BlockBreakParticles[$-1];
					p.vel=Vector3_t(uniform01()*(uniform(0, 2)?1.0:-1.0)*.075, 0.0, uniform01()*(uniform(0, 2)?1.0:-1.0)*.075);
					p.pos=Vector3_t(to!float(xpos)+to!float(x)*BlockBreakParticleSize,
					to!float(ypos)+to!float(y)*BlockBreakParticleSize,
					to!float(zpos)+to!float(z)*BlockBreakParticleSize);
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
	bool modify_model, enable_bullet_holes, send_hits;
	bool visible;
	bool Is_Solid;
	float weightfactor, frictionfactor;
	Vector3_t acl;
	ObjectPhysicsMode physics_mode;
	ScriptIndex_t physics_script;
	union{
		PhysicalObject_t obj;
		struct{mixin(__StructDefToString!PhysicalObject_t());}
	}

	DamageParticle_t[] particles;

	@property Model_t *model(){return obj.spr.model;} @property void model(Model_t *m){obj.spr.model=m;}
	@property uint color(){return obj.spr.color_mod;} @property void color(uint c){obj.spr.color_mod=c;}

	void Init(uint initindex){
		index=initindex;
		physics_mode=ObjectPhysicsMode.Standard;
		if(DamagedObjects.canFind(index))
			DamagedObjects.remove(index);
		if(Solid_Objects.canFind(index))
			Solid_Objects.remove(index);
		if(Hittable_Objects.canFind(index))
			Hittable_Objects.remove(index);
		acl=Vector3_t(0.0);
		obj=PhysicalObject_t([Vector3_t(0.0, 0.0, 0.0)]);
	}
	
	void Update(float dt=WorldSpeed){
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
				return;
			}
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
