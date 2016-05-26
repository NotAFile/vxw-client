import std.stdio;

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
