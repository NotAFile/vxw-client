extern(C){
struct pthread_t{
	void *pointer;
	uint extra_info; //NOTE: Could also be size_t (watch out on 64 bit systems)
}

alias pthread_attr_t=void;
	//void*(*func)(void*)
int pthread_create(pthread_t *, const pthread_attr_t *,  void* function(void*), void *);
void pthread_exit(void *);
int pthread_join(pthread_t, void**);
pthread_t pthread_self();
}
