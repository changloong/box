module box.core.time;

import core.stdc.time : time_t, tm ;

@system @nogc pure nothrow extern(C) {
	time_t time(time_t* timer);
	time_t mktime(tm* timeptr);
	tm* gmtime(time_t*);
	tm* localtime(time_t*);
	version(Windows) {
		tm* gmtime_s(tm*, time_t*);
		tm* localtime_s(tm*, time_t*);
	} else {
		tm* gmtime_r(time_t*, tm*);
		tm* localtime_r(time_t*, tm*);
	}
}

struct BoxTime {
	
	@system @nogc pure nothrow :
	
	static uint now() {
		time_t ts = time(null) ;
		return cast(uint) ts ;
	}
	
	static uint utc() {
		time_t ts = time(null) ;
		tm _tm = void;
		version(Windows) {
			gmtime_s(&_tm, &ts);
		} else {
			gmtime_r(&ts, &_tm);	
		}
		ts = mktime(&_tm);
		return cast(uint) ts ;
	}
}
