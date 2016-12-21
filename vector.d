import std.math;
import std.random;
import std.algorithm;
import misc;


version(LDC){
	import ldc_stdlib;
}

T degsin(T)(T val){
	return sin(val*PI/180.0);
}

T degcos(T)(T val){
	return cos(val*PI/180.0);
}

struct Vector3_t{
	float x, y, z;
	@property typeof(x) length(){
		return vector_length();
	}
	@property void length(typeof(x) newlength){
		this=this*newlength/vector_length();
	}
    alias opDollar=length;
	this(Vector3_t vec){
		this=vec;
	}
	this(T)(T[] val){
		x=cast(typeof(x))val[0]; y=cast(typeof(y))val[1]; z=cast(typeof(z))val[2];
	}
	this(T)(T val) if(__traits(isScalar, val)){
		x=cast(typeof(x))val; y=cast(typeof(y))val; z=cast(typeof(z))val;
	}
	this(typeof(x) ix, typeof(y) iy, typeof(z) iz){
		x=ix; y=iy; z=iz;
	}
	this(T1, T2, T3)(T1 ix, T2 iy, T3 iz){
		x=cast(typeof(x))ix; y=cast(typeof(y))iy; z=cast(typeof(z))iz;
	}
	Vector3_t opBinary(string op)(Vector3_t arg){
		return Vector3_t(mixin("x"~op~"arg.x"), mixin("y"~op~"arg.y"), mixin("z"~op~"arg.z"));
	}
	Vector3_t opBinary(string op, T)(T[] arg){
	}
	Vector3_t opBinary(string op, T)(T arg){
		static if(__traits(compiles, arg[0]) && __traits(compiles, arg[1]) && __traits(compiles, arg[2]) && !is(T==Vector3_t)){
			return Vector3_t(mixin("x"~op~"arg[0]"), mixin("y"~op~"arg[1]"), mixin("z"~op~"arg[2]"));
		}
		else{
			return Vector3_t(mixin("x"~op~"arg"), mixin("y"~op~"arg"), mixin("z"~op~"arg"));
		}
	}
	Vector3_t opOpAssign(string op)(Vector3_t arg){
		this=this.opBinary!(op)(arg);
		return this;
	}
	Vector3_t opOpAssign(string op, T)(T arg){
		this=this.opBinary!(op)(arg);
		return this;
	}
	float opIndex(T)(T index){
		static if((cast(int)T)==0)
			return x;
		else if((cast(int)T)==1)
			return y;
		else if((cast(int)T)==2)
			return z;
		assert(1);
	}
	
	typeof(x) vector_length(){return std.math.sqrt(x*x+y*y+z*z);}
	
	Vector3_t cossin(){return Vector3_t(degcos(x), degsin(y), degsin(z));}
	Vector3_t sincos(){return Vector3_t(degsin(x), degcos(y), degcos(z));}
	
	Vector3_t sincossin(){return Vector3_t(degsin(x), degcos(y), degsin(z));}
	
	Vector3_t sin(){return Vector3_t(degsin(x), degsin(y), degsin(z));}
	Vector3_t cos(){return Vector3_t(degcos(x), degcos(y), degcos(z));}
	
	Vector3_t rotdir(){return Vector3_t(degcos(x), degsin(x), degcos(y));}
	
	Vector3_t abs(){if(this.length)return (this/this.length); return Vector3_t(0.0, 0.0, 0.0);}
	Vector3_t vecabs(){return Vector3_t(fabs(x), fabs(y), fabs(z));}
	
	Vector3_t rotate(Vector3_t rot){
		Vector3_t rrot=rot;
		rrot.x=rot.z; rrot.z=rot.x;
		return rotate_raw(rrot);
	}

	Vector3_t rotate_raw(Vector3_t rot){
		Vector3_t ret=this, tmp=this;
		Vector3_t vsin=rot.sin(), vcos=rot.cos();
		ret.y=tmp.y*vcos.x-tmp.z*vsin.x; ret.z=tmp.y*vsin.x+tmp.z*vcos.x;
		tmp.x=ret.x; tmp.z=ret.z;
		ret.z=tmp.z*vcos.y-tmp.x*vsin.y; ret.x=tmp.z*vsin.y+tmp.x*vcos.y;
		tmp.x=ret.x; tmp.y=ret.y;
		ret.x=tmp.x*vcos.z-tmp.y*vsin.z; ret.y=tmp.x*vsin.z+tmp.y*vcos.z;
		return ret;
	}
	
	//This function is correct (lecom approved) (except for maybe negligible precision loss)
	Vector3_t RotationAsDirection(){
		/*float cx=degcos(this.x);
		float sy=degsin(this.y);
		float cz=degsin(this.x);
		float xzr=1.0-fabs(this.y)/90.0;
		cx*=xzr; cz*=xzr;
		return Vector3_t(cx, sy, cz);*/
		Vector3_t dir=Vector3_t(1.0, 0.0, 0.0);
		dir=dir.rotate(Vector3_t(this.y, this.x, this.z));
		auto result=Vector3_t(dir.x, -dir.z, dir.y);
		return result;
	}
	
	Vector3_t DirectionAsRotation(){
		float ry=atan2(this.z, this.x)*180.0/PI;
		float rx=asin(this.y)*180.0/PI;
		float rz=0.0;
		return Vector3_t(rx, ry, rz);
	}
	
	Vector3_t rotate_asd(Vector3_t rot){
		return RotateAroundX(rot.x).RotateAroundY(rot.y).RotateAroundZ(rot.z);
	}
	
	Vector3_t RotateAroundX(float rot){
		Vector3_t ret;
		ret.y=y*degcos(rot)-z*degsin(rot);
		ret.z=y*degsin(rot)+z*degcos(rot);
		ret.x=x;
		return ret;
	}
	
	Vector3_t RotateAroundY(float rot){
		Vector3_t ret;
		ret.z=z*degcos(rot)-z*degsin(rot);
		ret.y=y;
		ret.x=x*degcos(rot)-x*degcos(rot);
		return ret;
	}
	
	Vector3_t RotateAroundZ(float rot){
		Vector3_t ret;
		ret.x=x*degcos(rot)-y*degsin(rot);
		ret.y=x*degsin(rot)+y*degcos(rot);
		ret.z=z;
		return ret;
	}
	
	typeof(x) dot(T)(T arg){
		Vector3_t vec=Vector3_t(arg);
		return x*vec.x+y*vec.y+z*vec.z;
	}
	typeof(x) dot(Vector3_t vec){
		return x*vec.x+y*vec.y+z*vec.z;
	}
	
	typeof(x)[3] opCast(){
		return [x, y, z];
	}
	
	Vector3_t filter(T)(T[] filterarr){
		return filter(filterarr[0], filterarr[1], filterarr[2]);
	}
	Vector3_t filter(TFX, TFY, TFZ)(TFX filterx, TFY filtery, TFZ filterz){
		return Vector3_t(filterx ? x : 0.0, filtery ? y : 0.0, filterz ? z : 0.0);
	}
	Vector3_t filter(alias filterx, alias filtery, alias filterz)(){
		mixin("return Vector3_t("~(filterx ? "x," : "0,")~(filtery ? "y," : "0,")~(filterz ? "z," : "0,")~");");
	}
	Vector3_t sgn(){
		return Vector3_t(SGN(x), SGN(y), SGN(z));
	}
}

Vector3_t vmin(Vector3_t vec1, Vector3_t vec2){
	return Vector3_t(min(vec1.x, vec2.x), min(vec1.y, vec2.y), min(vec1.z, vec2.z));
}

Vector3_t vmax(Vector3_t vec1, Vector3_t vec2){
	return Vector3_t(max(vec1.x, vec2.x), max(vec1.y, vec2.y), max(vec1.z, vec2.z));
}

Vector3_t RandomVector(){
	return Vector3_t(uniform01()*2.0-1.0, uniform01()*2.0-1.0, uniform01()*2.0-1.0);
}
