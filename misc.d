import derelict.sdl2.sdl;
import std.stdio;
import std.traits;
import std.algorithm;
import std.system;
import std.math;
import std.conv;
import core.time;
import std.datetime;
import core.thread;
import std.traits;

version(DigitalMars){
	immutable bool Program_Is_Optimized=false;
}
else{
	immutable bool Program_Is_Optimized=true;
}
version(X86){
	alias register_t=uint;
	alias signed_register_t=int;
}
version(X86_64){
	alias register_t=ulong;
	alias signed_register_t=long;
}
static if(!is(register_t)){
	alias register_t=uint;
	alias signed_register_t=int;
}

static immutable bool Use_Assembler_Code=false;

static if(Use_Assembler_Code){
	version(D_InlineAsm_X86){
		immutable bool AssemblerCode_Enabled=true;
	}
	else{
		version(D_InlineAsm_X86_64){
			immutable bool AssemblerCode_Enabled=true;
			
		}
		else{
			immutable bool AssemblerCode_Enabled=false;
		}
	}
	static if(AssemblerCode_Enabled){
		version(LDC){
			immutable string AssemblerCode_BlockStart="asm";
		}
		else{
			immutable string AssemblerCode_BlockStart="asm nothrow pure";
		}
	}
}
else{
	immutable bool AssemblerCode_Enabled=false;
}

version(DigitalMars){
	string TypeName(T)(){
		return fullyQualifiedName!T;
	}
}
else{
	string TypeName(T)(){
		return T.stringof;
	}
}

static if(__traits(compiles, MonoTime.currTime)){
	alias PreciseClock=MonoTime.currTime;
	alias PreciseClock_t=MonoTimeImpl!(cast(ClockType)0);
	alias PreciseClockDiff_t=Duration;
	auto PreciseClock_DiffFromNSecs(IT)(IT val){
		return dur!"nsecs"(to!long(val))/10;
	}
	
	auto PreciseClock_TimeFromNSecs(IT)(IT val){
		return PreciseClock_ToTime(dur!"nsecs"(to!long(val)));
	}

	void PreciseClock_Wait(T)(T delay){
		Thread.sleep(delay);
	}
	//DEPRECATED - USE NSECS
	uint PreciseClock_ToMSecs(T)(T val){
		static if(is(T==Duration))
			return val.total!"msecs";
		else
			return cast(uint)(val.ticks*1000/val.ticksPerSecond);
	}
	
	long PreciseClock_ToNSecs(T)(T val){
		static if(is(T==Duration))
			return val.total!"nsecs"*10;
		else
			return cast(uint)(val.ticks*10e9/val.ticksPerSecond);
	}
	
	auto PreciseClock_ToTime(T)(T val){
		return MonoTime(val.total!"nsecs");
	}
	
	auto PreciseClock_ToDuration(T)(T val){
		return dur!"nsecs"(val);
	}
}
else
static if(__traits(compiles, Clock.currAppTick)){
	pragma(msg, "[NOTE]Your compiler and/or system doesn't support DLang's specialized monotonic clock. Expect \"jumps\" in time and other issues.");
	alias PreciseClock=Clock.currAppTick;
	alias PreciseClock_t=TickDuration;
	alias PreciseClockDiff_t=TickDuration;
	auto PreciseClock_DiffFromNSecs(T)(T val){
		return TickDuration.from!"nsecs"(to!long((cast(long)val)*TickDuration.ticksPerSec/10e9));
	}
	
	auto PreciseClock_TimeFromNSecs(T)(T val){
		return TickDuration.from!"nsecs"(to!long((cast(long)val)*TickDuration.ticksPerSec/10e9));
	}

	void PreciseClock_Wait(T)(T delay){
		Thread.sleep(to!Duration(delay));
	}

	uint PreciseClock_ToMSecs(T)(T val){
		return to!uint((val).to!("msecs", ulong)()*10e8/TickDuration.ticksPerSec);
	}
	
	ulong PreciseClock_ToNSecs(T)(T val){
		return to!ulong((val).to!("nsecs", ulong)()*10e9/TickDuration.ticksPerSec);
	}
}
else{
	pragma(msg, "[NOTE]Your compiler and/or system doesn't support DLang's high precision clocks.
Falling back to slightly unprecise SDL clock. Don't expect super-precise framerate timing.");
	alias PreciseClock=SDL_GetTicks;
	alias PreciseClock_t=uint;
	alias PreciseClockDiff_t=uint;
	auto PreciseClock_DiffFromNSecs(T)(T val){
		return val/10e6;
	}
	auto PreciseClock_TimeFromNSecs(T)(T val){
		return val/10e6;
	}
	void PreciseClock_Wait(T)(T delay){
		SDL_Delay(cast(uint)delay);
	}
	uint PreciseClock_ToMSecs(T)(T val){
		return val;
	}
	
	long PreciseClock_ToNSecs(T)(T val){
		return to!long(val*10e6);
	}
}

unittest{
	assert(PreciseClock_ToNSecs(PreciseClock_DiffFromNSecs(1337000))==1337000);
}

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

immutable uint BITS_PER_BYTE=8;
//credits go to the genious guy who wrote https://graphics.stanford.edu/~seander/bithacks.html#IntegerMinOrMax
T bitwise_min(T)(T x, T y){
	return y + ((x - y) & ((x - y) >> (T.sizeof * BITS_PER_BYTE - 1)));
}

TR int_sqrt(TI, TR=TI)(TI val){
	return cast(TR)sqrt(cast(double)val);
}
