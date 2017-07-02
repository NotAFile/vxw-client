import std.algorithm;
import std.random;

import std.math;
import std.random;
import std.algorithm;
import std.traits;
import std.format;
import std.conv;
static if(0){
	import core.simd;
}

template VectorTypeOf(VectorType){
	static if(!isVector3Like!VectorType()){
		alias VectorTypeOf=void;
	}
	else{
		alias VectorTypeOf=VectorType.__element_t;
	}
}

private void is_simd_vec_impl(T)(__vector(T) vec){}

template isSIMDVector(T){
	enum isSIMDVector=is(typeof(is_simd_vec_impl(T.init)));
}

template isVector_t(T){
	static if(!is(T==void)){
		static if(__traits(compiles, TemplateOf!T)){
			immutable bool is_vec=__traits(isSame, TemplateOf!T, Vector_t);
		}
		else{
			immutable bool is_vec=false;
		}
	}
	else{
		immutable bool is_vec=false;
	}
	alias isVector_t=is_vec;
}

template isVector3Like(T){
	immutable bool is_vec=__traits(hasMember, T, "x") && __traits(hasMember, T, "y") && __traits(hasMember, T, "z");
	alias isVector3Like=is_vec;
}


bool isFloat(T)(){
	return is(T==float) || is(T==double) || is(T==real);
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
		func_code~="filterarg_"~to!string(i)~" ? array["~to!string(i)~"] : cast(element_t)0";
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
		func_code~="filterarg_"~to!string(i)~" ? array["~to!string(i)~"] : cast(element_t)0";
		if(i!=dim-1)
			func_code~=",";
	}
	func_code~=");}";
	return func_code;
}

string __mixin_NearestFloatType(T)(){
	static if(is(T==float) || is(T==double) || is(T==real))
		return T.stringof;
	return "float";
}

template isScalar(T){
	static if(__traits(isScalar, T)){
		static if(isSIMDVector!T){
			immutable isScalar=false;
		}
		else{
			static if(__traits(compiles, std.traits.TemplateOf!(T))){
				static if(__traits(isSame, std.traits.TemplateOf!(T), core.simd.Vector))
					immutable isScalar=false;
				else
					immutable isScalar=true;
			}
			else
				immutable isScalar=true;
		}
	}
	else{
		immutable isScalar=false;
	}
}

template toNearestFloatType(T){
	static if(is(T==float) || is(T==double) || is(T==real))
		alias toNearestFloatType=T;
	else
		alias toNearestFloatType=float;
}

template toNearestSIMDType(alias dim, element_t){
	static if(is(element_t==float)){
		static if(dim<=4 && is(float4))
			alias toNearestSIMDType=float4;
		else
		static if(dim<=8 && is(float8))
			alias toNearestSIMDType=float8;
		else
			alias toNearestSIMDType=void;
	}
	else
	static if(is(element_t==double)){
		static if(dim<=2 && is(double2))
			alias toNearestSIMDType=double2;
		else
		static if(dim<=4 && is(double4))
			alias toNearestSIMDType=double4;
		else
			alias toNearestSIMDType=void;
	}
	else
	static if(is(element_t==int)){
		static if(dim<=2 && is(int4))
			alias toNearestSIMDType=__vector(int[2]);
		else
		static if(dim<=4 && is(int4))
			alias toNearestSIMDType=int4;
		else
		static if(dim<=8 && is(int8))
			alias toNearestSIMDType=int8;
		else
			alias toNearestSIMDType=void;
	}
	else{
		alias toNearestSIMDType=void;
	}
}

template Round_VectorLength(alias len){
	uint __len(){
		switch(len){
			case 1: return len;
			case 2: return len;
			case 3: return 4;
			case 4: return len;
			case 5: return 8;
			case 6: return 8;
			case 7: return 8;
			case 8: return len;
			default: return len;
		}
	}
	enum Round_VectorLength=__len;
}

nothrow pure struct Vector_t(alias dim=3, element_t=float){
	alias __this_type=Vector_t!(dim, element_t);
	alias __dim=dim;
	alias __element_t=element_t;
	mixin("alias __float_type="~__mixin_NearestFloatType!element_t()~";");
	//For stuff that can't be SIMD-ed, like int[32] or sth or for DMD which tries to sabotage 32 bit developers
	static if(is(toNearestSIMDType!(dim, element_t)==void)){
	union{
		element_t[Round_VectorLength!dim] elements;
		alias array=elements;
		static if(dim==2){
			struct{
				element_t x, y, d1, d2;
			}
		}
		static if(dim==3){
			struct{
				//Additional padding element
				element_t x, y, z, w;
			}
		}
		static if(dim==4){
			struct{
				element_t x, y, z, w;
			}
		}
	}
	this(dim, T)(Vector_t!(dim, T) vec){
		this=vec;
	}
	this(T)(T[] val){
		x=cast(typeof(x))val[0]; y=cast(typeof(y))val[1]; z=cast(typeof(z))val[2];
	}
	this(T)(T val) if(isScalar!T){
		elements[0..dim]=cast(element_t)val;
	}
	this(T)(Vector_t!(dim, T) val){
		static if(is(T==element_t)){
			array[0..$]=val.array[0..$];
		}
		else{
			import misc;
			foreach(immutable size_t ind, immutable el; val.array)
				array[ind]=cast(element_t)el;
		}
	}
	static if(dim!=3){
		this(element_t[dim] initelements...){
			elements[]=initelements[];
		}
		this(T)(T val) if(isVector3Like!T && !isVector_t!T){
			this.elements[0..$]=val.elements[0..$];
		}
		this(Args...)(Args args) if(args.length==dim){
			foreach(immutable ind, el; args)
				this.elements[ind]=cast(element_t)el;
		}
	}
	else{
		//Optimized version for fast Vector3_t
		this(T1, T2, T3)(T1 ix, T2 iy, T3 iz){
			x=cast(typeof(x))ix; y=cast(typeof(y))iy; z=cast(typeof(z))iz;
		}
		this(T)(T val) if(isVector3Like!T && !isVector_t!T){
			x=cast(typeof(x))val.x; y=cast(typeof(y))val.y; z=cast(typeof(z))val.z;
		}
	}
	const __this_type opUnary(string op)(){
		return __this_type(mixin(op~"x"), mixin(op~"y"), mixin(op~"z"));
	}
	const __this_type opBinary(string op, T)(T[] arg) if(op!="~"){
		__this_type ret;
		ret.elements=elements;
		mixin("ret.elements[]"~op~"=arg[];");
		return ret;
	}
	const opBinary(string op, T)(T[] arg) if(op=="~"){
		return elements[0..dim]~arg;
	}
	const __this_type opBinary(string op, T)(Vector_t!(dim, T) arg){
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
			foreach(ind; 0..dim)
				mixin("ret.elements[ind]=elements[ind]"~op~"arg;");
			return ret;
		}
	}
	static if(dim==3){
		bool opEquals(T)(T arg) if(isVector3Like!T){
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

	static if(dim==3){
	const __this_type cossin(){return __this_type(degcos(x), degsin(y), degsin(z));}
	const __this_type sincos(){return __this_type(degsin(x), degcos(y), degcos(z));}
	
	const __this_type sincossin(){return __this_type(degsin(x), degcos(y), degsin(z));}
	
	const __this_type sin(){return __this_type(degsin(x), degsin(y), degsin(z));}
	const __this_type cos(){return __this_type(degcos(x), degcos(y), degcos(z));}
	
	const __this_type rotdir(){return __this_type(degcos(x), degsin(x), degcos(y));}
	
	const __this_type vecabs(){
		static if(isFloat!element_t())
			return __this_type(fabs(x), fabs(y), fabs(z));
		else
			return __this_type(std.math.abs(x), std.math.abs(y), std.math.abs(z));
	}
	const __this_type floor(){
		__this_type ret;
		foreach(el; 0..dim)
			ret.elements[el]=cast(typeof(ret.elements[el]))std.math.floor(cast(__float_type)elements[el]);
		return ret;
	}
	const __this_type apply(F)(){
		__this_type ret;
		foreach(el; 0..dim)
			ret.elements[el]=F(elements[el]);
		return ret;
	}
	const Vector_t!(3, T) cross(T)(Vector_t!(3, T) vec){
		return Vector_t!(3, T)(y*vec.z-z*vec.y, z*vec.x-x*vec.z, x*vec.y-y*vec.x);
	}
	const __this_type sgn(){
		return __this_type(std.math.sgn(x), std.math.sgn(y), std.math.sgn(z));
	}
}
	__this_type inv(){
		__this_type ret;
		ret.elements[]=(cast(element_t)1.0)/this.elements[];
		return ret;
	}
	
	static if(dim==3){
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
	}
	
	__this_type min(__this_type vec){
		__this_type ret;
		foreach(i, ref val; this.elements){
			ret.elements[i]=std.algorithm.min(val, vec.elements[i]);
		}
		return ret;
	}

	const bool opEquals(ref const __this_type param){
		return elements==param.elements;
	}
	@safe const nothrow size_t toHash(){
		return typeid(elements).getHash(&elements);
	}
	}
	else{
		union{
			toNearestSIMDType!(dim, element_t) vec;
			static if(dim==2){
				element_t x, y;
			}
			else
			static if(dim==3){
				element_t x, y, z;
			}
			else
			static if(dim==4){
				element_t x, y, z, w;
			}
		}
		alias vec this;
		this(T)(T scalar_var) if(isScalar!T){
			version(GNU){
				foreach(ind; 0..vec.array.length)
					vec.array[ind]=scalar_var;
			}
			else{
				foreach(ref el; vec.array)
					el=scalar_var;
			}
		}
		this(Args...)(Args args) if(Args.length==dim){
			foreach(immutable ind, immutable arg; args)
				vec.array[ind]=cast(element_t)arg;
		}
		this(T, L)(T[L] array_var){
			static if(is(typeof(array_var[0])==element_t)){
				vec.array=array_var;
			}
			else{
				foreach(immutable ind, immutable arg; array_var)
					vec.array[ind]=cast(element_t)arg;
			}
			static if(array_var.length!=array.length)
				vec.array[array_var.length..$]=0;
		}
		this(T)(T[] array_var){
			static if(is(typeof(array_var[0])==element_t)){
				vec.array=array_var;
			}
			else{
				foreach(immutable ind, immutable arg; array_var)
					vec.array[ind]=cast(element_t)arg;
			}
			if(array_var.length!=array.length)
				vec.array[array_var.length..$]=0;
		}
		this(T)(T vector_var) if(isVector_t!T){
			static if(__traits(compiles, vector_var.vec))
				vec=vector_var.vec;
			else
				this(vector_var.array);
		}
		this(T)(T vector_var) if(isSIMDVector!T && T.array.length==dim){
			this(vector_var.array);
			static if(T.array.length<array.length)
				array[T.array.length..array.length]=0;
		}
		//DEPRECATED
		ref auto elements(){return vec.array;}
		__this_type opAssign(Args...)(Args args){
			return __this_type(args);
		}
		
		int opCmp(T)(T arg){
			auto diff=this.vec-arg.vec;
			auto vec=this-arg;
			element_t[] el=vec.array;
			auto avg=sum(el, 0.0)/vec.array.length;
			if(std.math.abs(avg)<1.0)
				avg/=avg*std.math.sgn(avg);
			return cast(int)avg;
		}
		
		const opUnary(string op)(){
			__this_type ret;
			mixin("ret.vec="~op~"vec;");
			return ret;
		}

		const opBinary(string op, T)(T arg){
			__this_type ret;
			ret.vec=vec;
			static if([">>", "<<", "/"].canFind(op)){
				static if(__traits(isScalar, T)){
					foreach(immutable ind, ref el; ret.vec.array){
						mixin("el"~op~"=arg;");
					}
				}
				else
				static if(isArray!T){
					foreach(immutable ind, immutable el; arg){
						mixin("ret.array[ind]"~op~"=el;");
					}
				}
				else
				static if(isVector_t!T){
					foreach(immutable ind, ref el; ret.vec.array){
						mixin("el"~op~"=arg.array[ind];");
					}
				}
			}
			else{
				static if(__traits(isScalar, T)){
					mixin("ret.vec"~op~"=arg;");
				}
				else
				static if(isArray!T){
					mixin("ret.array[]"~op~"=arg[];");
				}
				else
				static if(isVector_t!T){
					static if(__traits(compiles, arg.vec) && is(typeof(arg.vec)==typeof(vec))){
						mixin("ret.vec=ret.vec"~op~"cast(typeof(ret.vec))arg.vec;");
					}
					else{
						foreach(immutable ind, immutable el; arg.array){
							mixin("ret.array[ind]"~op~"=el;");
						}
					}
				}
			}
			return ret;
		}
	
		__this_type opOpAssign(string op, T)(T arg){
			this=this.opBinary!(op)(arg);
			return this;
		}
		
		const vmin(T)(Vector_t!(dim, T) val){
			__this_type ret;
			foreach(immutable ind, immutable el; val.elements)
				ret.vec.array[ind]=std.algorithm.min(el, val.vec.array[ind]);
			return ret;
		}
		const vmax(T)(Vector_t!(dim, T) val){
			__this_type ret;
			foreach(immutable ind, immutable el; val.elements)
				ret.array[ind]=std.algorithm.max(el, val.array[ind]);
			return ret;
		}
		const vecabs(){
			__this_type ret;
			foreach(immutable ind; 0..dim){
				static if(isFloat!element_t())
					ret.array[ind]=fabs(array[ind]);
				else
					ret.array[ind]=std.math.abs(array[ind]);
			}
			return ret;
		}
		const sgn(){
			__this_type ret;
			foreach(immutable ind, immutable el; array)
				ret.array[ind]=std.math.sgn(el);
			return ret;
		}
	}
	
	__this_type opAssign(T)(Vector_t!(dim, T) val){
		static if(__traits(compiles, this.vec) && is(T==__this_type)){
			vec=T.vec;
		}
		else{
			foreach(immutable ind, immutable el; val.array)
				this.array[ind]=el;
		}
		return this;
	}
	
	__this_type opAssign(T)(T val) if(isScalar!T){
		foreach(immutable ind; 0..dim){
			this.array[ind]=val;
		}
		return this;
	}
	
	void opIndexAssign(T)(element_t val, T ind){
		array[ind]=val;
	}
	
	ref opIndex(T)(T ind){
		return array[ind];
	}
	
	const dot(T)(Vector_t!(dim, T) arg){
		T ret=0.0;
		foreach(immutable ind; 0..dim){
			ret+=array[ind]*arg.array[ind];
		}
		return ret;
	}
	const sqlength(){
		element_t sumsq=0;
		foreach(immutable el; array[0..dim]){
			sumsq+=el*el;
		}
		return sumsq;
	}
	const length(){
		return cast(element_t)std.math.sqrt(cast(toNearestFloatType!(element_t))this.sqlength);
	}
	//Deprecated, use normal
	alias abs=normal;
	const normal(){
		return this/this.length;
	}

	const T opCast(T)() if(isArray!T){return elements[0..dim];}
	const T opCast(T)() if(is(T==bool)){
		foreach(immutable el; this.array)
			if(el)
				return true;
		return false;
	}
	
	
	const __this_type filter(T)(T filterarr) if(isArray!T){
		__this_type ret;
		foreach(i; 0..dim){
			ret.array[i]=filterarr[i] ? array[i] : cast(element_t)0;
		}
		return ret;
	}
	mixin(__mixin_VectorCTFilter!(dim)());
	mixin(__mixin_VectorRTFilter!(dim)());
	
	const string toString(){
		string ret="{";
		foreach(i; 0..dim){
			static if(isFloatingPoint!element_t)
				ret~=format("%10.10f", array[i]);
			else
			static if(isIntegral!element_t)
				ret~=format("%d", array[i]);
			else
				ret~=format("%s", array[i]);
			if(i!=dim-1)
				ret~=";";
		}
		ret~="}";
		return ret;
	}
}


//Deprecated
alias Vector3_t=Vector_t!(3);
alias Vector4_t=Vector_t!(4);

alias uVector3_t=Vector_t!(3, uint);
alias iVector3_t=Vector_t!(3, int);
alias fVector3_t=Vector_t!(3, float);

auto vmin(T1, T2, R=T1.__element_t)(T1 vec1, T2 vec2) if(isVector_t!T1 && isVector_t!T2 && T1.__dim==T2.__dim){
	Vector_t!(T1.__dim, R) ret;
	foreach(immutable ind; 0..T1.__dim)
		ret.array[ind]=min(vec1.array[ind], vec2.array[ind]);
	return ret;
}


auto vmax(T1, T2, R=T1.__element_t)(T1 vec1, T2 vec2) if(isVector_t!T1 && isVector_t!T2 && T1.__dim==T2.__dim){
	Vector_t!(T1.__dim, R) ret;
	foreach(immutable ind; 0..T1.__dim)
		ret.array[ind]=max(vec1.array[ind], vec2.array[ind]);
	return ret;
}

fVector3_t RandomVector(){
	return fVector3_t(uniform01()*2.0-1.0, uniform01()*2.0-1.0, uniform01()*2.0-1.0);
}

auto filter(alias x, alias y, alias z, T)(Vector_t!(3, T) arg){
	return Vector_t!(3, T)(x ? arg.x : 0, y ? arg.y : 0, z ? arg.z : 0);
}

auto filter(T)(Vector_t!(3, T) arg, bool x, bool y, bool z){
	return Vector_t!(3, T)(x ? arg.x : 0, y ? arg.y : 0, z ? arg.z : 0);
}

auto sgn(alias D=3, T=float)(Vector_t!(D, T) arg){
	Vector_t!(D, T) ret;
	foreach(immutable ind; 0..D){
		ret.elements[ind]=arg.elements[ind];
	}
	return ret;
}

	//This function is correct (lecom approved) (except for maybe negligible precision loss)
	//(Not suitable for OpenGL, needs corrections for that)
auto RotationAsDirection(T=float)(Vector_t!(3, T) arg){
	auto dir=typeof(arg)(1.0, 0.0, 0.0);
	dir=dir.rotate(typeof(arg)(arg.y, arg.x, arg.z));
	auto result=typeof(arg)(dir.x, -dir.z, dir.y);
	return result;
}
	
auto DirectionAsRotation(T=float)(Vector_t!(3, T) arg){
	float ry=atan2(cast(arg.__float_type)arg.z, cast(arg.__float_type)arg.x)*180.0/PI;
	float rx=asin(cast(arg.__float_type)arg.y)*180.0/PI;
	float rz=0.0;
	return typeof(arg)(rx, ry, rz);
}

auto rotate(T=float, TR=float)(Vector_t!(3, T) arg, Vector_t!(3, TR) rot){
	Vector_t!(3, T) rrot=rot;
	rrot.x=rot.z; rrot.z=rot.x;
	return arg.rotate_raw(rrot);
}

auto rotate_raw(T=float, TR=float)(Vector_t!(3, T) arg, Vector_t!(3, TR) rot){
	Vector_t!(3, T) ret=arg, tmp=arg;
	Vector_t!(3, T) vsin=rot.sin(), vcos=rot.cos();
	ret.y=tmp.y*vcos.x-tmp.z*vsin.x; ret.z=tmp.y*vsin.x+tmp.z*vcos.x;
	tmp.x=ret.x; tmp.z=ret.z;
	ret.z=tmp.z*vcos.y-tmp.x*vsin.y; ret.x=tmp.z*vsin.y+tmp.x*vcos.y;
	tmp.x=ret.x; tmp.y=ret.y;
	ret.x=tmp.x*vcos.z-tmp.y*vsin.z; ret.y=tmp.x*vsin.z+tmp.y*vcos.z;
	return ret;
}
	
auto rotate_raw(T=float, TS=float, TC=float)(Vector_t!(3, T) arg, Vector_t!(3, TS) vsin, Vector_t!(3, TC) vcos){
	Vector_t!(3, T) ret=arg, tmp=arg;
	ret.y=tmp.y*vcos.x-tmp.z*vsin.x; ret.z=tmp.y*vsin.x+tmp.z*vcos.x;
	tmp.x=ret.x; tmp.z=ret.z;
	ret.z=tmp.z*vcos.y-tmp.x*vsin.y; ret.x=tmp.z*vsin.y+tmp.x*vcos.y;
	tmp.x=ret.x; tmp.y=ret.y;
	ret.x=tmp.x*vcos.z-tmp.y*vsin.z; ret.y=tmp.x*vsin.z+tmp.y*vcos.z;
	return ret;
}

auto cossin(T=float)(Vector_t!(3, T) arg){return typeof(arg)(degcos(arg.x), degsin(arg.y), degsin(arg.z));}
auto sincos(T=float)(Vector_t!(3, T) arg){return typeof(arg)(degsin(arg.x), degcos(arg.y), degcos(arg.z));}

auto sincossin(T=float)(Vector_t!(3, T) arg){return typeof(arg)(degsin(arg.x), degcos(arg.y), degsin(arg.z));}
	
auto sin(T=float)(Vector_t!(3, T) arg){return typeof(arg)(degsin(arg.x), degsin(arg.y), degsin(arg.z));}
auto cos(T=float)(Vector_t!(3, T) arg){return typeof(arg)(degcos(arg.x), degcos(arg.y), degcos(arg.z));}

T degsin(T)(T val){
	return cast(T)std.math.sin(val*PI/cast(T)180.0);
}

T degcos(T)(T val){
	return cast(T)std.math.cos(val*PI/cast(T)180.0);
}

auto abssum(alias D=3, T=float)(Vector_t!(3, T) arg){
	T ret=0.0;
	foreach(immutable el; arg.array)
		ret+=std.math.abs(el);
	return ret;
}

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
