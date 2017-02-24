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

template Fields(T)
{
    static if (is(T == struct) || is(T == union))
        alias Fields = typeof(T.tupleof[0 .. $ - isNested!T]);
    else static if (is(T == class))
        alias Fields = typeof(T.tupleof);
    else
        alias Fields = TypeTuple!T;
}

template FieldNameTuple(T)
{
    static if (is(T == struct) || is(T == union))
        alias FieldNameTuple = staticMap!(NameOf, T.tupleof[0 .. $ - isNested!T]);
    else static if (is(T == class))
        alias FieldNameTuple = staticMap!(NameOf, T.tupleof);
    else
        alias FieldNameTuple = TypeTuple!"";
}

template staticMap(alias F, T...)
{
    static if (T.length == 0)
    {
        alias staticMap = AliasSeq!();
    }
    else static if (T.length == 1)
    {
        alias staticMap = AliasSeq!(F!(T[0]));
    }
    else
    {
        alias staticMap =
            AliasSeq!(
                staticMap!(F, T[ 0  .. $/2]),
                staticMap!(F, T[$/2 ..  $ ]));
    }
}

private enum NameOf(alias T) = T.stringof;

template AliasSeq(TList...)
{
    alias AliasSeq = TList;
}
