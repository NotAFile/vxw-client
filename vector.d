import std.math;
import std.random;
import std.algorithm;
import misc;
version(LDC){
	import ldc_stdlib;
}
version(GNU){
	import gdc_stdlib;
}

T degsin(T)(T val){
	return sin(val*PI/180.0);
}

T degcos(T)(T val){
	return cos(val*PI/180.0);
}

alias Vector3_t=Vector_t!(3);
alias Vector4_t=Vector_t!(4);

struct Vector_t(alias dim=3, element_t=float){
	union{
		element_t[dim] elements;
		static if(dim==3){
			struct{
				element_t x, y, z;
			}
		}
		else{
			struct{
				element_t x, y, z, w;
			}
		}
	}
	alias __this_type=Vector_t!(dim, element_t);
	@property typeof(x) length(){
		return vector_length();
	}
	@property void length(element_t newlength){
		this=this*newlength/vector_length();
	}
    alias opDollar=length;
	this(Vector_t vec){
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
	this(element_t[dim] initelements...){
		elements[]=initelements[];
	}
	this(T1, T2, T3)(T1 ix, T2 iy, T3 iz){
		x=cast(typeof(x))ix; y=cast(typeof(y))iy; z=cast(typeof(z))iz;
	}
	this(T)(T val) if(__traits(hasMember, T, "x") && __traits(hasMember, T, "y") && __traits(hasMember, T, "z")){
		x=cast(typeof(x))val.x; y=cast(typeof(y))val.y; z=cast(typeof(z))val.z;
	}
	void opIndexAssign(T)(element_t val, T ind){
		elements[ind]=val;
	}
	__this_type opUnary(string op)(){
		return __this_type(mixin(op~"x"), mixin(op~"y"), mixin(op~"z"));
	}
	__this_type opBinary(string op)(__this_type arg){
		return opBinary!(op)(arg.elements);
	}
	__this_type opBinary(string op, T)(T[] arg){
		__this_type ret;
		ret.elements=elements;
		mixin("ret.elements[]"~op~"=args[]");
		return ret;
	}
	__this_type opBinary(string op, T)(T arg){
		static if(__traits(compiles, arg[0]) && __traits(compiles, arg[1]) && __traits(compiles, arg[2]) && !is(T==__this_type)){
			return __this_type(mixin("x"~op~"arg[0]"), mixin("y"~op~"arg[1]"), mixin("z"~op~"arg[2]"));
		}
		else{
			return __this_type(mixin("x"~op~"arg"), mixin("y"~op~"arg"), mixin("z"~op~"arg"));
		}
	}
	__this_type opOpAssign(string op)(__this_type arg){
		this=this.opBinary!(op)(arg);
		return this;
	}
	__this_type opOpAssign(string op, T)(T arg){
		this=this.opBinary!(op)(arg);
		return this;
	}
	float opIndex(T)(T index){
		return elements[index];
		assert(1);
	}
	
	element_t vector_length(){
		static if(dim==3){
			return std.math.sqrt(x*x+y*y+z*z);
		}
		else
		static if(dim==4){
			return std.math.sqrt(x*x+y*y+z*z+w*w);
		}
		else{
			element_t ret=0.0;
			foreach(el; elements)
				ret+=el*el;
			return sqrt(ret);
		}
	}
	
	__this_type cossin(){return __this_type(degcos(x), degsin(y), degsin(z));}
	__this_type sincos(){return __this_type(degsin(x), degcos(y), degcos(z));}
	
	__this_type sincossin(){return __this_type(degsin(x), degcos(y), degsin(z));}
	
	__this_type sin(){return __this_type(degsin(x), degsin(y), degsin(z));}
	__this_type cos(){return __this_type(degcos(x), degcos(y), degcos(z));}
	
	__this_type rotdir(){return __this_type(degcos(x), degsin(x), degcos(y));}
	
	__this_type abs(){if(this.length)return (this/this.length); return __this_type(0.0, 0.0, 0.0);}
	__this_type vecabs(){return __this_type(fabs(x), fabs(y), fabs(z));}
	
	__this_type rotate(__this_type rot){
		__this_type rrot=rot;
		rrot.x=rot.z; rrot.z=rot.x;
		return rotate_raw(rrot);
	}

	__this_type rotate_raw(__this_type rot){
		__this_type ret=this, tmp=this;
		__this_type vsin=rot.sin(), vcos=rot.cos();
		ret.y=tmp.y*vcos.x-tmp.z*vsin.x; ret.z=tmp.y*vsin.x+tmp.z*vcos.x;
		tmp.x=ret.x; tmp.z=ret.z;
		ret.z=tmp.z*vcos.y-tmp.x*vsin.y; ret.x=tmp.z*vsin.y+tmp.x*vcos.y;
		tmp.x=ret.x; tmp.y=ret.y;
		ret.x=tmp.x*vcos.z-tmp.y*vsin.z; ret.y=tmp.x*vsin.z+tmp.y*vcos.z;
		return ret;
	}
	
	//This function is correct (lecom approved) (except for maybe negligible precision loss)
	__this_type RotationAsDirection(){
		/*float cx=degcos(this.x);
		float sy=degsin(this.y);
		float cz=degsin(this.x);
		float xzr=1.0-fabs(this.y)/90.0;
		cx*=xzr; cz*=xzr;
		return __this_type(cx, sy, cz);*/
		__this_type dir=__this_type(1.0, 0.0, 0.0);
		dir=dir.rotate(__this_type(this.y, this.x, this.z));
		auto result=__this_type(dir.x, -dir.z, dir.y);
		return result;
	}
	
	__this_type DirectionAsRotation(){
		float ry=atan2(this.z, this.x)*180.0/PI;
		float rx=asin(this.y)*180.0/PI;
		float rz=0.0;
		return __this_type(rx, ry, rz);
	}
	
	__this_type rotate_asd(__this_type rot){
		return RotateAroundX(rot.x).RotateAroundY(rot.y).RotateAroundZ(rot.z);
	}
	
	__this_type RotateAroundX(float rot){
		__this_type ret;
		ret.y=y*degcos(rot)-z*degsin(rot);
		ret.z=y*degsin(rot)+z*degcos(rot);
		ret.x=x;
		return ret;
	}
	
	__this_type RotateAroundY(float rot){
		__this_type ret;
		ret.z=z*degcos(rot)-z*degsin(rot);
		ret.y=y;
		ret.x=x*degcos(rot)-x*degcos(rot);
		return ret;
	}
	
	__this_type RotateAroundZ(float rot){
		__this_type ret;
		ret.x=x*degcos(rot)-y*degsin(rot);
		ret.y=x*degsin(rot)+y*degcos(rot);
		ret.z=z;
		return ret;
	}
	
	typeof(x) dot(T)(T arg){
		__this_type vec=__this_type(arg);
		return x*vec.x+y*vec.y+z*vec.z;
	}
	typeof(x) dot(__this_type vec){
		return x*vec.x+y*vec.y+z*vec.z;
	}
	
	typeof(x)[3] opCast(){
		return [x, y, z];
	}
	
	__this_type filter(T)(T[] filterarr){
		return filter(filterarr[0], filterarr[1], filterarr[2]);
	}
	__this_type filter(TFX, TFY, TFZ)(TFX filterx, TFY filtery, TFZ filterz){
		return __this_type(filterx ? x : 0.0, filtery ? y : 0.0, filterz ? z : 0.0);
	}
	__this_type filter(alias filterx, alias filtery, alias filterz)(){
		mixin("return __this_type("~(filterx ? "x," : "0,")~(filtery ? "y," : "0,")~(filterz ? "z," : "0,")~");");
	}
	__this_type sgn(){
		return __this_type(SGN(x), SGN(y), SGN(z));
	}
	Vector_t!(3) cross(Vector_t!(3) vec){
		return Vector_t!(3)(y*vec.z-z*vec.y, z*vec.x-x*vec.z, x*vec.y-y*vec.x);
	}
	string toString(){
		string ret="{";
		for(uint i=0; i<dim; i++){
			ret~=to!string(elements[i]);
			if(i!=dim-1)
				ret~=" | ";
		}
		ret~="}";
		return ret;
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

import std.conv;

struct Matrix_t(alias xdim=4, alias ydim=4, element_t=float){
	union{
		Vector_t!(xdim, element_t)[ydim] v_elements;
		element_t[xdim][ydim] a2_elements;
		element_t[xdim*ydim] a_elements;
	}
	alias __this_type=Matrix_t!(xdim, ydim, element_t);
	this(this){
		
	}
	this(T)(T val){
		this=val;
	}
	element_t opIndex(Tx, Ty)(Tx x, Ty y){
		return a_elements[x+y*xdim];
	}
	element_t opIndex(T)(T i){
		return a_elements[i];
	}
	void opIndexAssign(Tx, Ty)(element_t val, Tx x, Ty y){
		a_elements[x+y*xdim]=val;
	}
	void opIndexAssign(T)(element_t val, T ind){
		a_elements[ind]=val;
	}
	void opAssign(__this_type val){
		this.a_elements=val.a_elements;
	}
	void opAssign(T)(T[][] val){
		for(uint x=0; x<val.length; x++){
			for(uint y=0; y<val.length; y++){
				this[x, y]=val[x][y];
			}
		}
	}
	void opAssign(T)(T[] val) if(!__traits(compiles, val[0][0])){
		this.a_elements=val;
	}
	Vector_t!(4, element_t) opBinary(string op)(Vector_t!(4) vec) if(op=="*"){
		Vector_t!(4, element_t) ret;
		/*for(uint y=0; y<4; y++){
			ret[y]=this[0, y]*vec[0]+this[1, y]*vec[1]+this[2, y]*vec[2]+this[3, y]*vec[3];
		}*/
		ret[0]=this[0]*vec[0]+this[1]*vec[1]+this[2]*vec[2]+this[3]*vec[3];
		ret[1]=this[4]*vec[0]+this[5]*vec[1]+this[6]*vec[2]+this[7]*vec[3];
		ret[2]=this[8]*vec[0]+this[9]*vec[1]+this[10]*vec[2]+this[11]*vec[3];
		ret[3]=this[12]*vec[0]+this[13]*vec[1]+this[14]*vec[2]+this[15]*vec[3];
		return ret;
		//return Vector_t!(xdim, element_t)(v_elements[0].dot(vec), v_elements[1].dot(vec), v_elements[2].dot(vec), v_elements[3].dot(vec));
	}
	/*__this_type opBinary(string op)(__this_type vec) if(op=="*"){
		__this_type ret;
		for(uint x=0; x<xdim; x++){
			for(uint y=0; y<ydim; y++){
				ret[x, y]=0.0;
				for(uint i=0; i<xdim; i++){
					ret[x, y]=ret[x, y]+this[i, y]*vec[x, i];
				}
			}
		}
		return ret;
	}*/
	__this_type opBinary(string op)(__this_type vec) if(op=="*"){
		__this_type ret;
		ret.a_elements[0] = this.a_elements[0]*vec.a_elements[0]+this.a_elements[4]*vec.a_elements[1]+this.a_elements[8]*vec.a_elements[2]+this.a_elements[12]*vec.a_elements[3];
		ret.a_elements[1] = this.a_elements[1]*vec.a_elements[0]+this.a_elements[5]*vec.a_elements[1]+this.a_elements[9]*vec.a_elements[2]+this.a_elements[13]*vec.a_elements[3];
		ret.a_elements[2] = this.a_elements[2]*vec.a_elements[0]+this.a_elements[6]*vec.a_elements[1]+this.a_elements[10]*vec.a_elements[2]+this.a_elements[14]*vec.a_elements[3];
		ret.a_elements[3] = this.a_elements[3]*vec.a_elements[0]+this.a_elements[7]*vec.a_elements[1]+this.a_elements[11]*vec.a_elements[2]+this.a_elements[15]*vec.a_elements[3];
	
		ret.a_elements[4] = this.a_elements[0]*vec.a_elements[4]+this.a_elements[4]*vec.a_elements[5]+this.a_elements[8]*vec.a_elements[6]+this.a_elements[12]*vec.a_elements[7];
		ret.a_elements[5] = this.a_elements[1]*vec.a_elements[4]+this.a_elements[5]*vec.a_elements[5]+this.a_elements[9]*vec.a_elements[6]+this.a_elements[13]*vec.a_elements[7];
		ret.a_elements[6] = this.a_elements[2]*vec.a_elements[4]+this.a_elements[6]*vec.a_elements[5]+this.a_elements[10]*vec.a_elements[6]+this.a_elements[14]*vec.a_elements[7];
		ret.a_elements[7] = this.a_elements[3]*vec.a_elements[4]+this.a_elements[7]*vec.a_elements[5]+this.a_elements[11]*vec.a_elements[6]+this.a_elements[15]*vec.a_elements[7];
	
		ret.a_elements[8] = this.a_elements[0]*vec.a_elements[8]+this.a_elements[4]*vec.a_elements[9]+this.a_elements[8]*vec.a_elements[10]+this.a_elements[12]*vec.a_elements[11];
		ret.a_elements[9] = this.a_elements[1]*vec.a_elements[8]+this.a_elements[5]*vec.a_elements[9]+this.a_elements[9]*vec.a_elements[10]+this.a_elements[13]*vec.a_elements[11];
		ret.a_elements[10] = this.a_elements[2]*vec.a_elements[8]+this.a_elements[6]*vec.a_elements[9]+this.a_elements[10]*vec.a_elements[10]+this.a_elements[14]*vec.a_elements[11];
		ret.a_elements[11] = this.a_elements[3]*vec.a_elements[8]+this.a_elements[7]*vec.a_elements[9]+this.a_elements[11]*vec.a_elements[10]+this.a_elements[15]*vec.a_elements[11];
	
		ret.a_elements[12] = this.a_elements[0]*vec.a_elements[12]+this.a_elements[4]*vec.a_elements[13]+this.a_elements[8]*vec.a_elements[14]+this.a_elements[12]*vec.a_elements[15];
		ret.a_elements[13] = this.a_elements[1]*vec.a_elements[12]+this.a_elements[5]*vec.a_elements[13]+this.a_elements[9]*vec.a_elements[14]+this.a_elements[13]*vec.a_elements[15];
		ret.a_elements[14] = this.a_elements[2]*vec.a_elements[12]+this.a_elements[6]*vec.a_elements[13]+this.a_elements[10]*vec.a_elements[14]+this.a_elements[14]*vec.a_elements[15];
		ret.a_elements[15] = this.a_elements[3]*vec.a_elements[12]+this.a_elements[7]*vec.a_elements[13]+this.a_elements[11]*vec.a_elements[14]+this.a_elements[15]*vec.a_elements[15];
		return ret;
	}
	__this_type opBinary(string op)(__this_type vec) if(op!="*"){
		ret.a_elements=a_elements;
		mixin("ret.a_elements[]"~op~"=vec.a_elements[]");
		return ret;
	}
}

alias QMatrix_t=Matrix_t!();
alias Matrix4x4_t=Matrix_t!();
