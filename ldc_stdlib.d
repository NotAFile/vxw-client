//LDC doesn't properly support the Dlang stdlib. This file adds some of the (basic) dstdlib features that LDC doesn't have
import core.stdc.string;
import std.random;
import std.math;
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
