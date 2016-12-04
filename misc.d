import std.stdio;
import std.traits;
import std.algorithm;

void writeflnerr(Args...)(Args args){
	stdout.write("[ERROR]");
	stdout.writefln(args);
	stdout.flush();
}

void writeflnlog(Args...)(Args args){
	stdout.write("[LOG]");
	stdout.writefln(args);
	stdout.flush();
}

float tofloat(T)(T var){
	return cast(float)var;
}

int toint(T)(T var){
	return cast(int)var;
}

uint touint(T)(T var){
	return cast(uint)var;
}

T SGN(T)(T x){
	if(!x)
		return cast(T)0;
	if(x>0.0)
		return cast(T)1;
	return cast(T)-1;
}

T proper_reverse(T)(T arr){
	T ret;
	//static if(!__traits(isStaticArray, arr))
	//	ret.length=arr.length;
	uint i;
	for(i=0; i<arr.length/2; i++){
		ret[i]=arr[arr.length-1-i];
		ret[arr.length-1-i]=arr[i];
	}
	if(arr.length%2){
		ret[arr.length/2]=arr[arr.length/2];
	}
	return ret;
}

void proper_reverse_overwrite(T)(ref T arr){
	uint i;
	for(i=0; i<arr.length/2; i++)
		swap(arr[i], arr[arr.length-1-i]);
}
