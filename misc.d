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
