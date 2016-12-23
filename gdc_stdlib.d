//The GDC D compiler has a deprecated stdlib. This file should fix the problems arising from that.
import core.stdc.string;
import std.random;
import std.math;
import std.traits;
import misc;

const(char)[] fromStringz(const(char)* cstr){
	uint ln=cast(uint)strlen(cstr);
	return cstr[0..ln];
}

double uniform01(){
	return uniform!"[)"(0.0, 1.0);
}

T[] dup(T)(T[] arr){
	T[] ret;
	ret.length=arr.length;
	ret[]=arr[];
	return ret;
}

template Parameters(alias func){
	alias ParameterTypeTuple!(func) Parameters;
}
