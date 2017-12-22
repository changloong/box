module box.core.ctfe;

import std.traits;

template aliasType(T) {
	static if( is(T==struct) ) {
		static if( __traits(getAliasThis, T).length is 1 ) { 
			alias Type	= typeof(  __traits(getMember, T, __traits(getAliasThis, T)[0]));
			static if( is(Type==struct) ) { 
				alias aliasType	= aliasType!Type ; 
			} else {
				alias aliasType	= Type ;	
			}
		} else {
			alias aliasType	= T ;	
		}
	} else {
		alias aliasType	= T ;	
	}
}

void aliasChainCtor(T, A...)(ref T t, ref auto A a) if( is(T==struct) && A.length > 0 ) {
	static if( __traits(getAliasThis, T).length is 1 ) { 
		alias Type	= typeof(  __traits(getMember, T, __traits(getAliasThis, T)[0]));
		aliasChainCtor!(Type, A)(t, a) ;
	} else static if( __traits(hasMember, T, "__ctor") ) {
		t.__ctor(a) ;
	} else {
		static assert(false) ;
	}
}

void aliasChainDtor(T, A...)(ref T t) if( is(T==struct) ) {
	static if( __traits(hasMember, T, "__dtor") ) {
		t.__dtor() ;
	} else  static if( __traits(getAliasThis, T).length is 1 ) { 
		alias Type	= typeof(  __traits(getMember, T, __traits(getAliasThis, T)[0]));
		aliasChainDtor!(Type, A)(t) ;
	} 
}