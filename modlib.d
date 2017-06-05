import sdl2;
import std.stdio;
import std.file;
import std.path;
import std.array;
import std.string;
import std.algorithm;
import std.conv;
import gfx;
import snd;
import misc;
import script;
import renderer;
import vector;
version(LDC){
	import ldc_stdlib;
}
version(GNU){
	import gdc_stdlib;
}

int ProtocolBuiltin_ServerMessageScript=-1;

Model_t *Model_FromKV6(ubyte[] data, string filename){
	struct __kv6_header_t{
		ubyte[4] magic_bytes;
		int xsize, zsize, ysize;
		float xpivot, zpivot, ypivot;
		int voxelcount;
	}
	__kv6_header_t *header=cast(__kv6_header_t*)data.ptr;
	if(header.magic_bytes!="Kvxl"){
		writeflnerr("Model file %s is not a valid KV6 file (wrong header)", filename);
		return null;
	}
	Model_t *model=new Model_t;
	model.xsize=header.xsize; model.ysize=header.ysize; model.zsize=header.zsize;
	if(model.xsize<0 || model.ysize<0 || model.zsize<0){
		writeflnerr("Model file %s has invalid size (%d|%d|%d)", filename, model.xsize, model.ysize, model.zsize);
		return null;
	}
	model.xpivot=header.xpivot; model.ypivot=header.ypivot; model.zpivot=header.zpivot;
	int voxelcount=header.voxelcount;
	if(voxelcount<0){
		writeflnerr("Model file %s has invalid voxel count (%d)", filename, voxelcount);
		return null;
	}
	model.voxels=new ModelVoxel_t[](voxelcount);
	size_t voxel_end_ind=__kv6_header_t.sizeof+voxelcount*ModelVoxel_t.sizeof;
	model.voxels[0..$]=cast(ModelVoxel_t[])data[__kv6_header_t.sizeof..voxel_end_ind];
	auto xlength=new uint[](model.xsize);
	size_t xlength_end_ind=voxel_end_ind+model.xsize*uint.sizeof;
	xlength[0..$]=cast(uint[])data[voxel_end_ind..xlength_end_ind];
	auto ylength=new ushort[][](model.xsize, model.zsize);
	size_t ylength_end_ind=xlength_end_ind+model.xsize*model.zsize*ushort.sizeof;
	for(uint z=0; z<model.zsize; z++)
		for(uint x=0; x<model.xsize; x++)
			ylength[x][z]=(cast(ushort[])data[xlength_end_ind..$])[z+model.zsize*x];
	if(data.length>=ylength_end_ind){
		if(data[ylength_end_ind..ylength_end_ind+4]=="SPal"){
			writeflnlog("Note: File %s contains a useless suggested palette block (SLAB6)", filename);
		}
		else{
			writeflnlog("Warning: File %s contains invalid data \"%s\" after its ending (corrupted file?)", filename, data[ylength_end_ind..$]);
			writeflnlog("KV6 size: (%d|%d|%d), pivot: (%f|%f|%f), amount of voxels: %d", model.xsize, model.ysize, model.zsize, 
			model.xpivot, model.ypivot, model.zpivot, voxelcount);
		}
	}
	model.offsets.length=model.xsize*model.zsize;
	model.column_lengths.length=model.offsets.length;
	typeof(model.offsets[0]) voxel_xindex=0;
	for(uint x=0; x<model.xsize; x++){
		auto voxel_zindex=voxel_xindex;
		for(uint z=0; z<model.zsize; z++){
			model.offsets[x+z*model.xsize]=voxel_zindex;
			model.column_lengths[x+z*model.xsize]=ylength[x][z];
			voxel_zindex+=ylength[x][z];
		}
		voxel_xindex+=xlength[x];
	}
	return model;
}

Model_t *Model_FromVoxelArray(ModelVoxel_t[][] _voxels, uint xsize, uint zsize){
	ModelVoxel_t[][] voxels=_voxels.dup;
	for(uint zctr=0; zctr<zsize; zctr++){
		bool empty_rows=true;
		for(uint x=0; x<xsize; x++){
			if(voxels[x].length){
				empty_rows=false;
				break;
			}
		}
		if(!empty_rows)
			break;
		for(uint z=0; z<zsize-1; z++){
			for(uint x=0; x<xsize; x++){
				voxels[x+z*xsize]=voxels[x+(z+1)*xsize];
			}
		}
		for(uint x=0; x<xsize; x++)
			voxels[x+(zsize-1)*xsize].length=0;
	}
	for(uint xctr=0; xctr<xsize; xctr++){
		bool empty_rows=true;
		for(uint z=0; z<zsize; z++){
			if(voxels[z*xsize].length){
				empty_rows=false;
				break;
			}
		}
		if(!empty_rows)
			break;
		for(uint z=0; z<zsize; z++){
			for(uint x=0; x<xsize-1; x++){
				voxels[x+z*xsize]=voxels[x+1+z*xsize];
			}
		}
		for(uint z=0; z<zsize; z++)
			voxels[xsize-1+z*xsize].length=0;
	}
	uint origzsize=zsize;
	for(uint zctr=0; zctr<origzsize; zctr++){
		bool empty_rows=true;
		for(uint x=0; x<xsize; x++){
			if(voxels[x+(zsize-1)*xsize].length){
				empty_rows=false;
				break;
			}
		}
		if(!empty_rows)
			break;
		zsize--;
		ModelVoxel_t[][] nvoxels;
		nvoxels.length=xsize*zsize;
		for(uint x=0; x<xsize; x++){
			for(uint z=0; z<zsize; z++){
				nvoxels[x+z*xsize]=voxels[x+z*xsize];
			}
		}
		voxels=nvoxels;
	}
	uint origxsize=xsize;
	for(uint xctr=0; xctr<origxsize; xctr++){
		bool empty_rows=true;
		for(uint z=0; z<zsize; z++){
			if(voxels[xsize-1+z*xsize].length){
				empty_rows=false;
				break;
			}
		}
		if(!empty_rows)
			break;
		xsize--;
		ModelVoxel_t[][] nvoxels;
		nvoxels.length=xsize*zsize;
		for(uint x=0; x<xsize; x++){
			for(uint z=0; z<zsize; z++){
				nvoxels[x+z*xsize]=voxels[x+z*(xsize+1)];
			}
		}
		voxels=nvoxels;
	}
	Model_t *model=new Model_t;
	uint voxelcount=0, min_y=uint.max, max_y=uint.min;
	foreach(ref voxcol; voxels){
		voxelcount+=voxcol.length;
		voxcol.sort!("a.ypos<b.ypos");
		if(voxcol.length){
			min_y=min(voxcol[0].ypos, min_y); max_y=max(voxcol[$-1].ypos, max_y);
		}
	}
	model.voxels.length=voxelcount;
	model.xsize=xsize; model.ysize=max_y-min_y+1; model.zsize=zsize;
	model.pivot=model.size*.5;
	model.lower_mip_levels=null;
	model.offsets.length=model.column_lengths.length=xsize*zsize;
	uint offset=0;
	for(uint x=0; x<xsize; x++){
		for(uint z=0; z<zsize; z++){
			ushort col_len=to!ushort(voxels[x+z*xsize].length);
			model.column_lengths[x+z*xsize]=col_len;
			model.voxels[offset..offset+col_len]=voxels[x+z*xsize];
			model.offsets[x+z*xsize]=offset;
			offset+=col_len;
		}
	}
	return model;
}

immutable bool[string] Freeze_Mod_Directories;

static this(){
	Freeze_Mod_Directories=[
		"Default":true,
	];
}

enum ModDataTypes{
	Picture=0, Model=1, Script=2, Sound=3
}

struct ModFile_t{
	ubyte type;
	ushort index;
	string name;
	uint size;
	ubyte[] data;
	uint hash;
	bool receiving_data;
	bool no_file;
	this(string initname, ushort initindex, ubyte inittype){
		name=initname; index=initindex; type=inittype;
		size=0; hash=0; receiving_data=false; no_file=false;
	}
	void Loading_Finished(){
		receiving_data=false;
		string current_path=getcwd();
		string fname="./Ressources/"~name;
		string[] nmdirs=cast(string[])pathSplitter(name).array;
		string[] dirs=["./Ressources/"]~nmdirs;
		dirs=dirs[0..$-1];
		foreach(ref dir; dirs){
			if(!exists(dir))
				mkdir(dir);
			chdir(dir);
		}
		chdir(current_path);
		bool preserve_file=false;
		if(dirs[1] in Freeze_Mod_Directories)
			if(Freeze_Mod_Directories[dirs[1]])
				preserve_file=true;
		if(!preserve_file || !no_file){
			File f=File(fname, "wb+");
			f.rawWrite(data);
			f.close();
		}
		switch(type){
			//On Linux, I probably could have used virtual files in RAM instead of physically re-loading them :d
			case ModDataTypes.Picture:{
				SDL_Surface *fsrfc;
				string error;
				switch(fname[$-4..$]){
					case ".bmp":{
						fsrfc=SDL_LoadBMP(toStringz(fname));
						if(!fsrfc)
							error=cast(string)fromStringz(SDL_GetError());
						break;
					}
					case ".png":{
						fsrfc=IMG_Load(toStringz(fname));
						if(!fsrfc)
							error=cast(string)fromStringz(IMG_GetError());
						break;
					}
					default:{
						fsrfc=null;
						error="Unknown image file format"~fname[$-4..$];
						break;
					}
				}
				if(!fsrfc){writeflnerr("Couldn't load %s: %s", fname, error); break;}
				SDL_SetColorKey(fsrfc, SDL_TRUE, SDL_MapRGB(fsrfc.format, 255, 0, 255));
				SDL_Surface *srfc=SDL_ConvertSurfaceFormat(fsrfc, SDL_PIXELFORMAT_ARGB8888, 0);
				RendererTexture_t tex=Renderer_TextureFromSurface(srfc);
				if(Mod_Pictures.length<=index){
					Mod_Pictures.length=index+1;
					Mod_Picture_Surfaces.length=index+1;
					Mod_Picture_Sizes.length=index+1;
				}
				Mod_Pictures[index]=tex;
				Mod_Picture_Surfaces[index]=srfc;
				Mod_Picture_Sizes[index]=[srfc.w, srfc.h];
				SDL_FreeSurface(fsrfc);
				break;
			}
			case ModDataTypes.Model:{
				Model_t *model=Model_FromKV6(data, fname);
				if(!model){
					writeflnerr("Couldn't load %s", fname);
					break;
				}
				if(Mod_Models.length<=index)
					Mod_Models.length=index+1;
				Mod_Models[index]=model;
				break;
			}
			case ModDataTypes.Script:{
				try{
					string script=std.file.readText(fname);
					if(Loaded_Scripts.length<=index){
						Loaded_Scripts.length=index+1;
					}
					else{
						if(Loaded_Scripts[index].initialized){
							Loaded_Scripts[index].Uninit();
						}
					}
					Loaded_Scripts[index]=Script_t(index, fname, script);
				}
				catch(FileException){
					writeflnerr("Couldn't load %s", fname);
				}
				break;
			}
			case ModDataTypes.Sound:{
				if(Mod_Sounds.length<=index)
					Mod_Sounds.length=index+1;
				Mod_Sounds[index]=Sound_DecodeOgg(data);
				break;
			}
			default:{writeflnerr("Server sent mod of unknown data type %s", type); break;}
		}
		data=[];
	}
	bool LoadFromFile(){
		string fname="./Ressources/"~name;
		bool loaded_file=false;
		if(exists(fname)){
			if(isFile(fname) && !isDir(fname)){
				File f=File(fname);
				long lfsize=f.size();
				if(lfsize<int.max){
					data.length=cast(uint)lfsize;
					size=cast(uint)lfsize;
					f.rawRead(data);
					static if(1){
						import std.digest.crc;
						CRC32 context=makeDigest!CRC32();
						context.put(data);
						ubyte[4] hashbuf=context.finish();
						//RIP crc32Of() (used to work, great random number generator now)
						//ubyte[4] hashbuf=crc32Of(data);
						hash=*(cast(uint*)hashbuf.ptr);
					}
					else{
						hash=0;
					}
					Loading_Finished();
					loaded_file=true;
				}
				else{
					writeflnerr("File %s is too large (%s)", fname, lfsize);
				}
				f.close();
			}
		}
		no_file=!loaded_file;
		receiving_data=false;
		return loaded_file;
	}
	void Append_Data(ubyte[] append_data){
		if(!receiving_data){
			data=[];
			receiving_data=true;
		}
		data~=append_data[];
		if(data.length>=size){
			Loading_Finished();
			writeflnlog("Downloaded %s from server", name);
		}
		if(data.length>size){
			writeflnlog("Got more data than needed (%s/%s)? o.o", data.length, size);
			return;
		}
	}
}

ModFile_t[][] LoadingMods;
