import derelict.openal.al;
import derelict.vorbis.vorbis;
import derelict.vorbis.enc;
import derelict.vorbis.file;
import std.string;
import std.conv;
import std.traits;
import packettypes;
import protocol;
import world;
import ui;
import vector;
import misc;

void *Sound_Device, Sound_Context;

float Sound_Volume=1.0;
bool Sound_Enabled=true;
bool OpenAL_Initialized=false;

void Sound_Toggle(bool value){
	Sound_Enabled=value && OpenAL_Initialized;
}

SoundID_t ProtocolBuiltin_StepSound=VoidSoundID;
SoundID_t ProtocolBuiltin_ExplosionSound=VoidSoundID;
SoundID_t ProtocolBuiltin_BlockBreakSound=VoidSoundID;

enum SoundPlayOptions{
	Volume, Pitch
}

struct SoundSource_t{
	ALuint[] al_sources;
	ALuint[][] al_src_buffers;
	Vector3_t pos, vel;
	this(T)(T initarg){
		static if(is(T==Vector3_t))
			pos=initarg;
	}
	auto __alloc_openal_source(){
		alGetError();
		ALuint found_src=0;
		size_t ret_index;
		foreach(ind, src; al_sources){
			int state;
			alGetSourcei(src, AL_SOURCE_STATE, &state);
			if(__AlError("alGetSourcei() checking OpenAL source state"))return 0;
			if(state!=AL_PLAYING){
				found_src=src;
				if(al_src_buffers[ind].length){
					alSourceUnqueueBuffers(found_src, cast(uint)al_src_buffers[ind].length, al_src_buffers[ind].ptr);
					__AlError("alSourceUnqueueBuffers()");
					al_src_buffers[ind].length=0;
				}
				ret_index=ind;
				break;
			}
		}
		if(!found_src){
			al_sources~=0;
			al_src_buffers.length++;
			alGenSources(1, &al_sources[$-1]);
			found_src=al_sources[$-1];
			ret_index=al_sources.length-1;
		}
		if(__AlError("alGenSources()"))return 0;
		alSourcef(found_src, AL_GAIN, .1);
		if(__AlError("alSource() for gain"))return 0;
		alSourcef(found_src, AL_PITCH, 1.0);
		if(__AlError("alSource() for pitch"))return 0;
		alSourcei(found_src, AL_REFERENCE_DISTANCE, 1);
		if(__AlError("alSource() for reference distance"))return 0;
		alSourcei(found_src, AL_MAX_DISTANCE, 92);
		if(__AlError("alSource() for max distance"))return 0;
		alSourcei(found_src, AL_SOURCE_RELATIVE, 0);
		if(__AlError("alSource() for source relativity"))return 0;
		return ret_index;
	}
	void UnInit(){
		if(!OpenAL_Initialized)
			return;
		alGetError();
		foreach(ind, src; al_sources){
			{
				int state;
				alGetSourcei(src, AL_SOURCE_STATE, &state);
				if(state==AL_PLAYING){
					alSourceStop(src);
				}
			}
			if(al_src_buffers[ind].length){
				alSourceUnqueueBuffers(src, to!uint(al_src_buffers[ind].length), al_src_buffers[ind].ptr);
				__AlError("alSourceUnqueueBuffers()");
			}
			alDeleteSources(1, &src);
			__AlError("alDeleteSources()");
		}
	}
	void SetPos(P)(P spos){
		pos=spos;
		if(!Sound_Enabled)
			return;
		alGetError();
		foreach(src; al_sources){
			alSourcefv(src, AL_POSITION, pos.elements.ptr);
			__AlError("alSourcef() for position");
		}
	}
	void SetVel(V)(V svel){
		vel=svel;
		if(!Sound_Enabled)
			return;
		alGetError();
		foreach(src; al_sources){
			alSourcefv(src, AL_VELOCITY, vel.elements.ptr);
			__AlError("alSourcef() for velocity");
		}
	}
	//Hmm not sure if this option assoc is the best solution
	void Play_Sound(Sound_t snd, float[SoundPlayOptions] options=null){
		if(!Sound_Enabled)
			return;
		alGetError();
		auto src_ind=__alloc_openal_source();
		if(options!=null){
			if(SoundPlayOptions.Volume in options){
				alSourcef(al_sources[src_ind], AL_GAIN, options[SoundPlayOptions.Volume]);
				__AlError("alSource() for gain");
			}
			if(SoundPlayOptions.Pitch in options){
				alSourcef(al_sources[src_ind], AL_PITCH, options[SoundPlayOptions.Pitch]);
				__AlError("alSource() for pitch");
			}
		}
		alSourceQueueBuffers(al_sources[src_ind], to!uint(snd.buffers.length), snd.buffers.ptr);
		if(__AlError("alSourceQueueBuffers()"))
			return;
		al_src_buffers[src_ind]~=snd.buffers;
		alSourcePlay(al_sources[src_ind]);
		if(__AlError("alSourcePlay()"))
			return;
		if(options!=null && 0){
			if(SoundPlayOptions.Volume in options){
				alSourcef(al_sources[src_ind], AL_GAIN, .1);
				__AlError("alSource() for gain");
			}
			if(SoundPlayOptions.Pitch in options){
				alSourcef(al_sources[src_ind], AL_PITCH, 1.0);
				__AlError("alSource() for pitch");
			}
		}
	}
	bool Playing(){
		if(!Sound_Enabled)
			return false;
		alGetError();
		foreach(src; al_sources){
			int state;
			alGetSourcei(src, AL_SOURCE_STATE, &state);
			if(state==AL_PLAYING)
				return true;
		}
		return false;
	}
	bool Sound_Playing(Sound_t snd){
		size_t src_ind; bool src_found=false;
		foreach(ind; 0..al_src_buffers.length){
			if(al_src_buffers[ind]==snd.buffers){
				src_found=true;
				src_ind=ind;
			}
		}
		if(!src_found)
			return false;
		int state;
		alGetSourcei(al_sources[src_ind], AL_SOURCE_STATE, &state);
		return state==AL_PLAYING;
	}
}

SoundSource_t[] EnvironmentSoundSources;

struct Sound_t{
	ALuint[] buffers;
	void UnInit(){
		foreach(buf; buffers){
			alDeleteBuffers(1, &buf);
		}
	}
}

Sound_t[] Mod_Sounds;

import core.stdc.stdio;

extern(C) nothrow size_t __vorbisfile_read_func(void *ptr, size_t size, size_t nmemb, void *datasource){
	auto rfile=cast(__vorbisfile_readfunc_file*)datasource;
	if(rfile.data_pos==rfile.encoded_data.length-1){
		return 0;
	}
	size*=nmemb;
	if(rfile.data_pos+size>=rfile.encoded_data.length){
		(cast(ubyte*)ptr)[0..rfile.encoded_data.length-rfile.data_pos]=rfile.encoded_data[rfile.data_pos..$];
		auto written_size=rfile.encoded_data.length-rfile.data_pos;
		rfile.data_pos=rfile.encoded_data.length-1;
		return written_size;
	}
	(cast(ubyte*)ptr)[0..size]=rfile.encoded_data[rfile.data_pos..rfile.data_pos+size];
	rfile.data_pos+=size;
	return size;
}

struct __vorbisfile_readfunc_file{
	ubyte[] encoded_data;
	size_t data_pos;
}

Sound_t Sound_DecodeOgg(ubyte[] encoded_data){
	if(!OpenAL_Initialized)
		return Sound_t();
	OggVorbis_File vfile;
	ov_callbacks callbacks;
	callbacks.seek_func=null; callbacks.tell_func=null; callbacks.close_func=null;
	callbacks.read_func=&__vorbisfile_read_func;
	__vorbisfile_readfunc_file *__rfile=new __vorbisfile_readfunc_file;
	__rfile.encoded_data=encoded_data;
	__rfile.data_pos=0;
	auto cbret=ov_open_callbacks(__rfile, &vfile, cast(const char*)null, 0, callbacks);
	if(cbret<0){
		immutable auto possible_errors=[OV_EREAD, OV_ENOTVORBIS, OV_EVERSION, OV_EBADHEADER, OV_EFAULT];
		string errstr="Unknown error code";
		foreach(error; possible_errors){
			if(cbret==error){
				errstr=error.stringof;
				break;
			}
		}
		writeflnerr("ov_open_callbacks(): %s (%s)", cbret, errstr);
		return Sound_t();
	}
	struct datachunk_t{
		uint format, frequency;
		ubyte[] data;
	}
	datachunk_t[] data_chunks;
	while(1){
		ubyte[4096] buf;
		int current_pos;
		vorbis_info *info=ov_info(&vfile, -1);
		auto ret=ov_read(&vfile, cast(byte*)buf.ptr, buf.sizeof, 0, 2, 1, &current_pos);
		if(ret<0){
			writeflnerr("ov_read(): %s", ret);
			break;
		}
		if(!ret)
			break;
		uint fmt=info.channels==2 ? AL_FORMAT_STEREO16 : AL_FORMAT_MONO16;
		if(!data_chunks.length || fmt!=data_chunks[$-1].format || info.rate!=data_chunks[$-1].frequency){
			data_chunks~=datachunk_t(fmt, info.rate, []);
		}
		data_chunks[$-1].data~=buf[0..ret];
	}
	ov_clear(&vfile);
	Sound_t snd;
	snd.buffers.length=data_chunks.length;
	alGetError();
	alGenBuffers(to!uint(snd.buffers.length), snd.buffers.ptr);
	if(__AlError("alGenbuffers()"))
		return Sound_t();
	foreach(ind, chunk; data_chunks){
		if(!chunk.data.length)
			continue;
		alBufferData(snd.buffers[ind], chunk.format, cast(void*)chunk.data.ptr, to!uint(chunk.data.length), chunk.frequency);
		if(__AlError("alBufferData()")){}
	}
	return snd;
}

/* For sound, it's very important to not only be able to completely
 * disable execution of any related code to reduce CPU usage, but also
 * to not even load the corresponding libraries at all, so the game
 * can run on systems without OpenAL/Vorbis installed or where they cause trouble*/
void Init_Snd(){
	Sound_Enabled=Config_Read!bool("sound");
	if(!Sound_Enabled)
		return;
	DerelictVorbis.load();
    DerelictVorbisEnc.load();
    DerelictVorbisFile.load();
	DerelictAL.load();
	alGetError();
	Sound_Device=alcOpenDevice(null);
	if(!Sound_Device)
		if(__AlError("alcOpenDevice()"))
			return;
	alGetError();
	Sound_Context=alcCreateContext(Sound_Device, null);
	if(!Sound_Context)
		if(__AlError("alcCreateContext()"))
			return;
	alcMakeContextCurrent(Sound_Context);
	if(__AlError("alcMakeContextCurrent()"))
		return;
	OpenAL_Initialized=true;
	Sound_VolumeSet(Config_Read!float("volume"));
	Sound_Toggle(Config_Read!bool("sound"));
}

void Sound_Update(float dt=WorldSpeed){
	static float update_timer;
	update_timer+=dt;
	while(update_timer>=10.0){
		bool sources_deleted=false;
		do{
			foreach(ind, src; EnvironmentSoundSources){
				if(!src.Playing()){
					src.UnInit();
					EnvironmentSoundSources[ind]=EnvironmentSoundSources[$-1];
					EnvironmentSoundSources.length--;
					sources_deleted=true;
				}
			}
		}while(sources_deleted);
		update_timer-=10.0;
	}
}

void Sound_SetListenerPos(P)(P pos){
	if(!Sound_Enabled)
		return;
	Vector3_t vec=Vector3_t(pos);
	alListenerfv(AL_POSITION, vec.elements.ptr);
	if(__AlError("alListenerfv() for position"))
		return;
}

void Sound_SetListenerVel(V)(V vel){
	if(!Sound_Enabled)
		return;
	Vector3_t vec=Vector3_t(vel);
	alListenerfv(AL_VELOCITY, vec.elements.ptr);
	if(__AlError("alListenerfv() for velocity"))
		return;
}

void Sound_SetListenerOri(R)(R rot){
	if(!Sound_Enabled)
		return;
	Vector3_t vec=(Vector3_t(rot)+Vector3_t(0.0, 180.0, 0.0)).RotationAsDirection().normal();
	float[6] elements=vec~[0.0f, -1.0f, 0.0f];
	alListenerfv(AL_ORIENTATION, elements.ptr);
	if(__AlError("alListenerfv() for orientation"))
		return;
}

void Sound_VolumeSet(float vol){
	Sound_Volume=vol;
    alListenerf(AL_GAIN, Sound_Volume);
	__AlError("alListenerf() for gain");
}

private bool __AlError(string operation){
	uint error=alGetError();
	if(error!=AL_NO_ERROR){
		immutable auto al_errors_dict=[
			AL_INVALID_NAME:"AL_INVALID_NAME", AL_INVALID_ENUM:"AL_INVALID_ENUM", AL_INVALID_VALUE:"AL_INVALID_VALUE", 
			AL_INVALID_OPERATION:"AL_INVALID_OPERATION", AL_OUT_OF_MEMORY:"AL_OUT_OF_MEMORY"
		];
		string errstr="Unknown error";
		if(error in al_errors_dict){
			errstr=al_errors_dict[error];
		}
		writeflnerr(operation~": "~to!string(error)~" ("~errstr~")");
		return true;
	}
	return false;
}

void UnInit_Snd(){
	if(!OpenAL_Initialized)
		return;
	foreach(ref sound; Mod_Sounds)
		sound.UnInit();
	foreach(ref sound; EnvironmentSoundSources)
		sound.UnInit();
	alcDestroyContext(Sound_Context);
	alcCloseDevice(Sound_Device);
}
