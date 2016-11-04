extern(C){
alias SLtype=uint;
immutable SLtype SLANG_UNDEFINED_TYPE	=0x00;   /* MUST be 0 */
immutable SLtype SLANG_VOID_TYPE		=0x01;   /* also matches ANY type */
immutable SLtype SLANG_NULL_TYPE		=0x02;
immutable SLtype SLANG_ANY_TYPE		=0x03;
immutable SLtype SLANG_DATATYPE_TYPE	=0x04;
/* SLANG_REF_TYPE refers to an object on the stack that is a pointer =reference;
 * to some other object.
 */
immutable SLtype SLANG_REF_TYPE		=0x05;
immutable SLtype SLANG_STRING_TYPE	=0x06;
immutable SLtype SLANG_BSTRING_TYPE	=0x07;
immutable SLtype SLANG_FILE_PTR_TYPE	=0x08;
immutable SLtype SLANG_FILE_FD_TYPE	=0x09;
immutable SLtype SLANG_MD5_TYPE		=0x0A;
immutable SLtype SLANG_INTP_TYPE		=0x0F;

/* Integer types */
/* The integer and floating point types are arranged in order of arithmetic
 * precedence.
 */
immutable SLtype SLANG_CHAR_TYPE		=0x10;
immutable SLtype SLANG_UCHAR_TYPE	=0x11;
immutable SLtype SLANG_SHORT_TYPE	=0x12;
immutable SLtype SLANG_USHORT_TYPE	=0x13;
immutable SLtype SLANG_INT_TYPE =0x14;
immutable SLtype SLANG_UINT_TYPE		=0x15;
immutable SLtype SLANG_LONG_TYPE		=0x16;
immutable SLtype SLANG_ULONG_TYPE	=0x17;
immutable SLtype SLANG_LLONG_TYPE	=0x18;
immutable SLtype SLANG_ULLONG_TYPE	=0x19;
/* floating point types */
immutable SLtype SLANG_FLOAT_TYPE	=0x1A;
immutable SLtype SLANG_DOUBLE_TYPE	=0x1B;
immutable SLtype SLANG_LDOUBLE_TYPE	=0x1C;

immutable SLtype SLANG_COMPLEX_TYPE	=0x20;

/* An object of SLANG_INTP_TYPE should never really occur on the stack.  Rather,
 * the integer to which it refers will be there instead.  It is defined here
 * because it is a valid type for MAKE_VARIABLE.
 */

/* Container types */
immutable SLtype SLANG_ISTRUCT_TYPE 	=0x2A;
immutable SLtype SLANG_STRUCT_TYPE	=0x2B;
immutable SLtype SLANG_ASSOC_TYPE	=0x2C;
immutable SLtype SLANG_ARRAY_TYPE	=0x2D;
immutable SLtype SLANG_LIST_TYPE		=0x2E;

immutable SLtype SLANG_MIN_UNUSED_TYPE	=0x30;


immutable char SLANG_INTRINSIC=0x05;

struct _pSLang_Name_Type
{
	const char *name;
	_pSLang_Name_Type *next;
	ubyte name_type;
}

alias SLang_Name_Type=_pSLang_Name_Type;


struct _pSLang_NameSpace_Type
{
   _pSLang_NameSpace_Type *next;
   const char *name;	       /* this is the load_type name */
   char *namespace_name;/* this name is assigned by implements */
   const char *private_name;
   uint table_size;
   SLang_Name_Type **table;
}
alias SLang_NameSpace_Type=_pSLang_NameSpace_Type;

struct _pSLstruct_Field_Type
{
   const char *name;			       /* slstring */
   SLang_Object_Type obj;
}


struct _pSLang_Struct_Type
{
   _pSLstruct_Field_Type *fields;
   uint nfields;	       /* number used */
   uint num_refs;
   /* user-defined methods */
   SLang_Name_Type *destroy_method;
}

alias SLang_Struct_Type=_pSLang_Struct_Type;

//Better leave it at this (SLang_Class_Type is a very complex struct)
alias SLang_Class_Type=void*;

immutable SLARRAY_MAX_DIMS=7;
struct _pSLang_Array_Type
{
   SLtype data_type;
   uint sizeof_type;
   void* data;
   SLuindex_Type num_elements;
   uint num_dims;
   SLindex_Type dims [SLARRAY_MAX_DIMS];
   void **index_fun(_pSLang_Array_Type *, SLindex_Type *);
   /* This function is designed to allow a type to store an array in
    * any manner it chooses.  This function returns the address of the data
    * value at the specified index location.
    */
   uint flags;
   SLang_Class_Type *cl;
   uint num_refs;
   void *free_fun (_pSLang_Array_Type *);
   void *client_data;
}

alias SLang_Array_Type=_pSLang_Array_Type;

int SLang_pop_array_of_type (SLang_Array_Type **atp, SLtype type);
int SLang_pop_array (SLang_Array_Type **atp, int convert_scalar);
int SLang_push_array (SLang_Array_Type *at, int do_free);
void SLang_free_array (SLang_Array_Type *at);
SLang_Array_Type *SLang_create_array (SLtype, int, void *, SLindex_Type *, uint);
SLang_Array_Type *SLang_create_array1 (SLtype, int, void *, SLindex_Type *, uint, int);
SLang_Array_Type *SLang_duplicate_array (SLang_Array_Type *);
int SLang_get_array_element (SLang_Array_Type *, SLindex_Type *, void *);
int SLang_set_array_element (SLang_Array_Type *, SLindex_Type *, void *);

union _pSL_Object_Union_Type
{
   //long long_val;
   //ulong ulong_val;
   void * ptr_val;
   char *s_val;
   int int_val;
   uint uint_val;
   //SLang_MMT_Type *ref;
   SLang_Name_Type *n_val;
   _pSLang_Struct_Type *struct_val;
   //struct _pSLang_Array_Type *array_val;
   short short_val;
   ushort ushort_val;
   char char_val;
   ubyte uchar_val;
   //SLindex_Type index_val;
}


struct _pSLang_Object_Type
{
   SLtype o_data_type;	       /* SLANG_INT_TYPE, ... */
   _pSL_Object_Union_Type v;
}

alias SLang_Object_Type=_pSLang_Object_Type;

struct SLang_Load_Type
{
   int type;

   void *client_data;
   /* Pointer to data that client needs for loading */

   int auto_declare_globals;
   /* if non-zero, undefined global variables are declared as static */

   char* function(SLang_Load_Type *)read;
   /* function to call to read next line from obj. */

   uint line_num;
   /* Number of lines read, used for error reporting */

   int parse_level;
   /* 0 if at top level of parsing */

   const char *name;
   /* Name of this object, e.g., filename.  This name should be unique because
    * it alone determines the name space for static objects associated with
    * the compilable unit.
    */

   const char *namespace_name;
   uint reserved[3];
   /* For future expansion */
}

int SLang_init_slang();
int SLang_init_slmath();
int SLang_init_slfile();
int SLang_load_string(char *);
int SLns_load_string (const char *, const char *);

int SLexecute_function (SLang_Name_Type *);
int SLang_execute_function(const char *);
SLang_Name_Type *SLang_get_function (const char *);

struct String_Client_Data_Type
{
   const char *string;
   const char *ptr;
}

SLang_Load_Type *SLallocate_load_type (const char *);
SLang_Load_Type *SLns_allocate_load_type (const char *, const char *);
int SLang_load_object (SLang_Load_Type *);

SLang_Struct_Type *SLang_create_struct (const char **, uint);
int SLang_push_struct (SLang_Struct_Type *);
int SLang_push_struct_field (SLang_Struct_Type *, char *);
int SLang_pop_struct_fields (SLang_Struct_Type *, int);
int SLang_pop_struct (SLang_Struct_Type **);

int SLang_push_string(const char *);
int SLpop_string (char **);

int SLang_push_char (byte);
int SLang_push_uchar (ubyte);
int SLang_pop_char (byte *);
int SLang_pop_uchar (ubyte *);

int SLang_push_int(int);
int SLang_push_uint(uint);
int SLang_pop_int(int *);
int SLang_pop_uint(uint *);

int SLang_pop_short(short *);
int SLang_pop_ushort(ushort *);
int SLang_push_short(short);
int SLang_push_ushort(ushort);

int SLang_pop_float(float *);
int SLang_push_float(float);
int SLang_pop_double(double *);
int SLang_push_double(double);

int SLstack_depth();
int SLdo_pop();
int SLdo_pop_n(uint);
int SLang_peek_at_stack();

int SLreverse_stack (int);
int SLroll_stack (int);

alias SLang_Any_Type=_pSLang_Object_Type;
int SLang_pop_anytype (SLang_Any_Type **);
int SLang_push_anytype (SLang_Any_Type *);
void SLang_free_anytype (SLang_Any_Type *);

alias SLstrlen_Type=uint;

struct _pSLang_BString_Type
{
   uint num_refs;
   uint len;
   uint malloced_len;
   int ptr_type;
   union
     {
	ubyte bytes[1];
	ubyte *ptr;
     }
}

alias SLang_BString_Type=_pSLang_BString_Type;

SLang_BString_Type *SLbstring_create (ubyte *, SLstrlen_Type);
int SLang_push_bstring (SLang_BString_Type *);
ubyte *SLbstring_get_pointer (SLang_BString_Type *, SLstrlen_Type *);

SLang_NameSpace_Type *SLns_create_namespace (const char *);
void SLns_delete_namespace (SLang_NameSpace_Type *);
int SLns_add_intrinsic_function (SLang_NameSpace_Type *, const char *, void*, SLtype, uint, ...);


immutable auto SLANG_MAX_INTRIN_ARGS=7;
struct SLang_Intrin_Fun_Type
{
   const char *name;
   _pSLang_Name_Type *next;      /* this is for the hash table */
   char name_type;

   void * i_fun;		       /* address of object */
   SLtype arg_types [SLANG_MAX_INTRIN_ARGS];
   ubyte num_args;
   SLtype return_type;
}

SLang_Intrin_Fun_Type MAKE_INTRINSIC_N(char *name, void *func, SLtype typeout, ubyte numin, SLtype a1, SLtype a2, SLtype a3, SLtype a4, SLtype a5, 
SLtype a6, SLtype a7){
	return SLang_Intrin_Fun_Type(name, null, SLANG_INTRINSIC, func, [a1,a2,a3,a4,a5,a6,a7], numin, typeout);
}

SLang_Intrin_Fun_Type MAKE_INTRINSIC_0(char *name, void *func, SLtype typeout){
	return MAKE_INTRINSIC_N(name, func, typeout, cast(ubyte)0, 0u, 0u, 0u, 0u, 0u, 0u, 0u);
}

SLang_Intrin_Fun_Type MAKE_INTRINSIC_1(char *name, void *func, SLtype typeout, SLtype a1){
	return MAKE_INTRINSIC_N(name, func, typeout, cast(ubyte)1, a1, 0u, 0u, 0u, 0u, 0u, 0u);
}

SLang_Intrin_Fun_Type MAKE_INTRINSIC_2(char *name, void *func, SLtype typeout, SLtype a1, SLtype a2){
	return MAKE_INTRINSIC_N(name, func, typeout, cast(ubyte)2, a1, a2, 0u, 0u, 0u, 0u, 0u);
}

SLang_Intrin_Fun_Type MAKE_INTRINSIC_3(char *name, void *func, SLtype typeout, SLtype a1, SLtype a2, SLtype a3){
	return MAKE_INTRINSIC_N(name, func, typeout, cast(ubyte)3, a1, a2, a3, 0u, 0u, 0u, 0u);
}

struct SLang_Intrin_Var_Type
{
   const char *name;
   SLang_Name_Type *next;
   char name_type;

   void *addr;
   SLtype type;
}


auto SLANG_END_INTRIN_FUN_TABLE(){return MAKE_INTRINSIC_0(null,null,0);}

int SLns_add_intrin_fun_table (SLang_NameSpace_Type *, SLang_Intrin_Fun_Type *, const char *);
int SLns_add_intrinsic_variable (SLang_NameSpace_Type *, const char *, void*, SLtype, int);
int SLadd_intrinsic_variable (const char *, void*, SLtype, int);
int SLadd_intrinsic_function (const char *, void*, SLtype, uint,...);


int SLadd_intrin_fun_table (SLang_Intrin_Fun_Type *,  const char *);
int SLadd_intrin_var_table (SLang_Intrin_Var_Type *,  const char *);

alias SLindex_Type=int;
alias SLuindex_Type=uint;

struct _Chunk_Type
{
   _Chunk_Type *next;
   _Chunk_Type *prev;
   SLindex_Type num_elements;
   SLindex_Type chunk_size;
   SLang_Object_Type *elements;	       /* chunk_size of em */
}

alias Chunk_Type=_Chunk_Type;

immutable DEFAULT_CHUNK_SIZE=128;

struct _pSLang_List_Type
{
   SLindex_Type length;
   SLuindex_Type default_chunk_size;
   Chunk_Type *first;
   Chunk_Type *last;

   Chunk_Type *recent;		       /* most recent chunk accessed */
   SLindex_Type recent_num;	       /* num elements before the recent chunk */
   int ref_count;
}


alias SLang_List_Type=_pSLang_List_Type;
SLang_List_Type *SLang_create_list (int);
int SLang_list_append (SLang_List_Type *, int);
int SLang_list_insert (SLang_List_Type *, int);
int SLang_push_list (SLang_List_Type *, int free_list);
int SLang_pop_list (SLang_List_Type **);
void SLang_free_list (SLang_List_Type *);

alias SLstr_Type=char;
SLstr_Type *SLang_create_slstring (const char *);

extern __gshared int SLang_Traceback;
immutable SL_TB_NONE=0x0;
immutable SL_TB_FULL=0x1;    /* full traceback */
immutable SL_TB_OMIT_LOCALS=0x2;    /* full, but omit local vars */
immutable SL_TB_PARTIAL=0x4;    /* show just on line of traceback */

extern __gshared int SLang_Num_Function_Args;

void SLfree(void *);	       /* This function handles NULL */
}
