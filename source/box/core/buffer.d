module box.core.buffer;

private {
	import box.core.memory;
	import core.stdc.stdio ;
	import core.stdc.string ;
	import std.range, std.algorithm, std.conv, std.traits;
	enum dchar INVALID_SEQUENCE = cast(dchar) 0xFFFFFFFF;
	dchar safeDecode(string s)  {
		return INVALID_SEQUENCE ;
	}
	void enforce(A)(A a...) {
		assert(a) ;
	}
}

struct BufferImpl() {
	
	@disable this(this) ;
	
	private {
		enum size_t MAX_LENGTH = int.max >> 4 ;
		alias This	= typeof(this) ;
		struct Node {
			@disable this(this);
			ubyte[] data ;
		}
		static struct Position {
			private {
				This*	m_owner ;
				size_t	m_pos ;
			}
			
			@disable this();
			private this(This* owner) {
				assert( owner !is null ) ;
				m_owner	= owner ;
				m_pos	= owner.m_pos ;
			}
			
			private this(This* owner, size_t pos) {
				assert( owner !is null ) ;
				assert( owner.m_pos >= pos ) ;
				m_owner	= owner ;
				m_pos	= pos ;
			}
			
			@property ref auto last() return {
				if( m_owner is null || m_pos < m_owner.m_pos ) {
					return Slice.init ;
				}
				return Slice(m_owner, m_pos, m_owner.m_pos - m_pos) ;
			}
			
	       	bool restore() {
	            if ( m_owner ) {
					scope(exit) m_owner = null ;
					if( m_pos <= m_owner.m_pos ) {
						m_owner.m_pos = m_pos ;
						return true ;
					}
	            } 
				return false ;
	        }
			
			
		}
		
		static struct Slice {
			
			alias toString this ;
			private {
				This*	m_owner ;
				size_t	m_pos ;
				size_t	m_len ;
			}
	
			pragma(inline) 
			@property ref auto range() return {
				return String(this) ;
			}
			
			@disable this();
		
			private this(This* owner, size_t pos, size_t len) {
				assert( owner !is null ) ;
				assert( owner.m_pos >= pos + len ) ;
				m_owner	= owner ;
				m_pos	= pos ;
				m_len	= len ;
			}
		
			private this(This* owner, size_t pos) {
				assert( owner !is null ) ;
				assert( owner.m_pos >= pos ) ;
				m_owner	= owner ;
				m_pos	= pos ;
				m_len	= owner.m_pos - pos ;
			}
	
			pragma(inline)
			@property auto length() const {
				assert( m_pos >= 0 ) ;
				assert( m_len >= 0 ) ;
				return m_len ;
			}
	
			string toString() @trusted {
				if( m_owner is null ) {
					return null ;
				}
				if( m_pos > m_owner.length ) {
					return null ;
				}
				assert( m_pos >= 0 ) ;
				assert( m_len >= 0 ) ;
				auto stop_pos = m_pos + m_len ;
				if( stop_pos > m_owner.length ) {
					return null ;
				}
				return cast(string) m_owner.m_data[m_pos .. stop_pos] ;
			}
		
			alias opSlice = toString ;
	
			pragma(inline)
			ref auto opSlice(size_t from, size_t to) return {
				assert( m_owner !is null);
				assert(from >= 0);
				enforce(from <= to);
				enforce(to <= m_len);
				return Slice(m_owner, from + m_pos, to - from ) ;
			}

			pragma(inline)
			size_t opDollar(size_t dim)() if(dim == 0) { 
				return m_len; 
			}
	
			void putString(ref Buffer bz) @trusted {
				assert( m_owner !is null );
				assert( m_pos >= 0 );
				enforce( m_owner.m_pos >= m_pos + m_len );
				bz.append( &m_owner.m_data[m_pos], m_len) ;
			}
		}
		
		/**
		 * array can move ptr ?
		 */
		static struct String {
			
			private {
				Slice	m_slice	= void ;
				ptrdiff_t m_size 	= void ;
				//  U+0000..U+10FFFF
				dchar	m_value	= void ;
			}
			
			@disable this();
			
			private this(ref Slice slice) {
				assert( slice.m_owner !is null ) ;
				m_slice.m_owner	= slice.m_owner ;
				m_slice.m_pos	= slice.m_pos ;
				m_slice.m_len	= slice.m_len ;
				m_value	= INVALID_SEQUENCE ;
				m_size	= -1 ;
			}
			
			private this(This* owner) {
				assert( owner !is null ) ;
				m_slice.m_owner	= owner ;
				m_slice.m_pos	= 0 ;
				m_slice.m_len	= owner.m_pos ;
				m_value	= INVALID_SEQUENCE ;
				m_size	= -1 ;
			}
			
			
			private this(ref String self) {
				assert( self.m_slice.m_owner ) ;
				m_slice.m_owner	= self.m_slice.m_owner ;
				m_slice.m_pos	= self.m_slice.m_pos ;
				m_slice.m_len	= self.m_slice.m_len ;
				m_value	= self.m_value ;
				m_size	= self.m_size ;
			}
			
			pragma(inline)
			auto toString() {
				assert( m_slice.m_pos + m_slice.m_len <= m_slice.m_owner.m_pos ) ;
				return cast(string) m_slice.m_owner.m_data[ m_slice.m_pos .. m_slice.m_pos + m_slice.m_len ] ;
			}
			
			alias opCast = toString ;

			pragma(inline)
			@property bool empty() {
				if( m_slice.m_len is 0 ) {
					return true ;
				}
				assert( m_slice.m_pos + m_slice.m_len <= m_slice.m_owner.m_pos ) ;
				if( m_value !is INVALID_SEQUENCE ) {
					assert( m_size > 0 && m_size <= 4 ) ;
					assert( m_size <= m_slice.m_len ) ;
					return false ;
				}
				auto data = cast(string) m_slice.m_owner.m_data[ m_slice.m_pos .. m_slice.m_pos + m_slice.m_len ] ;
				while( data.length ) {
					m_value	= safeDecode(data) ;
					if( m_value !is INVALID_SEQUENCE ) {
						break ;
					}
				}
				if( m_value is INVALID_SEQUENCE ) {
					m_slice.m_len	= 0 ;
					return true ;
				}
				assert( data.length < m_slice.m_len ) ;
				m_size	= m_slice.m_len - data.length ;
				assert( m_size > 0 && m_size <= 4 ) ;
				return false ;
			}
			
			pragma(inline) @property dchar front() {
				enforce( !empty ) ;
				assert( m_value !is INVALID_SEQUENCE ) ;
				assert( m_size > 0 && m_size <= 4 ) ;
				assert( m_slice.m_len >= m_size ) ;
				return m_value ;
			}
			
			pragma(inline) void popFront() {
				enforce( !empty ) ;
				m_value	= INVALID_SEQUENCE ;
				m_slice.m_pos 	+= m_size ;
				m_slice.m_len 	-= m_size ;
			}
			
			pragma(inline) @property ref auto save() return {
				return String(this) ;
			}
		}
	}
	
	static {
		alias Pool = Box!(Node, BoxType.Clear | BoxType.Unique , 128) ;
		template hasPutString(T) {
			static if( is( T == This ) ) {
				enum hasPutString = false ;
			} else static if( isPointer!T ) {
				enum hasPutString = false ;
			} else static if( __traits(hasMember, T, "putString") && __traits(compiles, "T.init.putString(Buffer.init);") ) {
				enum hasPutString = true ;
			} else {
				enum hasPutString = false ;
			}
		}
		static assert( !hasPutString!(This) );
	}

	private {
        ubyte[]		m_data ;
		ptrdiff_t	m_step = 1024 ;
		
        ptrdiff_t	m_pos  ;
        ptrdiff_t	m_last_pos ;
		Pool.Boxed	m_node ;
	}
	
	/**
	 * this 
	 */
	public {
	
		this(T)(T[] _data) if ( T.sizeof is 1 && !is(T == char) ) {
			if( _data.length ) {
				m_data	= cast(ubyte[]) _data ;
				if( _data.length > m_step ) {
					m_step	= _data.length ;
				}
			}
		}
		
		this(ptrdiff_t size) {
			enforce(size < MAX_LENGTH ) ;
			m_step	= size ;
		}
		
		~this() {
			dispose ;
		}

		void dispose() @trusted {
			if( !m_node.isNull ) {
				assert(m_data.ptr is m_node.data.ptr) ;
				assert(m_data.length is m_node.data.length) ;
				assert(m_node.data.length > 0) ;
				m_node.drop ;
			}
			// data[]	= 0 ;
			m_data	= null ;
			m_pos	= 0 ;
		}
	
		void clear() {
			m_data[]	= 0 ;
	        m_pos = 0 ;
		}
	
	    void move(ptrdiff_t _step) {
	        ptrdiff_t _pos = m_pos + _step;
			enforce( _pos >= 0 );
	        if (m_pos > m_data.length) {
	            expand( m_data.length - m_pos ) ;
	        }
	        m_pos = _pos;
	    }
	
		private {
		    void expand(size_t size) @trusted {
		        assert(m_data.length >= m_pos);
				assert(size < MAX_LENGTH);
				scope(exit) {
					 assert(m_data.length >= m_pos);
				}
		        auto len = m_data.length;
		        if (len - m_pos >= size) {
		            return;
		        }
				auto data_len = len ;
		        while (len - m_pos < size) {
		            len += m_step;
		            assert(len < MAX_LENGTH );
		        }
				assert( len > data_len ) ;
				// node 
				if( !m_node.isNull ) {
					assert( m_node.data.length  > 0 ) ;
					auto ret = alloc.expandArray(m_node.data, len - data_len ) ;
					enforce(ret) ;
				} else {
					auto tmp = Pool.make() ;
					m_node = tmp ;
					if( m_node.data.length is 0 ) {
						m_node.data	= alloc.makeArray!ubyte(len) ;
						enforce(m_node.data.length ) ;
					} else if( m_node.data.length < len ) {
						auto _data_len	= m_node.data.length ; 
						auto ret = alloc.expandArray(m_node.data, len - _data_len ) ;
						enforce(ret) ;
					}
					if( m_pos > 0) {
						assert(m_node.data.ptr !is m_data.ptr) ;
						memcpy(m_node.data.ptr, m_data.ptr, m_pos) ;
					}
				}
		
		        assert(!m_node.isNull) ;
		        assert(m_node.data.length > 0 ) ;
				m_data	= m_node.data ;
		        assert(len <= m_data.length) ;
				assert( m_data.ptr is m_node.data.ptr) ;
		    }
	
		    void append(inout(void)* ptr, size_t size) {
				assert(m_data.length >= m_pos);
		        if ( size > 0) {
					assert(ptr !is null);
		            expand(size);
		            memcpy(&m_data[m_pos], ptr, size);
		            m_pos += size;
		        }
		    }
		}
	}
	
	/**
	 * property 
	 */
	
	@property ref auto range() @trusted return {
		return String(&this) ;
	}
		
	@property {
		
		auto data() return {
			return cast(string) m_data[ 0 .. m_pos] ;
		}
		
		ref auto slice() return {
			return Slice(&this, 0) ;
		}
	
		ref auto save() return {
			m_last_pos	= m_pos ;
			return Position(&this, m_pos) ;
		}
		
		ref auto last() return {
			if( m_last_pos > m_pos ) {
				return Slice(&this, m_pos) ;
			}
			return Slice(&this, m_last_pos) ;
		}
		
	    size_t length() {
	        return m_pos;
	    }
		
	    size_t capability() {
	        return m_data.length;
	    }
		
		size_t space() {
	        return m_data.length - m_pos ;
	    }
	}
	
	/**
	 * op
	 */

	ref auto opSlice() return {
		return Slice(&this, 0, m_pos) ;
	}
	
	pragma(inline)
	ref auto opSlice(size_t from, size_t to) return {
		assert(from >= 0) ;
		enforce(from <= to);
		enforce(to <= m_pos);
		return Slice(&this, from, to - from) ;
	}

	size_t opDollar(size_t dim)() if(dim == 0) { 
		return m_pos; 
	}

	ref auto opCall(T)(T e) return if( !is(T == struct) ) {
		m_last_pos = m_pos ;
		put(e) ;
		return this ;
	}

	ref auto opCall(T)(ref T e) return if( is(T == struct) ) {
		m_last_pos = m_pos ;
		put(e) ;
		return this;
	}
	
	ref auto opCall(T)(T e) return if( is(T == struct) && __traits(compiles, "T a=void;T b=a;") ) {
		put(e) ;
		return this;
	}

	/**
	 * binary byte
	 */
	public {
			
		ref auto putByte(T)(inout(T) e) return if( isIntegral!T || isSomeChar!T ){
			static if ( T.sizeof is 1 ) {
		        expand(1);
		        m_data[m_pos++] = e ;
			} else {
		        append(&e, T.sizeof) ;
			}
			return this;
		}
		
		ref auto putByte(T)(ref T e) return if( is(T == struct) ){
			static if ( T.sizeof is 1 ) {
		        expand(1);
		        m_data[m_pos++] = e ;
			} else {
		        append(cast(void*) &e, T.sizeof) ;
			}
			return this;
		}
		
		ref auto putByte(T)(T e) return if( is(T == struct) && __traits(compiles, "T a=void;T b=a;") ){
			static if ( T.sizeof is 1 ) {
		        expand(1);
		        m_data[m_pos++] = e ;
			} else {
		        append(cast(void*) &e, T.sizeof) ;
			}
			return this;
		}
		
		ref auto putArray(T)(inout(T)[] e) return if( isIntegral!T || isSomeChar!T || is(T == struct) ){
	        append(e.ptr, T.sizeof * e.length) ;
			return this;
		}
		
		alias borrowNByte	= borrowArray!ubyte ;
		alias getNByte		= getArray!ubyte ;
		
		T[] borrowArray(T)(size_t size) @trusted return if ( isNumeric!(T) || is(T == struct) ) {
			static if( T.sizeof is 1) {
				alias _size	= size ;
			} else {
				auto _size	= size * T.sizeof ;
			}
			assert(_size < int.max);
			expand(_size) ;
			return (cast(T*) &m_data[m_pos])[ 0 .. size] ;
		}
		
		ubyte[] borrowByte(T)() return if ( isSomeChar!T || isNumeric!(T) || is(T == struct) ) {
			return borrowNByte(T.sizeof) ;
		}
		
		T* borrowPointer(T)() @trusted return if ( isSomeChar!T || isNumeric!(T) || is(T == struct) ) {
			expand(T.sizeof) ;
			return (cast(T*) &m_data[ m_pos ]) ;
		}
		
		T[] getArray(T)(size_t size) return if ( isSomeChar!T || isNumeric!(T) || is(T == struct) ) {
			static if( T.sizeof is 1) {
				alias _size	= size ;
			} else {
				auto _size	= size * T.sizeof ;
			}
			auto data = borrowArray!T(size) ;
			m_pos 	+= _size ;
			return data ;
		}
		
		ubyte[] getByte(T)() return if ( isSomeChar!T || isNumeric!(T) || is(T == struct) ) {
			auto data = borrowByte!T ;
			m_pos  += T.sizeof ;
			return data ;
		}
		
		T* getPointer(T)() return if ( isSomeChar!T || isNumeric!(T) || is(T == struct) ) {
			auto instance = borrowPointer!T ;
			m_pos  += T.sizeof ;
			return instance ;
		}
		
		T* getInstance(T, A...)(ref auto A args) return if ( is(T == struct) ) {
			auto data = getByte!T ;
			return emplace!(T)(data, args) ;
		}
		
		T getInstance(T, A...)(ref auto A args) return if ( is(T == class) && !__traits(isAbstractClass, T) ) {
			alias S = embed!T ;
			auto instance = borrowBinary!S ;
			instance.init(args) ;
			return instance.payload ;
		}
	}
	
	/**
	 * string put
	 */
	public {
		void put(T)(inout(T) b) if( isSomeChar!T && !is(T == enum) ){
			static assert( !hasPutString!(T) ) ;
			static if( T.sizeof is 1 ) {
				putByte(b) ;
			} else static if( T.sizeof is 4 ) {
				if (b <= 0x7F) {
				 	putByte( cast(ubyte) b) ;
				} else if (b <= 0x7FF) {
 				 	putByte( cast(ubyte) ((b >> 6) | 0xC0) ) ;
 				 	putByte( cast(ubyte) ((b & 0x3F) | 0x80) ) ;
				} else if (b <= 0xFFFF) {
  				 	putByte( cast(ubyte) ((b >> 12) | 0xE0) ) ;
  				 	putByte( cast(ubyte) (((b >> 6) & 0x3F) | 0x80) ) ;
  				 	putByte( cast(ubyte) ((b & 0x3F) | 0x80) ) ;
				} else if (b <= 0x1FFFFF) {
  				 	putByte( cast(ubyte) ((b >> 18) | 0xF0) ) ;
  				 	putByte( cast(ubyte) (((b >> 12) & 0x3F) | 0x80) ) ;
  				 	putByte( cast(ubyte) (((b >> 6) & 0x3F) | 0x80) ) ;
  				 	putByte( cast(ubyte) ((b & 0x3F) | 0x80) ) ;
				} else if (b <= 0x3FFFFFF) {
  				 	putByte( cast(ubyte) ((b >> 24) | 0xF8) ) ;
  				 	putByte( cast(ubyte) (((b >> 18) & 0x3F) | 0x80) ) ;
  				 	putByte( cast(ubyte) (((b >> 12) & 0x3F) | 0x80) ) ;
  				 	putByte( cast(ubyte) (((b >> 6) & 0x3F) | 0x80) ) ;
  				 	putByte( cast(ubyte) ((b & 0x3F) | 0x80) ) ;
				} else if (b <= 0x7FFFFFFF) {
  				 	putByte( cast(ubyte) ((b >> 30) | 0xFC) ) ;
  				 	putByte( cast(ubyte) (((b >> 24) & 0x3F) | 0x80) ) ;
  				 	putByte( cast(ubyte) (((b >> 18) & 0x3F) | 0x80) ) ;
  				 	putByte( cast(ubyte) (((b >> 12) & 0x3F) | 0x80) ) ;
  				 	putByte( cast(ubyte) (((b >> 6) & 0x3F) | 0x80) ) ;
  				 	putByte( cast(ubyte) ((b & 0x3F) | 0x80) ) ;
				}
			} else {
				static assert(false, T.stringof ) ;
			}
		}
	
		void put(T)(inout(T) e) if( isNumeric!T && !is(T == enum) ) {
			static assert( !hasPutString!(T) ) ;
		
			static if( isIntegral!T ) {
				static if( isSigned!T ) {
				    immutable negative = e < 0 ;
					Unsigned!T arg	= negative ?-e : e ;
				} else {
				    enum negative = false ;
					T arg	= e ;
				}
			
			    ubyte[64] buffer = void; // 64 bits in base 2 at most
			    ubyte[] digits;
			    {
			        size_t i = buffer.length;
			        while (arg)
			        {
			            --i;
			            buffer[i] = cast(ubyte) (arg % 10 + '0' ) ;
			            arg /= 10 ;
			        }
			        digits = buffer[i .. $]; // got the digits without the sign
			    }
				static if( isSigned!T ) {
					if( negative ) putByte('-') ;
				}
				putArray( digits ) ;
			} else static if( is(FloatingPointTypeOf!T) ) {
		        import std.math : isNaN, isInfinity;
				FloatingPointTypeOf!T val = e ;
			
			    version (CRuntime_Microsoft) {
			        immutable double tval = val; // convert early to get "inf" in case of overflow
					if (isNaN(tval)) {
						put("nan") ;
						return ;
					}
					if( isInfinity(tval) ) {
						if( val < 0 ) {
							putByte('-') ;
						}
						put("inf") ;
						return ;
					}
				} else {
			        alias tval = val;
				}
				static if( is(Unqual!(typeof(val)) == real) ) {
					auto sprintfSpec = "%*.*gL\0" ;
				} else {
					auto sprintfSpec = "%*.*g\0" ;
				}
				char[512] buf = void;
			    auto n = () @trusted {
			        return snprintf(buf.ptr, buf.length,
			                        sprintfSpec.ptr,
			                        0,
			                        -1,
			                        tval);
			    }();
				assert( n >= 0 ) ;
				if( n >= buf.length ) {
					n	= buf.length -1 ;
				}
				putArray( buf[ 0 .. n ] ) ;
			} else {
				static assert(false) ;
			}
		}
	
		void put(T)(inout(T)[] e) if( isSomeChar!T && !is(T == enum) ){
			static assert( !hasPutString!(T) ) ;
			static if(  T.sizeof is 1 ) {
				putArray(e) ;
			} else static if( T.sizeof is 4 ) {
		        for(int i = 0; i < e.length; i++) {
		        	put(e[i]) ;
		        }
			} else static if( T.sizeof is 2 ) {
				// import rt.util.utf ;
				int i = 0 ;
				do {
					dchar u = e[i];
					if (u & ~0x7F) {
						 if (u >= 0xD800 && u <= 0xDBFF) {
							if (i + 1 == e.length) {
								// "surrogate UTF-16 high value past end of string";
								break ;
							}
							dchar u2 = e[i + 1];
							if (u2 < 0xDC00 || u2 > 0xDFFF) {
								// "surrogate UTF-16 low value out of range";
								break ;
							}
							u = ((u - 0xD7C0) << 10) + (u2 - 0xDC00);
							i += 2 ;
						 } else  if (u >= 0xDC00 && u <= 0xDFFF) {
							 // "unpaired surrogate UTF-16 value";
							 break ;
						 }  else if (u == 0xFFFE || u == 0xFFFF) {
							 // "illegal UTF-16 value";
							 break ;
						 } else {
							i++; 	
						 }
					} else {
						i++;
					}
					put(u) ;
				} while( i < e.length ) ;
			} else {
				static assert(false, T.stringof) ;
			}
		}

		void put(T)(inout(T)[] e) if( !isSomeChar!T ) {
			putByte('[') ;
			if( e.length ) {
		        for(int i = 0; i < e.length; i++) {
		        	put(e[i]) ;
					putByte(',') ;
					putByte(' ') ;
		        }
				move(-2) ;
			}
			putByte(']') ;
		}
	
		void put(T)(T e) if( isAssociativeArray!(T) && !is(T == enum) ) {
			alias K = KeyType!T ;
			putByte('[') ;
			if( e.length ) {
		        foreach(K key, ref value; e) {
					static if( isSomeString!K ) {
						putByte('"') ;
						quote(key) ;
						putByte('"') ;
					} else {
				        put(key) ;
					}
					putByte(':') ;
		        	put(value) ;
					putByte(',') ;
					putByte(' ') ;
		        }
				move(-2) ;
			}
			putByte(']') ;
		}
	
		void put(T)(inout(T)[] e) if( is(T == enum) ){
			static assert(false) ;
		}
	
		void put(T)(T e) if ( is(T == class) ) {
			static if( hasPutString!T ) {
				if ( e is null ) {
					put("null") ;
				} else {
					e.putString(ptr) ;
				}
			} else {
				static assert(false) ;
			}
		}
	
		void put(T)(ref T e) if ( is(T == struct) ) {
			static if( is( Unqual!T == This ) ) {
				put(e.slice[]) ;
			} else static if( hasPutString!T ) {
				static if ( __traits(compiles, "e is null") ) {
					if ( e is null ) {
						put("null") ;
					} else {
						e.putString(ptr) ;
					}
				} else {
					e.putString(ptr) ;
				}
			} else {
				static assert(false) ;
			}
		}
	
		void put(T)(T e) if( is(T == struct) && __traits(compiles, "T a=void;T b=a;") ){
			static if( hasPutString!T ) {
				static if ( __traits(compiles, "e is null") ) {
					if ( e is null ) {
						put("null") ;
					} else {
						e.putString(ptr) ;
					}
				} else {
					e.putString(ptr) ;
				}
			} else {
				static assert(false, T.stringof) ;
			}
		}
	}
	
	public {
		
		ref auto quote(T)(T s, char quote = '"', ptrdiff_t deep = 0, char escape = '\\' ) return if( isSomeString!(T) ) {
			static assert( typeof(s[0]).sizeof is 1 ) ;
			m_last_pos = m_pos ;
			enforce(deep >=0 && deep < byte.max ) ;
			auto tmp = Range(s) ;
			auto bz	= tmp.range ;
			for( ;!bz.empty; bz.popFront ) {
				auto c = bz.front ;
				if( c is escape || c is quote || c is '\n' ) {
					for(ptrdiff_t j = 0; j <= deep; j++) {
						put(escape);
					}
					put(c);
				} else if( c is '\r'){
				
				} else {
					put(c);
				}
			}
			return this;
		}
	
		ref auto html(T)(T s) return if( isSomeString!(T) ) {
			m_last_pos = m_pos ;
			size_t last_line = 0 ;
			for(size_t i = 0 ; !s.empty; i++ , s.popFront ) {
				auto c = s.front ;
				if( c is '\\' ){
					put("\\\\");
				} else if( c is '\"' ){
					put(`&quot;`);
				} else if( c is '>' ){
					put(`&gt;`);
				}else if( c is '<' ){
					put(`&lt;`);
				} else if( c is '&' ){
					put(`&amp;`);
				} else if( c is '\n' ){
					if( last_line < i ){
						put('\\');
						put('n');
					}
				} else if( c is '\r' ){
					put('\\');
					put('n');
					last_line = i + 1 ;
				} else {
					put(c);
				}
			}
			return this;
		}
	
		ref auto unstrip(T)(T s, char quote = '\"') return if( isSomeString!(T) ) {
			enum escape = '\\' ;
			m_last_pos = m_pos ;
			for(; !s.empty; s.popFront ) {
				auto c = s.front ;
				if( c is escape || c is quote || c is '\n' ){
					put(escape);
					put(c);
				} else if( c is '\r' ) {
				
				} else if( c < ' ') {
					put("\\u");
					put( cast(ubyte) c ) ;
					put(";");
				} else {
					put(c);
				}
			}
			return this;
		}

		ref auto strip(T)(T s, char quote = '\"') return if( isSomeString!(T) ) {
			enum escape = '\\' ;
			m_last_pos = m_pos ;
			bool is_escaped = false ;
			for(; !s.empty; s.popFront ) {
				auto c = s.front ;
				if( is_escaped ) {
					if( c is 'n' || c is 'r' || c is 't' || c is quote || c is escape ) {
						put(c);
					} else if( c is 'u') {
						size_t n = 0 ;
						int size = void ;
						for(int i = 1; i < s.length; i++ ) {
							if( s[i] is ';' ) {
								size = i ;
								break ;
							}
							if( s[i] < '0' || s[i] >= '9' ) {
								break ;
							}
							n	= n * 10 ;
							n	+= cast(ubyte) s[i] - cast(ubyte) '0' ;
							if( n >= dchar.max ) {
								n	= 0 ;
								break ;
							}
						}
						if( n > 0 && s[1] !is '0' ) {
							if( n <= ubyte.max ) {
								put( cast(char) n ) ;
							} else {
								put( cast(dchar) n ) ;
							}
							s	= s[ size .. $ ] ;
						} else {
							put(escape) ;
							put(c) ;
						}
					} else {
						put(escape) ;
						put(c);
					}
					is_escaped	= false ;
					continue ;
				}
				if( c is escape ) {
					is_escaped = true ;
				} else {
					put(c);
				}
			}
			return this;
		}
	}
}


alias Buffer = BufferImpl!() ;
