import std.math;
import std.random;
import std.algorithm;
import std.traits;
import std.format;
import misc;
version(LDC){
	import ldc_stdlib;
}
version(GNU){
	import gdc_stdlib;
}

T degsin(T)(T val){
	return cast(T)sin(val*PI/180.0);
}

T degcos(T)(T val){
	return cast(T)cos(val*PI/180.0);
}

alias Vector3_t=Vector_t!(3);
alias Vector4_t=Vector_t!(4);

string __mixin_NearestFloatType(T)(){
	static if(is(T==float) || is(T==double))
		return T.stringof;
	return "float";
}

bool isFloat(T)(){
	return is(T==float) || is(T==double);
}

template VectorTypeOf(VectorType){
	static if(!isVector3Like!VectorType()){
		alias VectorTypeOf=void;
	}
	else{
		alias VectorTypeOf=VectorType.__element_t;
	}
}

template isVector_t(T){
	immutable bool is_vec=__traits(hasMember, T, "x") && __traits(hasMember, T, "y") && __traits(hasMember, T, "z");
	alias isVector_t=is_vec;
}

template isVectorLike(T){
	immutable bool is_vec=__traits(hasMember, T, "x") && __traits(hasMember, T, "y") && __traits(hasMember, T, "z");
	alias isVectorLike=is_vec;
}

private string __mixin_VectorCTFilter(alias dim)(){
	string func_code="const __this_type filter(";
	foreach(i; 0..dim){
		func_code~="alias filterarg_"~to!string(i);
		if(i!=dim-1)
			func_code~=",";
	}
	func_code~=")(){return __this_type(";
	foreach(i; 0..dim){
		func_code~="filterarg_"~to!string(i)~" ? elements["~to!string(i)~"] : cast(element_t)0";
		if(i!=dim-1)
			func_code~=",";
	}
	func_code~=");}";
	return func_code;
}

private string __mixin_VectorRTFilter(alias dim)(){
	string func_code="const __this_type filter(";
	foreach(i; 0..dim){
		func_code~="filterarg_"~to!string(i)~"_type";
		if(i!=dim-1)
			func_code~=",";
	}
	func_code~=")(";
	foreach(i; 0..dim){
		func_code~="filterarg_"~to!string(i)~"_type filterarg_"~to!string(i);
		if(i!=dim-1)
			func_code~=",";
	}
	func_code~="){return __this_type(";
	foreach(i; 0..dim){
		func_code~="filterarg_"~to!string(i)~" ? elements["~to!string(i)~"] : cast(element_t)0";
		if(i!=dim-1)
			func_code~=",";
	}
	func_code~=");}";
	return func_code;
}

version(DigitalMars){pragma(inline, true):}
nothrow pure struct Vector_t(alias dim=3, element_t=float){
	union{
		element_t[dim] elements;
		static if(dim==3){
			struct{
				element_t x, y, z, w;
			}
		}
		static if(dim==4){
			struct{
				element_t x, y, z, w;
			}
		}
	}
	alias __dim=dim;
	alias __element_t=element_t;
	alias __this_type=Vector_t!(dim, element_t);
	mixin("alias __float_type="~__mixin_NearestFloatType!element_t()~";");
	const @property typeof(x) length(){
		return vector_length();
	}
	@property void length(element_t newlength){
		this=this*newlength/vector_length();
	}
	const @property typeof(x) sqlength(){
		return vector_sqlength();
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
	static if(dim!=3){
		this(element_t[dim] initelements...){
			elements[]=initelements[];
		}
	}
	//Optimized version for fast Vector3_t
	this(T1, T2, T3)(T1 ix, T2 iy, T3 iz){
		x=cast(typeof(x))ix; y=cast(typeof(y))iy; z=cast(typeof(z))iz;
	}
	version(DigitalMars){ pragma(inline, true):}
	this(T)(T val) if(isVectorLike!T){
		x=cast(typeof(x))val.x; y=cast(typeof(y))val.y; z=cast(typeof(z))val.z;
	}
	void opIndexAssign(T)(element_t val, T ind){
		elements[ind]=val;
	}
	__this_type opAssign(T)(T val) if(isVectorLike!T){
		x=cast(typeof(x))val.x; y=cast(typeof(y))val.y; z=cast(typeof(z))val.z;
		return this;
	}
	const __this_type opUnary(string op)(){
		return __this_type(mixin(op~"x"), mixin(op~"y"), mixin(op~"z"));
	}
	const __this_type opBinary(string op, T)(T[] arg){
		__this_type ret;
		ret.elements=elements;
		mixin("ret.elements[]"~op~"=arg[];");
		return ret;
	}
	const __this_type opBinary(string op, T)(T arg) if(isVector_t!T){
		static assert(arg.__dim==dim);
		//Apparently I have to pass some CT arguments, or else this function will get evaluated in runtime or sth
		//(in any case not passing any CT arguments, will make this lag)
		string __mixin_code(alias _dim, alias _op)(){
			string ret;
			foreach(i; 0.._dim){
				ret~="elements["~to!string(i)~"]"~_op~"arg.elements["~to!string(i)~"]";
				if(i!=dim-1)
				ret~=",";
			}
			return ret;
		}
		return mixin("__this_type("~__mixin_code!(dim, op)()~")");
	}
	const __this_type opBinary(string op, T)(T arg) if(!isArray!T && !isVector_t!T){
		static if(dim==3){
			return __this_type(mixin("x"~op~"arg"), mixin("y"~op~"arg"), mixin("z"~op~"arg"));
		}
		else{
			__this_type ret;
			mixin("ret.elements=elements[]"~op~"arg;");
			return ret;
		}
	}
	static if(dim==3){
		bool opEquals(T)(T arg) if(isVectorLike!T){
			return x==arg.x && y==arg.y && z==arg.z;
		}
	}
	int opCmp(T)(T arg){
		auto vec=this-arg;
		element_t[] el=vec.elements;
		auto avg=sum(el, 0.0)/vec.elements.length;
		if(std.math.abs(avg)<1.0)
			avg/=avg*std.math.sgn(avg);
		return cast(int)avg;
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
	
	const element_t vector_length(){
		static if(dim==3){
			return cast(element_t)std.math.sqrt(cast(__float_type)(x*x+y*y+z*z));
		}
		else
		static if(dim==4){
			return cast(element_t)std.math.sqrt(cast(__float_type)(x*x+y*y+z*z+w*w));
		}
		else{
			element_t ret=0.0;
			foreach(el; elements)
				ret+=el*el;
			return sqrt(ret);
		}
	}
	
	const element_t vector_sqlength(){
		static if(dim==3){
			return x*x+y*y+z*z;
		}
		else
		static if(dim==4){
			return x*x+y*y+z*z+w*w;
		}
		else{
			element_t ret=0.0;
			foreach(el; elements)
				ret+=el*el;
			return ret;
		}
	}
	
	const __this_type cossin(){return __this_type(degcos(x), degsin(y), degsin(z));}
	const __this_type sincos(){return __this_type(degsin(x), degcos(y), degcos(z));}
	
	const __this_type sincossin(){return __this_type(degsin(x), degcos(y), degsin(z));}
	
	const __this_type sin(){return __this_type(degsin(x), degsin(y), degsin(z));}
	const __this_type cos(){return __this_type(degcos(x), degcos(y), degcos(z));}
	
	__this_type rotdir(){return __this_type(degcos(x), degsin(x), degcos(y));}
	
	__this_type normal(){if(this.length)return (this/this.length); return __this_type(0.0, 0.0, 0.0);}
	//DEPRECATED
	__this_type abs(){return this.normal();}
	const __this_type vecabs(){
		static if(isFloat!element_t())
			return __this_type(fabs(x), fabs(y), fabs(z));
		else
			return __this_type(std.math.abs(x), std.math.abs(y), std.math.abs(z));
	}
	__this_type inv(){
		__this_type ret;
		ret.elements[]=(cast(element_t)1.0)/this.elements[];
		return ret;
	}
	
	__this_type rotate(__this_type rot){
		__this_type rrot=rot;
		rrot.x=rot.z; rrot.z=rot.x;
		return rotate_raw(rrot);
	}

	__this_type rotate_raw(T)(T rot) if(isVector_t!T){
		__this_type ret=this, tmp=this;
		__this_type vsin=rot.sin(), vcos=rot.cos();
		ret.y=tmp.y*vcos.x-tmp.z*vsin.x; ret.z=tmp.y*vsin.x+tmp.z*vcos.x;
		tmp.x=ret.x; tmp.z=ret.z;
		ret.z=tmp.z*vcos.y-tmp.x*vsin.y; ret.x=tmp.z*vsin.y+tmp.x*vcos.y;
		tmp.x=ret.x; tmp.y=ret.y;
		ret.x=tmp.x*vcos.z-tmp.y*vsin.z; ret.y=tmp.x*vsin.z+tmp.y*vcos.z;
		return ret;
	}
	
	__this_type rotate_raw(__this_type vsin, __this_type vcos){
		__this_type ret=this, tmp=this;
		ret.y=tmp.y*vcos.x-tmp.z*vsin.x; ret.z=tmp.y*vsin.x+tmp.z*vcos.x;
		tmp.x=ret.x; tmp.z=ret.z;
		ret.z=tmp.z*vcos.y-tmp.x*vsin.y; ret.x=tmp.z*vsin.y+tmp.x*vcos.y;
		tmp.x=ret.x; tmp.y=ret.y;
		ret.x=tmp.x*vcos.z-tmp.y*vsin.z; ret.y=tmp.x*vsin.z+tmp.y*vcos.z;
		return ret;
	}
	
	//This function is correct (lecom approved) (except for maybe negligible precision loss)
	//(Not suitable for OpenGL, needs corrections for that)
	__this_type RotationAsDirection(){
		__this_type dir=__this_type(1.0, 0.0, 0.0);
		dir=dir.rotate(__this_type(this.y, this.x, this.z));
		auto result=__this_type(dir.x, -dir.z, dir.y);
		return result;
	}
	
	__this_type DirectionAsRotation(){
		float ry=atan2(cast(__float_type)this.z, cast(__float_type)this.x)*180.0/PI;
		float rx=asin(cast(__float_type)this.y)*180.0/PI;
		float rz=0.0;
		return __this_type(rx, ry, rz);
	}
	
	__this_type rotate_asd(__this_type rot){
		return RotateAroundX(rot.x).RotateAroundY(rot.y).RotateAroundZ(rot.z);
	}
	
	__this_type RotateAroundX(element_t rot){
		__this_type ret;
		immutable element_t old_y=y;
		ret.x=x;
		ret.y=cast(typeof(ret.y))(y*degcos(rot)-z*degsin(rot));
		ret.z=cast(typeof(ret.z))(z*degcos(rot)+old_y*degsin(rot));
		return ret;
	}
	
	__this_type RotateAroundY(element_t rot){
		__this_type ret;
		immutable element_t old_x=x;
		ret.x=cast(typeof(ret.x))(x*degcos(rot)-z*degsin(rot));
		ret.y=y;
		ret.z=cast(typeof(ret.z))(z*degcos(rot)+old_x*degsin(rot));
		return ret;
	}
	
	__this_type RotateAroundZ(element_t rot){
		__this_type ret;
		immutable element_t old_x=x;
		ret.x=cast(typeof(ret.x))(x*degcos(rot)-y*degsin(rot));
		ret.y=cast(typeof(ret.y))(y*degcos(rot)+old_x*degsin(rot));
		ret.z=z;
		return ret;
	}
	const typeof(x) dot(T)(T arg){
		__this_type vec=__this_type(arg);
		return x*vec.x+y*vec.y+z*vec.z;
	}
	const typeof(x) dot(__this_type vec){
		return x*vec.x+y*vec.y+z*vec.z;
	}
	
	const T opCast(T)() if(is(T==__this_type)){return this;}
	const T opCast(T)() if(isArray!T){return elements;}
	const T opCast(T)() if(is(T==bool)){return x && y && z;}
	
	const __this_type filter(T)(T filterarr) if(isArray!T){
		__this_type ret;
		foreach(i; 0..dim){
			ret.elements[i]=filterarr[i] ? elements[i] : cast(element_t)0;
		}
		return ret;
	}
	mixin(__mixin_VectorCTFilter!(dim)());
	mixin(__mixin_VectorRTFilter!(dim)());
	__this_type sgn(){
		return __this_type(std.math.sgn(x), std.math.sgn(y), std.math.sgn(z));
	}
	__this_type min(__this_type vec){
		__this_type ret;
		foreach(i, ref val; this.elements){
			ret.elements[i]=std.algorithm.min(val, vec.elements[i]);
		}
		return ret;
	}
	Vector_t!(3, T) cross(T)(Vector_t!(3, T) vec){
		return Vector_t!(3, T)(y*vec.z-z*vec.y, z*vec.x-x*vec.z, x*vec.y-y*vec.x);
	}

	const string toString(){
		string ret="{";
		for(uint i=0; i<dim; i++){
			ret~=format("%10.10f", elements[i]);
			if(i!=dim-1)
				ret~=";";
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
