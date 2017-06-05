version(LDC){
	import ldc_stdlib;
}
version(GNU){
	import gdc_stdlib;
}
version(DMD){
	import std.meta;
}
import sdl2;
import core.stdc.stdlib;
import slang;
import misc;
import ui;
import gfx;
import world;
import protocol;
import packettypes;
import network;
import renderer;
import vector;
import std.string;
import std.traits;
import std.format;
import std.datetime;
import std.algorithm;
import std.typetuple;
import std.conv;
import std.stdio;
import std.random;

class SLangFunctionNotFound : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}


class SLangException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line);
    }
}

extern(C){

alias ScriptIndex_t=short;

ScriptIndex_t Current_Script_Index=-1;
char* toCString(string st){return cast(char*)toStringz(st);}

void SLStdLib_DisabledFunc(){}
string[] SLStdLib_DisabledFuncs=["get_doc_string_from_file", "add_doc_file", "get_doc_files", "set_doc_files", "autoload", "getenv", "putenv",
"get_environ", "evalfile", "eval", "system", "system_intr", "_apropos", "_get_namespaces", "_trace_function", "byte_compile_file",
"_clear_error", "_function_name", "set_float_format", "get_float_format", "fpu_test_except_bits",
"__get_defined_symbols", "use_namespace", "current_namespace", "__set_argc_argv"];
uint SLStdLib_DisabledVar=0;
string[] SLStdLib_DisabledVars=["_slang_install_prefix"];

//Just btw the whole intrinsic function table thing is broken af (seems like only aggregate types like structures and bstring get passed properly).
//But that's not a problem since we can just pop the stuff we need from the stack.
//(S-Lang won't check amount of arguments and just throws them all on the stack)
SLang_Intrin_Fun_Type[] ScrGuiLib_Funcs(){
return [
	MAKE_INTRINSIC_0(cast(char*)toStringz("MenuElement_Create"), &ScrGuiLib_MenuElementCreate, SLANG_VOID_TYPE),
	MAKE_INTRINSIC_1(cast(char*)toStringz("MenuElement_Update"), &ScrGuiLib_MenuElementUpdate, SLANG_VOID_TYPE, SLANG_STRUCT_TYPE),
	MAKE_INTRINSIC_1(cast(char*)toStringz("MenuElement_Delete"), &ScrGuiLib_MenuElementDelete, SLANG_VOID_TYPE, SLANG_STRUCT_TYPE),
	MAKE_INTRINSIC_1(cast(char*)toStringz("Object_Hovered"), &ScrGuiLib_Object_Hovered, SLANG_UCHAR_TYPE, SLANG_STRUCT_TYPE),
	MAKE_INTRINSIC_0(cast(char*)toStringz("Mouse_LeftClick"), &ScrGuiLib_MouseLeftClicked, SLANG_UCHAR_TYPE),
	MAKE_INTRINSIC_0(cast(char*)toStringz("Mouse_RightClick"), &ScrGuiLib_MouseRightClicked, SLANG_UCHAR_TYPE),
	MAKE_INTRINSIC_0(cast(char*)toStringz("Mouse_LeftChanged"), &ScrGuiLib_MouseLeftChanged, SLANG_UCHAR_TYPE),
	MAKE_INTRINSIC_0(cast(char*)toStringz("Mouse_RightChanged"), &ScrGuiLib_MouseRightChanged, SLANG_UCHAR_TYPE),
	MAKE_INTRINSIC_0(cast(char*)toStringz("MenuMode_Get"), &ScrGuiLib_MenuMode_Get, SLANG_UCHAR_TYPE),
	//MAKE_INTRINSIC_1(cast(char*)toStringz("MenuMode_Set"), &ScrGuiLib_MenuMode_Set, SLANG_VOID_TYPE, SLANG_UCHAR_TYPE),
	MAKE_INTRINSIC_0(cast(char*)toStringz("StandardFont_Get"), &ScrGuiLib_StandardFont_Get, SLANG_UCHAR_TYPE),
	MAKE_INTRINSIC_1(cast(char*)toStringz("StandardFont_Set"), &ScrGuiLib_StandardFont_Set, SLANG_VOID_TYPE, SLANG_UCHAR_TYPE), //Doesn't work btw lel
	MAKE_INTRINSIC_0(cast(char*)toStringz("MouseX"), &ScrGuiLib_MouseX, SLANG_DOUBLE_TYPE),
	MAKE_INTRINSIC_0(cast(char*)toStringz("MouseY"), &ScrGuiLib_MouseY, SLANG_DOUBLE_TYPE),
	MAKE_INTRINSIC_0(cast(char*)toStringz("TextBox_Create"), &ScrGuiLib_TextBoxCreate, SLANG_VOID_TYPE),
	MAKE_INTRINSIC_1(cast(char*)toStringz("TextBox_Update"), &ScrGuiLib_TextBoxUpdate, SLANG_VOID_TYPE, SLANG_STRUCT_TYPE),
	MAKE_INTRINSIC_1(cast(char*)toStringz("TextBox_Delete"), &ScrGuiLib_TextBoxDelete, SLANG_VOID_TYPE, SLANG_STRUCT_TYPE),
	MAKE_INTRINSIC_0(cast(char*)toStringz("PictureColor_Get"), &ScrGuiLib_PictureColorGet, SLANG_UINT_TYPE),
	MAKE_INTRINSIC_0(cast(char*)toStringz("MiniMap_Shown"), &ScrGuiLib_MiniMap_Shown, SLANG_UCHAR_TYPE),
	MAKE_INTRINSIC_1(cast(char*)toStringz("MenuElement_Render"), &ScrGuiLib_MenuElementRender, SLANG_VOID_TYPE, SLANG_STRUCT_TYPE),
	SLANG_END_INTRIN_FUN_TABLE()
];
}

SLang_Intrin_Fun_Type[] ScrWorldLib_Funcs(){
return[
	MAKE_INTRINSIC_0(cast(char*)toStringz("FogColor_Get"), &ScrWorldLib_FogColorGet, SLANG_UINT_TYPE),
	MAKE_INTRINSIC_0(cast(char*)toStringz("FogColor_Set"), &ScrWorldLib_FogColorSet, SLANG_VOID_TYPE),
	MAKE_INTRINSIC_0(cast(char*)toStringz("VisibilityRange_Get"), &ScrWorldLib_VisibilityRangeGet, SLANG_UINT_TYPE),
	MAKE_INTRINSIC_0(cast(char*)toStringz("VisibilityRange_Set"), &ScrWorldLib_VisibilityRangeSet, SLANG_VOID_TYPE),
	MAKE_INTRINSIC_0(cast(char*)toStringz("EnvEffectSlot_Alloc"), &ScrWorldLib_EnvEffectSlotAlloc, SLANG_UINT_TYPE),
	MAKE_INTRINSIC_1(cast(char*)toStringz("EnvEffectSlot_Set"), &ScrWorldLib_EnvEffectSlotSet, SLANG_VOID_TYPE, SLANG_STRUCT_TYPE),
	MAKE_INTRINSIC_0(cast(char*)toStringz("Voxel_Del"), &ScrWorldLib_VoxelDel, SLANG_VOID_TYPE),
	SLANG_END_INTRIN_FUN_TABLE()
];
}

struct SLIntrinFunc_t{
	string name;
	void *funcptr;
	SLtype[SLANG_MAX_INTRIN_ARGS] arg_types;
	uint num_args;
	SLtype ret_type;
}

template Make_SLang_Func_Intrinsic(alias name, alias func){
	private SLIntrinFunc_t make_intr(){
		SLIntrinFunc_t intr=SLIntrinFunc_t(name, &func, 0, 0, DLangType_To_SLangType!(ReturnType!func)());
		foreach(ind, param; Parameters!func)
			intr.arg_types[ind]=DLangType_To_SLangType!(param)();
		intr.num_args=Parameters!func.length;
		return intr;
	}
	enum Make_SLang_Func_Intrinsic=make_intr();
}

SLIntrinFunc_t[] ScrWorldLibFuncs=[Make_SLang_Func_Intrinsic!("FogColor_Get", ScrWorldLib_FogColorGet)];

SLang_NameSpace_Type *ScrStdLib_Ns;

struct ScriptLib_t{
	string typename;
	string nsname;
	SLang_NameSpace_Type *ns;
	SLstr_Type *nshashname;
	this(string initname, string libname){
		typename=initname;
		nsname=libname;
		if(nsname.length){
			ns=SLns_create_namespace(toStringz(nsname));
			nshashname=SLang_create_slstring(toStringz(nsname));
		}
		SLang_Intrin_Fun_Type[] intr_func_table;
		switch(nsname){
			case "scrgui":{
				intr_func_table=ScrGuiLib_Funcs();
				SLns_add_intrinsic_variable(ns, toStringz("Font_SpecialColor"), &Font_SpecialColor, DLangType_To_SLangType!(typeof(Font_SpecialColor))(), 1);
				SLns_add_intrinsic_variable(ns, toStringz("StartZPos"), &StartZPos, DLangType_To_SLangType!(typeof(StartZPos))(), 1);
				SLns_add_intrinsic_variable(ns, toStringz("MiniMapZPos"), &MiniMapZPos, DLangType_To_SLangType!(typeof(MiniMapZPos))(), 1);
				SLns_add_intrinsic_variable(ns, toStringz("InvisibleZPos"), &InvisibleZPos, DLangType_To_SLangType!(typeof(InvisibleZPos))(), 1);
				SLns_add_intrinsic_variable(ns, toStringz("ScreenXSize"), &ScreenXSize, DLangType_To_SLangType!(typeof(ScreenXSize))(), 1);
				SLns_add_intrinsic_variable(ns, toStringz("ScreenYSize"), &ScreenYSize, DLangType_To_SLangType!(typeof(ScreenYSize))(), 1);
				SLns_add_intrinsic_function(ns, toStringz("MenuMode_Set"), &ScrGuiLib_MenuMode_Set, SLANG_VOID_TYPE, 0);
				break;
			}
			case "scrworld":{
				intr_func_table=ScrWorldLib_Funcs();
				break;
			}
			default:break;
		}
		if(intr_func_table.length){
			if(SLns_add_intrin_fun_table(ns, intr_func_table.ptr, cast(const(char*))toStringz(nsname)))
				writeflnerr("Couldn't add intrinsic function table for script library \"%s\"", typename);
		}
		/*version(GNU){
			import if_you_have_compiler_optimization_flags_enabled_then_remove_or_comment_out_the_statement_below_and_this_import;
		}
		if(nsname.length)
			ns.namespace_name=null;*/
	}
}

private ScriptLib_t[] ScriptLibraries=[];

SLtype DLangType_To_SLangType(type)(){
	static if(is(type==uint))
		return SLANG_UINT_TYPE;
	static if(is(type==int))
		return SLANG_INT_TYPE;
	static if(is(type==ubyte))
		return SLANG_UCHAR_TYPE;
	static if(is(type==float))
		return SLANG_FLOAT_TYPE;
	static if(is(type==SLang_Struct_Type*))
		return SLANG_STRUCT_TYPE;
	static if(is(type==void))
		return SLANG_VOID_TYPE;
}

template _ArrayElementType(T : T[])
{
  alias T _ArrayElementType;
}

void *DLangObject_To_SLangObject(T)(T obj, out SLtype sltype){
	static if(is(type==float)){
		sltype=SLANG_FLOAT_TYPE;
		return &obj;
	}
	else static if(isArray!T){
		SLindex_Type ind=obj.length;
		SLang_Array_Type *arr=SLang_create_array1(DLangType_To_SLangType!(_ArrayElementType!(T))(), 1, obj.ptr, &ind, 1, 1);
		sltype=SLANG_ARRAY_TYPE;
		return &obj;
	}
	else
	static assert(0);
}

void Push_DLang_Object(T)(T obj){
	alias type=typeof(obj);
	static if(is(type==string)){SLang_push_string(cast(char*)toStringz(obj));}
	else static if(is(type==uint)){SLang_push_uint(obj);}
	else static if(is(type==int)){SLang_push_int(obj);}
	else static if(is(type==ubyte)){SLang_push_uchar(obj);}
	else static if(is(type==byte)){SLang_push_char(obj);}
	else static if(is(type==float)){SLang_push_float(obj);}
	else static if(is(type==ubyte[])){SLang_push_bstring(SLbstring_create(obj.ptr, cast(uint)obj.length));}
	else static if(is(type==bool)){SLang_push_uchar(cast(ubyte)obj);}
	//NOTE: It's a complicated situation with those vectors and arrays, since 
	else static if(is(type==Vector_t!())){
		SLindex_Type ind=obj.elements.length;
		type.__element_t *elements=cast(type.__element_t*) malloc(type.__element_t.sizeof*type.__dim);
		elements[0..type.__dim]=obj.elements;
		SLang_Array_Type *arr=SLang_create_array1(DLangType_To_SLangType!(typeof(type.x))(), 1, elements, &ind, 1, 1);
		SLang_push_array(arr, 1);
	}
	else static if(isArray!type){
		SLindex_Type ind=obj.length;
		SLang_Array_Type *arr=SLang_create_array1(DLangType_To_SLangType!(_ArrayElementType!(type))(), 1, obj.ptr, &ind, 1, 1);
		SLang_push_array(arr, 0);
	}
	else static if(isPointer!type){
		static if(isArray!(PointerTarget!type)){
			SLindex_Type ind=obj.length;
			SLang_Array_Type *arr=SLang_create_array1(DLangType_To_SLangType!(_ArrayElementType!(PointerTarget!type))(), 0, obj.ptr, &ind, 1, 1);
			SLang_push_array(arr, 0);
		}
		else static if(is(type==Vector_t!()*)){
			SLindex_Type ind=obj.elements.length;
			SLang_Array_Type *arr=SLang_create_array1(DLangType_To_SLangType!(typeof(type.x))(), 0, obj.elements.ptr, &ind, 1, 1);
			SLang_push_array(arr, 0);
		}
		else
			return Push_DLang_Object(*obj);
	}
	else
	static assert(0);
}

void SLangObject_Push(void *obj, SLtype type){
	final switch(type){
		case SLANG_FLOAT_TYPE:SLang_push_float(*(cast(float*)obj));break;
		case SLANG_ARRAY_TYPE:SLang_push_array(cast(SLang_Array_Type*)obj, 0); break;
	}
}

struct Script_t{
	ScriptIndex_t index;
	bool initialized;
	bool has_exception;
	string name, content;
	string nsname;
	bool enabled, call_on_frame, call_on_minimap_render;
	SLang_NameSpace_Type *localns;
	ScriptLib_t *sclibrary;
	this(ScriptIndex_t initindex, string filename, string initcontent){
		index=initindex;
		name=filename;
		content=initcontent;
		has_exception=false;
		nsname=format("___clntscrptns_%x_", index);
		enabled=false;
		sclibrary=null;
		if(content[0..2]=="%#"){
			string scrlibname="";
			uint chars_to_skip=0;
			foreach(ref c; content[2..$]){
				if(c=='\n' || c=='\0')
					break;
				scrlibname~=c;
				chars_to_skip++;
			}
			content=content[chars_to_skip+2..$];
			foreach(ref sclib; ScriptLibraries){
				if(sclib.typename==scrlibname){
					sclibrary=&sclib;
					break;
				}
			}
		}
	}
	void Init(){
		uint stkdepth1=SLstack_depth();
		if(sclibrary){
			if(sclibrary.ns){
				sclibrary.ns.namespace_name=sclibrary.nshashname;
			}
		}
		localns=SLns_create_namespace(cast(const(char*))toStringz(nsname));
		writeflnlog("table size before:%s", localns.table_size);
		SLns_load_string(cast(const(char*))toStringz(content), cast(const(char*))toStringz(nsname));
		writeflnlog("table size after:%s (smh)", localns.table_size);
		if(sclibrary){
			if(sclibrary.ns){
				sclibrary.ns.namespace_name=null;
			}
		}
		uint stkdepth2=SLstack_depth();
		if(stkdepth2!=stkdepth1){
			writeflnerr("Script %s changed S-Lang stack depth from %d to %d while initializing", name, stkdepth1, stkdepth2);
			if(stkdepth2>stkdepth1){
				writeflnerr("(Stack overflow, fixing)");
				SLdo_pop_n(stkdepth2-stkdepth1);
			}
			else{
				writeflnerr("(Stack underflow, very dangerous");
			}
		}
		initialized=true;
	}
	void Uninit(){
		SLns_delete_namespace(localns);
	}
	void Set_Enabled(bool run, bool repeat, bool minimap){
		call_on_frame=repeat; call_on_minimap_render=minimap;
		if(run){
			Call_Func("RunScript");
			enabled=false;
			return;
		}
	}
	void Call_Func(T...)(string funcname, T args){
		if(has_exception)
			return;
		Current_Script_Index=index;
		if(!initialized)
			Init();
		uint stkdepth1=SLstack_depth();
		if(sclibrary){
			if(sclibrary.ns){
				sclibrary.ns.namespace_name=sclibrary.nshashname;
			}
		}
		foreach(ref arg; args){
			Push_DLang_Object(arg);
		}
		const char *nsfuncname=cast(const(char*))toStringz(nsname~"->"~funcname);
		auto ret=SLang_execute_function(nsfuncname);
		if(ret<1){
			if(!ret){
				has_exception=true;
				//writeflnerr("SLang function %s(%s) doesn't exist in script %s", funcname, fromStringz(nsfuncname), name);
				throw new SLangFunctionNotFound(format("SLang function %s(%s) doesn't exist in script %s", funcname, fromStringz(nsfuncname), name));
			}
			else{
				has_exception=true;
				//writeflnerr("Exception while executing SLang function %s(%s) in script %s", funcname, fromStringz(nsfuncname), name);
				throw new SLangException(format("Exception while executing SLang function %s(%s) in script %s", funcname, fromStringz(nsfuncname), name));
			}
		}
		if(sclibrary){
			if(sclibrary.ns){
				sclibrary.ns.namespace_name=null;
			}
		}
		uint stkdepth2=SLstack_depth();
		if(stkdepth2!=stkdepth1){
			writeflnerr("Script %s changed S-Lang stack depth from %d to %d while initializing", name, stkdepth1, stkdepth2);
			if(stkdepth2>stkdepth1){
				writeflnerr("(Stack overflow, fixing stack)");
				SLdo_pop_n(stkdepth2-stkdepth1);
			}
			else{
				writeflnerr("(Stack underflow, very dangerous");
			}
		}
		Current_Script_Index=-1;
	}
	SLang_Name_Type *Get_Function(string name){
		return SLang_get_function(cast(const(char*))toStringz(nsname~"->"~name));
	}
}

T Script_GetSafeStructValue(T)(SLang_Struct_Type *strct, string valname, T defaultval){
	if(!SLang_push_struct_field(strct, toCString(valname))){
		T ret;
		static if(is(T==float)){
			if(!SLang_pop_float(&ret))return ret;
		}
		else
		static if(is(T==uint)){
			if(!SLang_pop_uint(&ret))return ret;
		}
		else
		static if(is(T==int)){
			if(!SLang_pop_int(&ret))return ret;
		}
	}
	SLang_set_error(0);
	return defaultval;
}

Script_t[] Loaded_Scripts;

void Init_Script(){
	//In case I might want to link S-Lang dynamically
	/*static if(__SLANG_LINK_DYNAMICALLY){
		version(Posix){
			import core.sys.posix.dlfcn;
			auto libhandle=dlopen("./libslang.so".toStringz(), RTLD_NOW );
			foreach(elementname; __traits(allMembers, slang)){
				static if(__traits(isStaticFunction, __traits(getMember, slang, elementname))){
					dlsym(libhandle, elementname.toStringz() );
					writeflnlog("%s", elementname);
				}
				else{
					writeflnlog("_%s", elementname);
				}
			}			
		}
		version(Windows){
			import std.windows;
			auto libhandle=LoadLibraryA("./libslang.dll".toStringz());	
			foreach(elementname; __traits(allMembers, slang)){
				static if(__traits(isStaticFunction, __traits(getMember, slang, elementname))){
					GetProcAddress(libhandle, elementname.toStringz() );
					writeflnlog("%s", elementname);
				}
				else{
					writeflnlog("_%s", elementname);
				}
			}
		}
	}*/
	version(DigitalMars){
		version(Windows){
			//Don't access, or segfault (because shitty OPTLINK)
		}
		else{
			SLang_Traceback=SL_TB_PARTIAL;
		}
	}
	else{
		SLang_Traceback=SL_TB_PARTIAL;
	}
	SLang_init_slang();
	SLang_init_slmath();
	SLang_init_array();
	foreach(funcname; SLStdLib_DisabledFuncs)
		SLadd_intrinsic_function(cast(const(char*))toStringz(funcname), &SLStdLib_DisabledFunc, SLANG_VOID_TYPE, 0);
	foreach(varname; SLStdLib_DisabledVars)
		SLadd_intrinsic_variable(cast(const(char*))toStringz(varname), &SLStdLib_DisabledVar, SLANG_UINT_TYPE, 1);
	ScrStdLib_Ns=SLns_create_namespace(toStringz("scrstd"));
	SLns_add_intrinsic_function(ScrStdLib_Ns, cast(const(char*))toStringz("rand"), &ScrStdLib_Rand, SLANG_UINT_TYPE, 0);
	SLns_add_intrinsic_function(ScrStdLib_Ns, cast(const(char*))toStringz("Send_Packet"), &ScrStdLib_SendPacket, SLANG_VOID_TYPE, 1, SLANG_BSTRING_TYPE);
	SLns_add_intrinsic_function(ScrStdLib_Ns, cast(const(char*))toStringz("Key_Pressed"), &ScrStdLib_KeyPressed, SLANG_UCHAR_TYPE, 0);
	SLns_add_intrinsic_function(ScrStdLib_Ns, cast(const(char*))toStringz("plog"), &ScrStdLib_PrintLog, SLANG_VOID_TYPE, 0);
	SLns_add_intrinsic_function(ScrStdLib_Ns, cast(const(char*))toStringz("Ping"), &Get_Ping, SLANG_UINT_TYPE, 0);
	SLns_add_intrinsic_function(ScrStdLib_Ns, cast(const(char*))toStringz("AssignBuiltin"), &ScrStdLib_AssignBuiltin, SLANG_VOID_TYPE, 0);
	SLns_add_intrinsic_function(ScrStdLib_Ns, cast(const(char*))toStringz("ClearBuiltin"), &ScrStdLib_ClearBuiltin, SLANG_VOID_TYPE, 0);
	SLns_add_intrinsic_variable(ScrStdLib_Ns, toStringz("MapXSize"), &MapXSize, DLangType_To_SLangType!(typeof(MapXSize))(), 1);
	SLns_add_intrinsic_variable(ScrStdLib_Ns, toStringz("MapYSize"), &MapYSize, DLangType_To_SLangType!(typeof(MapYSize))(), 1);
	SLns_add_intrinsic_variable(ScrStdLib_Ns, toStringz("MapZSize"), &MapZSize, DLangType_To_SLangType!(typeof(MapZSize))(), 1);
	SLadd_intrinsic_function(cast(const(char*))toStringz("Vector3_RotationAsDirection"), &ScrVecLib_RotationAsDirection, SLANG_VOID_TYPE, 1, SLANG_ARRAY_TYPE);
	SLadd_intrinsic_function(cast(const(char*))toStringz("Vector3_DirectionAsRotation"), &ScrVecLib_DirectionAsRotation, SLANG_VOID_TYPE, 1, SLANG_ARRAY_TYPE);
	ScriptLibraries=[ScriptLib_t("None", ""), ScriptLib_t("GUI", "scrgui"), ScriptLib_t("World", "scrworld")];
}

void Script_OnFrame(){
	foreach(ref scr; Loaded_Scripts){
		if(!scr.call_on_frame)
			continue;
		scr.Call_Func("On_Frame_Update", delta_time);
	}
}

void Script_OnMiniMapRender(){
	foreach(ref scr; Loaded_Scripts){
		if(!scr.call_on_minimap_render)
			continue;
		scr.Call_Func("On_Minimap_Render", delta_time);
	}
}

void Script_OnMouseClick(bool left, bool right){
	foreach(ref scr; Loaded_Scripts){
		if(!scr.enabled)
			continue;
		if(scr.Get_Function("On_Mouse_Click"))
			scr.Call_Func("On_Mouse_Click", left, right);
	}
}

//TODO: Create proper menu element management code
void ScrGuiLib_MenuElementCreate(){
	string[] fieldnames=["elementindex", "picindex", "xpos", "ypos", "zpos", "xsize", "ysize", "transparency", "color_mod"];
	char*[] c_fieldnames;
	foreach(ref field; fieldnames)
		c_fieldnames~=cast(char*)toStringz(field);
	SLang_Struct_Type *button=SLang_create_struct (cast(const(char**))c_fieldnames.ptr, cast(uint)fieldnames.length);
	int elem=-1;
	for(uint i=0; i<MenuElements.length; i++){
		if(!MenuElements[i].inactive() || MenuElements[i].reserved)
			continue;
		elem=i;
		break;
	}
	if(elem==-1){
		elem=cast(int)MenuElements.length;
		MenuElements.length++;
		MenuElements[elem].zpos=255;
	}
	MenuElements[elem].reserved=true;
	//Inivisible, but not inactive (Still need a good way to combine script/packet menu element modification stuff)
	MenuElements[elem].set(cast(ubyte)elem, cast(ubyte)0, cast(ubyte)0, 0.0, 0.0, 1.0f/float.infinity, 1.0f/float.infinity, 1);
	SLang_push_uchar(cast(ubyte)elem); SLang_push_uchar(0); SLang_push_float(0.0); SLang_push_float(0.0); SLang_push_uchar(0);
	SLang_push_float(10e-5); SLang_push_float(10e-5); SLang_push_uchar(1); SLang_push_uint(0x00ffffff);
	SLang_pop_struct_fields(button, cast(int)fieldnames.length);
	SLang_push_struct(button);
}

void ScrGuiLib_MenuElementUpdate(SLang_Struct_Type *slelement){
	string[] fieldnames=["elementindex", "picindex", "xpos", "ypos", "zpos", "xsize", "ysize", "transparency", "color_mod"];
	foreach(ref field; fieldnames)
		SLang_push_struct_field(slelement, cast(char*)toStringz(field));
	uint color_mod; ubyte elementindex, picindex; float xpos, ypos; ubyte zpos; float xsize, ysize; ubyte transparency;
	SLang_pop_uint(&color_mod); SLang_pop_uchar(&transparency); SLang_pop_float(&ysize); SLang_pop_float(&xsize); SLang_pop_uchar(&zpos);
	SLang_pop_float(&ypos); SLang_pop_float(&xpos); SLang_pop_uchar(&picindex); SLang_pop_uchar(&elementindex);
	MenuElements[elementindex].set(elementindex, picindex, zpos, xpos, ypos, xsize, ysize, transparency, color_mod);
	MenuElements[elementindex].reserved=true;
}

void ScrGuiLib_MenuElementDelete(SLang_Struct_Type *slelement){
	SLang_push_struct_field(slelement, cast(char*)toStringz("elementindex"));
	ubyte elementindex;
	SLang_pop_uchar(&elementindex);
	MenuElements[elementindex].picture_index=255;
	MenuElements[elementindex].reserved=false;
	if(slelement.destroy_method)
		SLexecute_function(slelement.destroy_method);
}

void ScrGuiLib_TextBoxCreate(){
	string[] fieldnames=["boxindex", "fontindex", "xpos", "ypos", "xsize", "ysize", "wrap_lines", "move_lines_down",
	"move_lines_up", "lines", "colors"];
	char*[] c_fieldnames;
	foreach(ref field; fieldnames)
		c_fieldnames~=cast(char*)toStringz(field);
	SLang_Struct_Type *textbox=SLang_create_struct (cast(const(char**))c_fieldnames.ptr, cast(uint)fieldnames.length);
	int box=-1;
	for(uint i=0; i<TextBoxes.length; i++){
		if(!TextBoxes[i].inactive())
			continue;
		box=i;
		break;
	}
	if(box==-1){
		box=cast(int)TextBoxes.length;
		TextBoxes.length++;
	}
	TextBoxes[box].set(0, 0.0, 0.0, 1.0f/float.infinity, 1.0f/float.infinity, 0);
	SLang_push_uchar(cast(ubyte)box); SLang_push_uchar(cast(ubyte)0); SLang_push_float(0.0); SLang_push_float(0.0);
	SLang_push_float(1.0f/float.infinity); SLang_push_float(1.0f/float.infinity); 
	SLang_push_uchar(cast(ubyte)0); SLang_push_uchar(cast(ubyte)0); SLang_push_uchar(cast(ubyte)0);
	SLindex_Type dim=0;
	SLang_push_array(SLang_create_array(SLANG_STRING_TYPE, 0, null, &dim, 1), 1);
	SLang_push_array(SLang_create_array(SLANG_UINT_TYPE, 0, null, &dim, 1), 1);
	SLang_pop_struct_fields(textbox, cast(int)fieldnames.length);
	SLang_push_struct(textbox);
}

void ScrGuiLib_TextBoxUpdate(SLang_Struct_Type *slelement){
	string[] fieldnames=["boxindex", "fontindex", "xpos", "ypos", "xsize", "ysize", "wrap_lines", "move_lines_down",
	"move_lines_up", "lines", "colors"];
	foreach(ref field; fieldnames)
		SLang_push_struct_field(slelement, cast(char*)toStringz(field));
	ubyte boxindex, fontindex; float xpos, ypos, xsize, ysize, xsizeratio, ysizeratio; ubyte wrap_lines, move_lines_down, move_lines_up;
	SLang_Array_Type* lines, colors;
	SLang_pop_array_of_type(&colors, SLANG_UINT_TYPE); SLang_pop_array_of_type(&lines, SLANG_STRING_TYPE);
	SLang_pop_uchar(&move_lines_up); SLang_pop_uchar(&move_lines_up); SLang_pop_uchar(&wrap_lines); 
	SLang_pop_float(&ysize); SLang_pop_float(&xsize); SLang_pop_float(&ypos);
	SLang_pop_float(&xpos); SLang_pop_uchar(&fontindex); SLang_pop_uchar(&boxindex);
	TextBoxes[boxindex].set(fontindex, xpos, ypos, xsize, ysize,
	to!ubyte((wrap_lines*TEXTBOX_FLAG_WRAP) | (move_lines_up*TEXTBOX_FLAG_MOVELINESDOWN) | (move_lines_down*TEXTBOX_FLAG_MOVELINESUP)));
	TextBoxes[boxindex].lines.length=lines.dims[0];
	for(SLindex_Type i=0; i<TextBoxes[boxindex].lines.length; i++){
		SLstr_Type *line;
		SLang_get_array_element(lines, &i, &line);
		TextBoxes[boxindex].lines[i]=cast(string)fromStringz(line);
	}
	TextBoxes[boxindex].colors.length=colors.dims[0];
	for(SLindex_Type i=0; i<TextBoxes[boxindex].colors.length; i++){
		uint color;
		SLang_get_array_element(colors, &i, &color);
		TextBoxes[boxindex].colors[i]=color;
	}
}

void ScrGuiLib_TextBoxDelete(SLang_Struct_Type *slelement){
	SLang_push_struct_field(slelement, cast(char*)toStringz("boxindex"));
	ubyte boxindex;
	SLang_pop_uchar(&boxindex);
	TextBoxes[boxindex].font_index=255;
	if(slelement.destroy_method)
		SLexecute_function(slelement.destroy_method);
}

ubyte ScrGuiLib_Object_Hovered(SLang_Struct_Type *slelement){
	string[] fieldnames=["xpos", "ypos", "xsize", "ysize"];
	foreach(ref field; fieldnames)
		SLang_push_struct_field(slelement, cast(char*)toStringz(field));
	float xpos, ypos, xsize, ysize;
	SLang_pop_float(&ysize); SLang_pop_float(&xsize); SLang_pop_float(&ypos); SLang_pop_float(&xpos);
	int ixpos=to!int(xpos*ScreenXSize), iypos=to!int(ypos*ScreenYSize), ixsize=to!int(xsize*ScreenXSize), iysize=to!int(ysize*ScreenYSize);
	return MouseXPos>=ixpos && MouseXPos<ixpos+ixsize && MouseYPos>=iypos && MouseYPos<iypos+iysize;
}

double ScrGuiLib_MouseX(){return MouseXPos;}
double ScrGuiLib_MouseY(){return MouseYPos;}
ubyte ScrGuiLib_MouseLeftClicked(){return MouseLeftClick;}
ubyte ScrGuiLib_MouseRightClicked(){return MouseRightClick;}
ubyte ScrGuiLib_MouseLeftChanged(){return MouseLeftChanged;}
ubyte ScrGuiLib_MouseRightChanged(){return MouseRightChanged;}
void ScrGuiLib_MenuMode_Set(){ubyte mode; SLang_pop_uchar(&mode); Set_Menu_Mode(cast(bool)mode);}
ubyte ScrGuiLib_MenuMode_Get(){return Menu_Mode;}

void ScrGuiLib_StandardFont_Set(ubyte font){
	Set_ModFile_Font(font);
}
ubyte ScrGuiLib_StandardFont_Get(){
	auto ind=Mod_Pictures.countUntil(font_texture);
	if(ind<0)
		return font_index;
	return cast(ubyte)ind;
}

uint ScrGuiLib_PictureColorGet(){
	ubyte picindex; float xcoord, ycoord;
	SLang_pop_float(&ycoord); SLang_pop_float(&xcoord); SLang_pop_uchar(&picindex);
	SDL_Surface *pic=Mod_Picture_Surfaces[picindex];
	uint xp=to!uint(xcoord*(pic.w-1)), yp=to!uint(ycoord*(pic.h-1));
	uint col=*(cast(uint*)(&((pic.pixels))[(xp<<2)+yp*pic.pitch]));
	return col;
}

ubyte ScrGuiLib_MiniMap_Shown(){
	return Render_MiniMap;
}

void ScrGuiLib_MenuElementRender(SLang_Struct_Type *slelement){
	ScrGuiLib_MenuElementUpdate(slelement);
	SLang_push_struct_field(slelement, cast(char*)toStringz("elementindex"));
	ubyte elementindex;
	SLang_pop_uchar(&elementindex);
	MenuElement_Draw(&MenuElements[elementindex]);
}

uint ScrWorldLib_EnvEffectSlotAlloc(){
	EnvironmentEffectSlots.length++;
	EnvironmentEffectSlots[$-1].fog[3]=0;
	EnvironmentEffectSlots[$-1].visibility=1.0;
	return cast(uint)(EnvironmentEffectSlots.length-1);
}

void ScrWorldLib_EnvEffectSlotSet(SLang_Struct_Type *effect_slot){
	SLang_push_struct_field(effect_slot, toCString("index"));
	uint slot_index;
	SLang_pop_uint(&slot_index);
	EnvEffectSlot_t *slot=&EnvironmentEffectSlots[slot_index];
	SLang_push_struct_field(effect_slot, toCString("fog"));
	SLang_Array_Type *fog_arr;
	SLang_pop_array(&fog_arr, 0);
	for(SLindex_Type fog_ind=0; fog_ind<4; fog_ind++)
		SLang_get_array_element(fog_arr, &fog_ind, &slot.fog[fog_ind]);
	slot.shake=Script_GetSafeStructValue!(float)(effect_slot, "shake", 0.0);
	slot.blur=Script_GetSafeStructValue!(float)(effect_slot, "blur", 0.0);
	slot.visibility=Script_GetSafeStructValue!(float)(effect_slot, "visibility", 1.0);
	slot.brightness=Script_GetSafeStructValue!(float)(effect_slot, "brightness", 1.0);
}

uint ScrWorldLib_FogColorGet(){return Current_Fog_Color;}
void ScrWorldLib_FogColorSet(){SLang_pop_uint(&Base_Fog_Color);}
uint ScrWorldLib_VisibilityRangeGet(){return Current_Visibility_Range;}
void ScrWorldLib_VisibilityRangeSet(){SLang_pop_uint(&Base_Visibility_Range);}
void ScrWorldLib_VoxelDel(){
	uint x, y, z;
	SLang_pop_uint(&x); SLang_pop_uint(&y); SLang_pop_uint(&z);
	Break_Block!(false, false)(x, y, z);
}

void ScrVecLib_RotationAsDirection(SLang_Array_Type *vec){
	float x, y, z;
	SLindex_Type ind=0;
	SLang_get_array_element(vec, &ind, &x); ind++; SLang_get_array_element(vec, &ind, &y); ind++; SLang_get_array_element(vec, &ind, &z);
	Push_DLang_Object(Vector3_t(x, y, z).RotationAsDirection());
}

void ScrVecLib_DirectionAsRotation(SLang_Array_Type *vec){
	float x, y, z;
	SLindex_Type ind=0;
	SLang_get_array_element(vec, &ind, &x); ind++; SLang_get_array_element(vec, &ind, &y); ind++; SLang_get_array_element(vec, &ind, &z);
	Push_DLang_Object(Vector3_t(x, y, z).DirectionAsRotation());
}

ubyte ScrStdLib_KeyPressed(){
	ubyte key;
	SLang_pop_uchar(&key);
	if(TypingChat)
		return 0;
	return KeyState[key]!=0;
}

uint ScrStdLib_Rand(){return uniform!uint();}
void ScrStdLib_SendPacket(SLang_BString_Type *bstr){
	if(Current_Script_Index<0){
		writefln("[SCRIPT]Can't send data to server from unindexed script (%d)", Current_Script_Index);
		return;
	}
	CustomScriptPacketLayout packet;
	packet.scr_index=to!ushort(Current_Script_Index);
	ubyte *content; SLstrlen_Type len;
	content=SLbstring_get_pointer(bstr, &len);
	packet.data=to!string((cast(char*)content)[0..len].dup());
	Send_Packet(CustomScriptPacketID, packet);
}
void ScrStdLib_PrintLog(){
	char *content;
	if(!SLpop_string(&content)){
		writefln("[SCRIPT]%s", fromStringz(content));
		SLfree(content);
	}
}
void ScrStdLib_AssignBuiltin(){
	AssignBuiltinPacketLayout packet;
	if(SLang_pop_uchar(&packet.index)) return;
	if(SLang_pop_uchar(&packet.target)) return;
	if(SLang_pop_uchar(&packet.type)) return;
	ReceivedPacket_t recv_packet;
	recv_packet.ConnectionID=0;
	recv_packet.data=AssignBuiltinPacketID~PackStructToPacket(packet);
	On_Packet_Receive(recv_packet);
}
void ScrStdLib_ClearBuiltin(){
	AssignBuiltinPacketLayout packet;
	if(SLang_pop_uchar(&packet.target)) return;
	if(SLang_pop_uchar(&packet.type)) return;
	packet.index=255;
	ReceivedPacket_t recv_packet;
	recv_packet.ConnectionID=0;
	recv_packet.data=AssignBuiltinPacketID~PackStructToPacket(packet);
	On_Packet_Receive(recv_packet);
}

}
