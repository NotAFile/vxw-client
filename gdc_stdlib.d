//The GDC D compiler has a deprecated stdlib. This file should fix the problems arising from that.
import core.stdc.string;
import std.random;
import std.math;
import std.traits;
import misc;

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

template TemplateOf(alias T : Base!Args, alias Base, Args...)
{
    alias TemplateOf = Base;
}

template TemplateOf(T : Base!Args, alias Base, Args...)
{
    alias TemplateOf = Base;
}
