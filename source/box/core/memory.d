module box.core.memory;

private {
	import core.stdc.stdint : uintptr_t ;
	import core.stdc.stdio ;
	import std.traits ;
	import std.typecons ;
	import box.core.ctfe ;
	import box.core.time ;
	
	extern(C) @nogc pure nothrow {
		void*	memcpy(void* dest, const(void)* src, size_t n);
		void*	memset(void* dest, int ch, size_t n);
		void*   malloc(size_t size);
		void*   calloc(size_t nmemb, size_t size);
		void*   realloc(inout(void)* ptr, size_t size);
		void    free(inout(void)* ptr);
		void    abort() @safe;
		void 	exit(int status);
		int     atexit(void function() func);
	}
	

	static struct Array(Node, size_t STEP_SIZE_SIZE, bool CHECK = false) {
		static if( CHECK ) {
			static struct List {
				Node[]	m_node_list ;
				@disable this(this);
			}
			Array!(List, STEP_SIZE_SIZE) m_array_list ;
		}
	
     	Node[] m_array ;
		size_t m_depth ;
		size_t m_step = STEP_SIZE_SIZE ;
	
		@disable this(this);
	
		~this() {
			drop;
		}
	
	    @property void drop() {
			static if( CHECK ) {
				if( m_array_list.m_array.length ) {
					for( size_t i = 0; i < m_array_list.m_depth ; i ++ ) {
						alloc.dispose( m_array_list.m_array[i].m_node_list ) ;
					}
				}
				m_array_list.drop ;
			} else {
				if( m_array.length ) {
					alloc.dispose( m_array ) ;
					memset( &this, 0, this.sizeof ) ;
					assert( m_array.length is 0 ) ;
				}
			}
			if( m_depth !is 0 ) {
		        m_depth = 0 ;
			}
	    }
	
		static if( isPointer!Node ) {
			static assert( !CHECK ) ;
		
			void push(Node value) {
				assert( value !is null) ;
				assert(m_depth <= m_array.length) ;
				if( m_array.length is 0 ) {
					assert( Node.sizeof * m_step > 0 ) ;
					assert( Node.sizeof * m_step < short.max ) ;
					m_array	= alloc.makeArray!Node(m_step) ;
					enforce( m_array.length is m_step ) ;
				}
		        if ( m_depth >= m_array.length ) {
					auto ret =alloc.expandArray(m_array, m_step) ;
					enforce(ret) ;
		        }
				assert( m_array.length > m_depth ) ;
		        m_array[m_depth++] = value;
			}
	
		} else {
		
		    Node* pop() {
				static if( CHECK ) {
					if( m_depth >= m_array.length ) {
						m_array		= alloc.makeArray!Node(m_step) ;
						enforce( m_array.length >= m_step ) ;
						auto _ptr	= m_array_list.pop ;
						_ptr.m_node_list	= m_array ;
						m_depth	= 0 ;
					}
				} else {
					if( m_array.length is 0 ) {
						m_array	= alloc.makeArray!Node(m_step) ;
						enforce( m_array.length >= m_step ) ;
					} else {
						alloc.expandArray(m_array, m_step) ;
						enforce( m_array.length >= m_step ) ;
					}
				}
		        size_t index	= m_depth ;
				m_depth++ ;
				return  &m_array[index] ;
		    }
		}
	}
}
public {
	
	void enforce(string file = __FILE__, int line = __LINE__, T, A...)(T value, auto ref A a) if (is(typeof({ if (!value) {} })))  {
	    if (!value) {
			static if( A.length ) {
				printf("enforce!%s:%d( ", file.ptr, line);
				static if( A.length is 1 ) {
					printf(a[0].ptr) ;
				} else {
					static assert(false) ;
				}
				printf(" )\n");
			} else {
				printf("enforce!%s:%d\n", file.ptr, line);
			}
			exit(-1) ;
		}
	}

	enum BoxType : ulong {
		None	= 0 ,
		Clear	= 1 ,
		Debug	= 1 << 1 ,
		Release	= 1 << 2 ,
		Unique	= 1 << 3 ,
		Slice	= 1 << 4 ,
		List	= 1 << 5 ,
		Local	= 1 << 6 , // thread local storage	
		Lock	= 1 << 7 , // lock
	}

	BoxType getBoxType ( BoxType TYPE) {
		if( (TYPE & BoxType.List) && !(TYPE & BoxType.Slice) ) {
			return getBoxType( TYPE | BoxType.Slice );
		}
		debug {
			if( !(TYPE & BoxType.Release) ) {
				return TYPE | BoxType.Debug ;
			} else {
				return TYPE ;
			}
		} else {
			return TYPE ;
		}
	}

	bool hasClear(BoxType type) {
		return cast(bool) (type & BoxType.Clear) ;
	}

	bool hasDebug(BoxType type) {
		return cast(bool) (type & BoxType.Debug) ;
	}

	bool hasSlice(BoxType type) {
		return cast(bool) (type & BoxType.Slice) ;
	}

	bool hasList(BoxType type) {
		return cast(bool) (type & BoxType.List) ;
	}
	
	bool hasUnique(BoxType type) {
		return cast(bool) (type & BoxType.Unique) ;
	}
	
	bool hasLocal(BoxType type) {
		return cast(bool) (type & BoxType.Local) ;
	}
	
	private uintptr_t _alignUp(uintptr_t alignment)(uintptr_t n) @nogc pure nothrow {
		static assert( alignment > 0 && !((alignment - 1) & alignment) ) ;
	    enum badEnd = alignment - 1 ; // 0b11, 0b111, ...
		enum notBadEnd = ~badEnd ;
	    return (n + badEnd) & notBadEnd ;
	}
	
	struct BoxAllocator {
	
	    @trusted 
	    void[] allocate(size_t bytes) immutable {
	        if (!bytes) return null;
	        auto p = malloc(bytes);
	        return p ? p[0 .. bytes] : null;
	    }

	    @system 
	    bool deallocate(inout(void)[] b) immutable {
	        free(b.ptr);
	        return true;
	    }

	    @system 
	    bool reallocate(ref inout(void)[] b, size_t s) immutable {
	        if (!s) {
	            deallocate(b);
	            b = null;
	            return true;
	        }
	        auto p = cast(inout(void)*) realloc(b.ptr, s);
	        if (!p) return false;
	        b = p[0 .. s];
	        return true;
	    }
		
		private void dispose(T)(auto ref inout(T)[] array) immutable {
			auto _array =  (cast(void*) array.ptr)[0 .. array.length * T.sizeof ] ; 
		    deallocate(_array);
		    static if (__traits(isRef, array))
		        array = null;
		}
		
		T[] makeArray(T)(size_t length) @trusted immutable {
		    if (!length) return null;
		    auto m = allocate(T.sizeof * length);
		    if (!m.ptr) return null;
		    return (cast(T*) m.ptr)[0 .. length] ; 
		}
		
		bool expandArray(T)(ref inout(T)[] array,  size_t delta) @trusted inout immutable {
		    if (!delta) return true;
		    if (array is null) return false;
			auto _array =  (cast(void*) array.ptr)[0 .. array.length * T.sizeof ] ;
		    if (!alloc.reallocate(_array, _array.length + T.sizeof * delta)) return false;
		    array = (cast(inout(T)*) _array.ptr)[0 .. array.length + delta ] ; 
		    return true;
		}
	}
	static __gshared immutable BoxAllocator alloc;
	import std.experimental.allocator.common : platformAlignment ;
}

struct Box(RawType, BoxType BOX_TYPE = BoxType.Clear, size_t STEP_SIZE = 64, string BOX_FILE = __FILE__, size_t BOX_LINE = __LINE__) if( is( RawType == struct ) ) {
	static immutable auto default_value = RawType.init ;
	enum MAX_STEP_SIZE	= 0x7ffffff ;
	static assert(STEP_SIZE > 0 && STEP_SIZE < MAX_STEP_SIZE );
	enum TYPE = getBoxType(BOX_TYPE) ;
	enum BOX_MAGIC_NUMBER = BOX_LINE ;
	
	private  {
		
		static struct RawNode {
			@disable this() ;
			@disable this(this);
			
			private :
			RawType m_raw_data = void ;
			size_t	m_magic_number = void ;
			RawNode*	m_next_unused = void ;
			bool		m_escaped = void ;	// setTrue on intoRaw
			
			static if( !TYPE.hasUnique ) {
				size_t m_ref_count = void ;
				private void addRefCount() {
					m_ref_count++ ;
				}
				private void releaseRefCount() {
					m_ref_count++ ;
				}
			}
			static if( TYPE.hasLocal )	Pool* m_pool = void ;
			
			static if( TYPE.hasSlice ) {
				RawNode*	m_next_slice = void ;
				static if( TYPE.hasList )  RawNode* m_pre_slice = void ;
				static if( TYPE.hasDebug ) {
					bool	m_sliced = void ;	// for shared data, should keep this on release mode
					void*	m_slice_owner  = void ;
				}
			}
			
			static if( TYPE.hasDebug ) {
				bool	m_inused = void ;
				uint 	m_time  = void ;
				string 	m_file  = void ;
				size_t 	m_line  = void ;
				size_t 	m_version = void ;
				size_t	m_index	= void ;
				
				private void updateVersion(string file, size_t line)(){
					// printf("updateVersion(index=%d, version=%d+1) from %s:%d at %s:%d\n", m_index, m_version, file.ptr, line, __FILE__.ptr, __LINE__);
					m_version	= size_t.max > m_version ? m_version + 1 : 1 ;
				}
			}
			
			private void assertNode(bool FOR_SLICE)() inout {
				static if( TYPE.hasDebug) {
					assert( m_inused ) ;
					assert( m_index >= 0 ) ;
					static if( TYPE.hasLocal ) {
						assert( m_index < m_pool.m_pool_indexs.m_depth ) ;
						assert( m_pool.m_pool_indexs.m_array[ m_index ] is &this ) ;
					}
					assert( m_version > 0 ) ;
				}
				static if( !TYPE.hasUnique ) {
					// printf("%s:%d assertNode=%d\n", __FILE__.ptr, __LINE__, m_ref_count);
					assert( m_ref_count < size_t.max );
				}
				static if( FOR_SLICE ) {
					static assert(TYPE.hasSlice) ;
					static if( TYPE.hasDebug )	assert( m_sliced !is false) ;
					static if( TYPE.hasDebug )  assert( m_slice_owner !is null) ;
				} else {
					static if( TYPE.hasSlice ) {
						assert( m_next_slice is null ) ;
						static if( TYPE.hasList ) 	assert(m_pre_slice is null) ;
						static if( TYPE.hasDebug )	assert(m_sliced is false) ;
						static if( TYPE.hasDebug )	assert( m_slice_owner is null) ;
					}
				}
			}
			
			private void _ctor(A...)(ref auto A a) if( A.length > 0) {
				aliasChainCtor(m_raw_data, a) ;
			}
			
			private void _dtor() {
				aliasChainDtor(m_raw_data) ;
			}
		}

		static struct Nullable(bool FOR_SLICE) {
			static if( TYPE.hasUnique ) {
				@disable this(this) ;
			} else {
				this(this) {
					if( !isNull ) m_raw_ptr.addRefCount ;
					printf("%s:%d postblit\n", __FILE__.ptr, __LINE__);
				}
			}
			
			private {
				alias NullableThis	= typeof(this) ;
				RawNode*	m_raw_ptr ;
				static if( TYPE.hasDebug ) {
					size_t m_raw_version ;
					string m_nullable_file ;
					size_t m_nullable_line ;
				}
				
				this(RawNode* raw_ptr, string file = __FILE__, size_t line = __LINE__) {
					if( raw_ptr !is null ) {
						m_raw_ptr	= raw_ptr ;
						static if( !TYPE.hasUnique ) m_raw_ptr.addRefCount ;
						static if( TYPE.hasDebug ) {
							m_raw_version = m_raw_ptr.m_version ;
							m_nullable_file	= file ;
							m_nullable_line	= line ;
						}
					}
				}
				
				void assertNullable(string file= __FILE__, size_t line = __LINE__)() inout {
			        if (m_raw_ptr !is null) {
						m_raw_ptr.assertNode!FOR_SLICE;
						static if( TYPE.hasDebug ) {
							if( m_raw_version !is m_raw_ptr.m_version ) {
								// printf("assertNullable(index=%d) version(%d != %d) from %s:%d at %s:%d\n",  m_raw_ptr.m_index, m_raw_version, m_raw_ptr.m_version, file.ptr, line, __FILE__.ptr, __LINE__) ;
							}
							assert(m_raw_version is m_raw_ptr.m_version) ;
						}
					}
				}
			}

		    ~this() {
		        drop;
		    }
			
			void drop(string file = __FILE__, size_t line = __LINE__)() {
				assertNullable!(file, line);
				scope(exit) assertNullable!(file, line);
				
		        if (m_raw_ptr !is null) {
					static if( TYPE.hasUnique ) {
						static if( !FOR_SLICE ) {
							pool.push!(FOR_SLICE, file, line)(m_raw_ptr) ;
						}
					} else {
						m_raw_ptr.m_ref_count-- ;
						static if( !FOR_SLICE ) {
							// printf("drop(id=%d, ref=%d)\n", getIndex, m_raw_ptr.m_ref_count) ;
							if( m_raw_ptr.m_ref_count is 0) {
								pool.push!(FOR_SLICE, file, line)(m_raw_ptr) ;
							}
						}
					}
		            m_raw_ptr = null;
		        }
			}
			
			alias getThis this ;
			
			@property ref auto getThis() return inout {
				assert(!isNull) ;
				assertNullable ;
				return m_raw_ptr.m_raw_data ;
			}
			
			@property bool isNull() const inout {
				assertNullable;
				return m_raw_ptr is null ;
			}

			this(ref NullableThis other, string file = __FILE__, size_t line = __LINE__) {
				assert(!isNull) ;
				assert(isNull) ;
				m_raw_ptr	= other.m_raw_ptr ;
			 	other.m_raw_ptr	= null ;
				static if( TYPE.hasDebug ) {
					m_raw_version = other.m_raw_version ;
					m_nullable_file	= file ;
					m_nullable_line	= line ;
				}
			}
			
			void opAssign(ref NullableThis other){
				drop ;
				if( !other.isNull ) {
					m_raw_ptr	= other.m_raw_ptr ;
				 	static if( TYPE.hasUnique ) {
						other.m_raw_ptr	= null ;
					} else {
						printf("%s:%d ref_count=%d\n", __FILE__.ptr, __LINE__, other.m_raw_ptr.m_ref_count);
						m_raw_ptr.addRefCount ;
					}
					static if( TYPE.hasDebug ) {
						m_raw_version	= m_raw_ptr.m_version ;
						m_nullable_file	= other.m_nullable_file ;
						m_nullable_line	= other.m_nullable_line ;
					}
				}
			}
			
			static if( !FOR_SLICE && !TYPE.hasUnique ) {
				
				void opAssign(NullableThis other){
					drop;
					if( !other.isNull ) {
						m_raw_ptr	= other.m_raw_ptr ;
						m_raw_ptr.addRefCount ;
						static if( TYPE.hasDebug ) {
							m_raw_version	= m_raw_ptr.m_version ;
							m_nullable_file	= other.m_nullable_file ;
							m_nullable_line	= other.m_nullable_line ;
						}
					}
				}
				
				// sliced raw ownerd by slice, can not escape
				// keep the RefCount from drop
				@property auto intoRaw(string file = __FILE__, size_t line = __LINE__)() {
					assertNullable!(file, line);
					scope(exit) assertNullable!(file, line);
					if( isNull ) {
						return null ;
					}
					auto ptr	= &m_raw_ptr.m_raw_data ;
					assert( ptr is cast(typeof(ptr)) m_raw_ptr ) ;
					m_raw_ptr	= null ;
					return cast(RawType*) ptr ;
				}
				
				@property auto fromRaw(string file = __FILE__, size_t line = __LINE__)(ref RawType* ptr) {
					m_raw_ptr	= cast(typeof(m_raw_ptr)) ptr ;
					ptr	= null ;
					static if( TYPE.hasDebug ) {
						m_raw_version	= m_raw_ptr.m_version ;
						m_nullable_file	= file ;
						m_nullable_line	= line ;
					}
				}
				
				@property auto takeRaw(string file = __FILE__, size_t line = __LINE__)(ref RawType* ptr) {
					drop!(file, line) ;
					if( ptr !is null ) {
						m_raw_ptr	= cast(typeof(m_raw_ptr)) ptr ;
						static if( !TYPE.hasUnique ) m_raw_ptr.addRefCount ;
						static if( TYPE.hasDebug ) {
							m_raw_version = m_raw_ptr.m_version ;
							m_nullable_file	= file ;
							m_nullable_line	= line ;
						}
						ptr	= null ;
					}
				}
				
				this(ref RawType* ptr) {
					if( ptr !is null ) {
						m_raw_ptr	= cast(typeof(m_raw_ptr)) ptr ;
						static if( !TYPE.hasUnique ) m_raw_ptr.addRefCount ;
						static if( TYPE.hasDebug ) m_raw_version = m_raw_ptr.m_version ;
						ptr	= null ;
					}
				}
			}
			
			static if( TYPE.hasDebug ) {

				@property auto inUsed(string file = __FILE__, int line = __LINE__)() {
					enforce!(file, line)(!isNull, "null") ;
					return m_raw_ptr.m_inused ;
				}

				@property auto getFile(string file = __FILE__, int line = __LINE__)() {
					enforce!(file, line)(!node.isNull, "null") ;
					return m_raw_ptr.m_file ;
				}

				@property auto getLine(string file = __FILE__, int line = __LINE__)() {
					enforce!(file, line)(!isNull, "null") ;
					return m_raw_ptr.m_line ;
				}

				@property auto getTime(string file = __FILE__, int line = __LINE__)() {
					enforce!(file, line)(!isNull, "null") ;
					return m_raw_ptr.m_time ;
				}
			
				@property auto isSliced(string file = __FILE__, int line = __LINE__)() const {
					enforce!(file, line)(!isNull, "null") ;
					return m_raw_ptr.m_sliced ;
				}
			}
			
			static if( !TYPE.hasUnique ) @property auto getRefCount(string file = __FILE__, int line = __LINE__)() const {
				enforce!(file, line)(!isNull, "null") ;
				return m_raw_ptr.m_ref_count ;
			}
			
			static if( TYPE.hasDebug ) {
				size_t getIndex(string file = __FILE__, int line = __LINE__)() const {
					enforce!(file, line)(!isNull, "null") ;
					assert( m_raw_ptr.m_index >= 0 ) ;
					assert( m_raw_ptr.m_index < pool.m_pool_indexs.m_depth ) ;
					assert( pool.m_pool_indexs.m_array[ m_raw_ptr.m_index ] is m_raw_ptr ) ;
					return m_raw_ptr.m_index + 1 ;
				}
			} else {
				@property size_t getIndex(string file = __FILE__, int line = __LINE__)() const {
					enforce!(file, line)(!isNull, "null") ;
					return cast(size_t) m_raw_ptr ;
				}
			}
		}
	}
	
	static if( TYPE.hasSlice ) {
		static alias Sliced	= Nullable!true ;
		/**
		 * for unique data,	Sliced should keep one copy, and removed after Slice destroyed, but can keep multi WeakRef
		 * for WeakRef to work, the version must be used even in release mode
		 *	
		 * Boxed only has one Owner, Sliced should be unique or removed(use Boxed instead)
		 * for shared data,	Sliced shoule be unique, but can have multi Boxed copy
		 * 		after Slice Destroyed, the data could be still inused and wait for destroy after task finished
		 *	
		 * in Range process, Slice can not be changed (add version to force, can be used only in debug)	
		 *	
		 * Can we remove Sliced.Owner for Non-Unique Boxed ? if so we has use RawNode.m_sliced to check if it has been already Sliced 
		 * for Rmoved Boxed (Double-List), how to know which Sliced to --length ? (use contain check)   
		 */
		static struct Slice {
			
			@disable this(this) ;
			
			private {
				ptrdiff_t	m_slice_length = 0 ;
				RawNode*	m_slice_first = null ;
				RawNode*	m_slice_last = null ;
			}
			
			invariant {
				assert( m_slice_length >= 0 ) ;
				if( m_slice_length is 0 ) {
					assert(m_slice_first is null);
					assert(m_slice_last is null);
				} else {
					assert(m_slice_first !is null);
					assert(m_slice_last !is null);
					if( m_slice_length is 1 ) {
						assert(m_slice_first is m_slice_last) ;
					} else {
						assert(m_slice_first.m_next_slice !is null) ;
						assert(m_slice_first !is m_slice_last) ;
					}
					assert(m_slice_last.m_next_slice is null) ;
					static if( TYPE.hasList ) {
						assert(m_slice_first.m_pre_slice is null) ;
						if( m_slice_length > 1 ) {
							assert(m_slice_last.m_pre_slice !is null) ;
						}
					}
				}
			}
			
			static struct Range {
				@disable this(this);
				
				private RawNode* m_range_ptr = null ;
				static if(TYPE.hasDebug)  void* m_slice_owner = null ;
				
				invariant {
					if( m_range_ptr !is null ) {
						static if( TYPE.hasDebug ) {
							assert( m_range_ptr.m_inused) ;
							assert( m_range_ptr.m_sliced) ;
							assert( m_slice_owner is m_range_ptr.m_slice_owner) ;
						}
					}
				}
				
				private this(RawNode* ptr) {
					m_range_ptr	= ptr ;
					static if(TYPE.hasDebug) m_slice_owner	= ptr.m_slice_owner ;
				}
				
				@property {
					ref auto front() const return {
						return Sliced( cast(RawNode*) m_range_ptr) ;
					}
					
					bool empty() const { 
						return m_range_ptr is null;
					}
				}
				
				void popFront() {
					if( m_range_ptr ) {
						m_range_ptr	= m_range_ptr.m_next_slice ;
					}
				}
			}

			this(ref Slice lhs) const {
				m_slice_length	= lhs.m_slice_length ;
				m_slice_first	= lhs.m_slice_first ;
				m_slice_last	= lhs.m_slice_last ;
				lhs.clear ;
			}

		    version(D_BetterC) {} else ~this() {
		        drop;
		    }
			
			private void clear() {
				m_slice_length	= 0 ;
				m_slice_first = null ;
				m_slice_last = null ;
			}
			
			void drop() {
		        if ( m_slice_length > 0 ) {
					printf("Slice(%s, length=%d) dropd\n", RawType.stringof.ptr, length);
		            pool.push(this) ;
					clear;
		        }
			}

			alias getRange this ;
			@property ref auto getRange() const return {
				return Range( cast(RawNode*) m_slice_first ) ;
			}
			
			@property ptrdiff_t length() const {
				return m_slice_length ;
			}
			
			void opOpAssign(string op, string file = __FILE__, size_t line = __LINE__)(ref Slice lhs) if (op == "~") {
				assert( lhs.m_slice_length >= 0 );
				assert( this.m_slice_length >= 0 );
				if( lhs.m_slice_length ) {
					m_slice_length	+=	lhs.m_slice_length	;
					if( m_slice_length > lhs.m_slice_length ) {
						assert( m_slice_last.m_next_slice is null ) ;
						static if( TYPE.hasList ) lhs.m_slice_first.m_pre_slice	= m_slice_last ;
						m_slice_last.m_next_slice	= lhs.m_slice_first ;
						m_slice_last	= lhs.m_slice_last ;
					} else {
						m_slice_first	= lhs.m_slice_first ;
						m_slice_last	= lhs.m_slice_last ;
					}
					static if( TYPE.hasDebug )  {
						for( auto _ptr = lhs.m_slice_first; _ptr !is null ; _ptr = _ptr.m_next_slice ) {
							_ptr.m_slice_owner = &this ;
						}
					}
					lhs.clear;
				}
			}
			
			void opOpAssign(string op)(ref Boxed o) if (op == "~") {
				assert(!o.isNull) ;
				_push(o.m_raw_ptr) ;
				o.m_raw_ptr	= null ;
			}
			
			private void _push(string file = __FILE__, size_t line = __LINE__)(RawNode* _ptr) in { assert(_ptr !is null); } do {
				static if( TYPE.hasDebug ) _ptr.m_sliced	= true ;
				if( m_slice_length > 0 ) {
					static if( TYPE.hasList ) _ptr.m_pre_slice	= m_slice_last ;
					m_slice_last.m_next_slice = _ptr ;
					m_slice_last	= _ptr ;
				} else {
					m_slice_first	= _ptr ;
					m_slice_last	= _ptr ;
				}
				static if( !TYPE.hasUnique ) {
					_ptr.addRefCount ;
					/**
					 * check ref number, if > 1, then old Boxed should be destroyed, and copy into a fresh RawNode
					 */
				}  else {
					// old Boxed should be destroyed 
				}
				static if( TYPE.hasDebug ) {
					_ptr.updateVersion!(file,line) ;
					_ptr.m_slice_owner = &this ;
					_ptr.m_sliced	= true ;
				}
				m_slice_length	+=	1 ;
			}
			
			
			private ref auto _pop(string file = __FILE__, size_t line = __LINE__)(RawNode* _ptr) return {
				assert(_ptr !is null) ;
				static if( TYPE.hasDebug ) _ptr.m_sliced = false ;
				static if( TYPE.hasDebug ) _ptr.m_slice_owner = null ;
				static if( TYPE.hasDebug ) _ptr.updateVersion!(file, line) ;
				static if( !TYPE.hasUnique ) _ptr.releaseRefCount() ;
				return Boxed(_ptr) ;
			}
			
			@property ref auto first() return {
				if( m_slice_length is 0 ) {
					return Sliced() ;
				}
				return Sliced(m_slice_first) ;
			}
			
			@property ref auto last() return {
				if( m_slice_length is 0 ) {
					return Sliced() ;
				}
				return Sliced(m_slice_last) ;
			}
			
			ref auto next(ref Sliced node) return {
				auto _ptr = node.m_raw_ptr  ;
				if( m_slice_length is 0 || _ptr is null ) {
					return Sliced() ;
				}
				
				auto _next	= node.m_raw_ptr.m_next_slice ;

				static if( TYPE.hasDebug ) {
					assert(_ptr.m_inused) ;
					assert(_ptr.m_sliced) ;
					if( _next ) {
						assert(_next.m_inused) ;
						assert(_next.m_sliced) ;
					}
				}
				return Sliced(_next) ;
			}
			
			bool has(ref Sliced node) {
				auto _ptr = node.m_raw_ptr ;
				if( m_slice_length is 0 ) {
					return false ;
				}
				for(auto _p = m_slice_first ; _p !is null; _p = _p.m_next_slice ){
					if( _p is _ptr ) {
						_p.assertNode!true ;
						static if(TYPE.hasDebug) assert( _ptr.m_slice_owner is &this) ;
						return true ;
					}
				}
				return false ;
			}
			
			static if( TYPE.hasList ) ref auto remove(string file = __FILE__, size_t line = __LINE__)(ref Sliced node) {
				if( node.isNull ) {
					return Boxed() ;
				}
				assert( has(node) ) ;
				auto _ptr	= node.m_raw_ptr ;
				if( m_slice_length is 1 ) {
					m_slice_first	= null ;
					m_slice_last	= null ;
					m_slice_length	= 0 ;
				} else if( m_slice_length > 1 ){
					m_slice_length--;
					if( _ptr.m_pre_slice is null ) {
						assert( _ptr is m_slice_first ) ;
						m_slice_first	= _ptr.m_next_slice ;
						m_slice_first.m_pre_slice	= null ;
						_ptr.m_next_slice	= null ;
					} else if( _ptr.m_next_slice is null ) {
						assert( _ptr is m_slice_last ) ;
						m_slice_last	= _ptr.m_pre_slice ;
						m_slice_last.m_next_slice	= null ;
						_ptr.m_pre_slice	= null ;
					} else {
						_ptr.m_pre_slice.m_next_slice = _ptr.m_next_slice ;
						_ptr.m_next_slice.m_pre_slice	= _ptr.m_pre_slice ;
						_ptr.m_pre_slice	= null ;
						_ptr.m_next_slice	= null ;
					}
				} else {
					enforce(_ptr is null) ;
				}
				node.drop ;
				return _pop!(file,line)(_ptr) ;
			}
			
			ref auto shift(string file = __FILE__, size_t line = __LINE__)() {
				if( m_slice_length is 0 ) {
					return Boxed() ;
				}
				auto _ptr	= m_slice_first ;
				m_slice_first	= _ptr.m_next_slice ;
				static if( TYPE.hasList ) assert( _ptr.m_pre_slice is null) ;
				if( m_slice_length > 1 ) {
					_ptr.m_next_slice	= null ;
					static if( TYPE.hasList ) m_slice_first.m_pre_slice = null ;
				} else {
					assert( m_slice_first is null) ;
					m_slice_last	= null ;
				}
				m_slice_length-- ;
				return _pop!(file,line)(_ptr) ;
			}
			
			static if( TYPE.hasList ) ref auto pop(string file = __FILE__, size_t line = __LINE__)() {
				assert( m_slice_length >= 0) ;
				if( m_slice_length is 0 ) {
					return Boxed() ;
				}
				auto _ptr	= m_slice_last ;
				m_slice_last	= _ptr.m_pre_slice ;
				if( m_slice_length > 1 ) {
					_ptr.m_pre_slice	= null ;
					m_slice_last.m_next_slice = null ;
				} else {
					assert( m_slice_last is null ) ;
					m_slice_first	= null ;
				}
				m_slice_length-- ;
				return _pop!(file,line)(_ptr) ;
			}
			
			static if( TYPE.hasList ) ref auto prev(ref Sliced node) {
				auto _ptr = node.m_raw_ptr ;
				if( m_slice_length is 0 || _ptr is null ) {
					return Sliced() ;
				}
				auto _prev	= _ptr.m_pre_slice ;
				return Sliced(_prev) ;
			}
			
			static if( TYPE.hasList ) @property bool isFirst(string file = __FILE__, size_t line = __LINE__)(ref Sliced node) {
				enforce!(file, line)(!node.isNull, "null") ;
				return node.m_raw_ptr is m_slice_first ;
			}
			
			@property bool isLast(string file = __FILE__, size_t line = __LINE__)(ref Sliced node) {
				enforce!(file, line)(!node.isNull, "null") ;
				return node.m_raw_ptr is m_slice_last ;
			}
		}
	}

	private {
		
		static struct Pool {
        	@disable this(this);
		
		 	Array!(RawNode, STEP_SIZE, true) 		m_pool_values ;
			static if( TYPE.hasDebug ) {
				Array!(RawNode*, STEP_SIZE)		m_pool_indexs ;
			}
			RawNode*		m_last_unused ;
			static if( TYPE.hasDebug ) ptrdiff_t	m_inused_counter ;
			static if( TYPE.hasDebug ) ptrdiff_t	m_unused_counter ;
			
		    void drop() {
				static if( TYPE.hasDebug ) {
					enforce(m_inused_counter is 0);
				}
				bool reset	= false ;
				static if( TYPE.hasDebug ) {
					if( m_pool_indexs.m_array.length ) {
						m_pool_indexs.drop ;
						reset	= true ;
					}
				}
				if(  m_pool_values.m_array.length  ) {
					m_pool_values.drop ;
					reset	= true ;
				}
				if( reset ) {
					memset( &this, 0, this.sizeof );
				}
		    }
	
			private auto pop(bool FOR_SLICE, string file= __FILE__, size_t line = __LINE__)() @trusted {
				auto _ptr	= m_last_unused ;
				if( _ptr !is null ) {
					static if( TYPE.hasSlice ) {
						assert( _ptr.m_next_slice is null) ;
						static if( TYPE.hasDebug ) assert( !_ptr.m_sliced ) ;
					}
					m_last_unused = _ptr.m_next_unused ;
					static if(TYPE.hasDebug) {
						_ptr.m_version = 1 ;
						 m_unused_counter-- ;
					}
				} else {
					_ptr	= m_pool_values.pop() ;
					assert(_ptr !is null) ;
					static if( TYPE.hasClear ) {
						memcpy(_ptr, &default_value, default_value.sizeof) ;
					} 
					_ptr.m_next_unused = null ;
					static if( TYPE.hasDebug ) {
						_ptr.m_index 	= m_pool_indexs.m_depth ;
						m_pool_indexs.push(_ptr) ;
						_ptr.m_magic_number = BOX_MAGIC_NUMBER ;
					}
					
					static if(TYPE.hasDebug) _ptr.updateVersion!(file, line) ;
					static if( TYPE.hasSlice ) {
						static if( !FOR_SLICE ) {
							_ptr.m_next_slice	= null ;
							static if( TYPE.hasList ) _ptr.m_pre_slice	= null ;
							static if( TYPE.hasDebug ) _ptr.m_sliced	= false ;
						}
					}
				}
				static if( !TYPE.hasUnique && !FOR_SLICE ) _ptr.m_ref_count = 0 ;
				static if( TYPE.hasDebug ) {
					_ptr.m_inused	= true ;
					_ptr.m_file	= file ;
					_ptr.m_line	= line ;
					_ptr.m_time	= BoxTime.now ;
					assert( m_inused_counter >= 0 );
					m_inused_counter++ ;
				}
				return _ptr ;
			}
			
			void push(bool FOR_SLICE, string file= __FILE__, size_t line = __LINE__)(RawNode* _ptr) @trusted {
				assert( _ptr !is null) ;
				_ptr.assertNode!FOR_SLICE() ;
				_ptr._dtor;
				
				static if( TYPE.hasDebug ) {
					assert( contains(_ptr) ) ;
					_ptr.m_inused	= false ;
					_ptr.m_file	= null ;
					_ptr.m_line	= 0 ;
					_ptr.m_time	= 0 ; 
				}
				static if( TYPE.hasClear ) {
					memcpy(_ptr, &default_value, default_value.sizeof) ;
				}
				static if( TYPE.hasDebug ) {
					assert( _ptr.m_index >= 0 ) ;
					assert( m_pool_indexs.m_depth > _ptr.m_index ) ;
					assert( m_pool_indexs.m_array.length >  0 ) ;
					assert( m_pool_indexs.m_array[ _ptr.m_index ] is _ptr ) ;
				}
				static if( TYPE.hasSlice ) {
					static if( TYPE.hasDebug ) _ptr.m_sliced	= false ;
					static if( FOR_SLICE ) {
						_ptr.m_next_slice	= null ;
						static if( TYPE.hasList ) _ptr.m_pre_slice	= null ;
						static if( TYPE.hasDebug ) _ptr.m_slice_owner = null ;
					} 
				}
				_ptr.m_next_unused	= m_last_unused ;
				m_last_unused	= _ptr ;
				static if( TYPE.hasDebug ) {
					m_inused_counter-- ;
					m_unused_counter++;
					assert( m_inused_counter >= 0 ) ;
				}
			}
	
			bool contains(RawNode* _ptr) {
				static if( TYPE.hasDebug ) {
					assert( _ptr.m_index >= 0 ) ;
					assert( _ptr.m_index < m_pool_indexs.m_depth ) ;
					assert( m_pool_indexs.m_array[ _ptr.m_index ] is _ptr ) ;
				}
				static bool match(RawNode* _ptr, RawNode[] list) {
					if( list.length is 0 ) {
						return false ;
					}
					if(  _ptr < &list[0] || _ptr > &list[$-1] ) {
						return false ;
					}
					return  true ;
				}
				if( match(_ptr, m_pool_values.m_array[ 0 .. m_pool_values.m_depth]) ) {
					return true ;
				}
				for(size_t i = 0 ; i < ( m_pool_values.m_array_list.m_depth - 1 )  ; i++ ) {
					if( match(_ptr, m_pool_values.m_array_list.m_array[i].m_node_list ) ) {
						return true ;
					}
				}
				return false ;
			}
			
			static if( TYPE.hasSlice ) {
	
				pragma(inline)
				void push(string file= __FILE__, size_t line = __LINE__)(ref Slice slice) {
					auto	_ptr	= slice.m_slice_first ;
					static if( TYPE.hasDebug ) {
						size_t	counter	= 0 ;
					}
					while( _ptr !is null ) {
						auto	_next	= _ptr.m_next_slice ;
						push!(true, file, line)(_ptr) ;
						_ptr	= _next ;
						static if( TYPE.hasDebug ) {
							counter++ ;
						}
					}
					static if( TYPE.hasDebug ) {
						assert( counter is slice.m_slice_length );
					}
					slice.m_slice_first		= null ;
					slice.m_slice_last		= null ;
					slice.m_slice_length	= 0 ;
				}
		
				ref auto slice(string file= __FILE__, size_t line = __LINE__)(size_t size) return {
					Slice _slice = void ;
					if( size is 0 ) {
						_slice.m_slice_length	= 0 ;
						_slice.m_slice_first	= null ;
						_slice.m_slice_last	= null ;
						return _slice ;
					}
					_slice.m_slice_length	= size ;

					// printf("%s:%d = new slice = %x\n", __FILE__.ptr, __LINE__, &_slice);
					
					static void setSilceNode(RawNode* _ptr, ref Slice _slice) {
						static if( TYPE.hasDebug ) _ptr.m_sliced	= true ;
						static if( TYPE.hasDebug ) _ptr.m_slice_owner = &_slice ;
						static if( !TYPE.hasUnique ) _ptr.m_ref_count = 1 ;
					}
					auto	_ptr	= pop!(true, file, line) ;
					_slice.m_slice_first	= _ptr ;
					_slice.m_slice_last		= _ptr ;
					
					setSilceNode(_ptr, _slice);
					static if( TYPE.hasList ) _ptr.m_pre_slice	= null ;
					
					size-- ;
					for(ptrdiff_t i =0; i < size ; i++) {
						_ptr	= pop!(true, file, line);
						setSilceNode(_ptr, _slice) ;
						_slice.m_slice_last.m_next_slice	= _ptr ;
						static if( TYPE.hasList ) _ptr.m_pre_slice	= _slice.m_slice_last ;
						_slice.m_slice_last	= _ptr ;
					}
					_ptr.m_next_slice	= null ;
					return _slice ;
				}
		
			}
			
		}
		static if( TYPE.hasLocal ) {
			static assert(false) ;
		} else {
			static __gshared Pool _pool ;
		}
		
		static if( TYPE.hasLocal ) {
			// add Global Hook
			
			// add Thread Hook
			
			@property auto pool() {
				assert(false) ;
			}
		} else {
			alias pool	= _pool ;
		}
	}
	
	static alias Boxed	= Nullable!false ;
	
	static {
		
		static struct Weak {
			static if( TYPE.hasUnique ) {
				@disable this(this) ;
			}
			private RawNode* m_raw_ptr ;
			static if( TYPE.hasDebug ) size_t m_raw_version ;
			
		}
		
		ref auto make(string file = __FILE__, size_t line = __LINE__)(){
			auto ptr = pool.pop!(false, file, line) ;
			return Boxed(ptr, file, line) ;
		}
		
		ref auto make(string file = __FILE__, size_t line = __LINE__, A...)(auto ref A a) if(A.length > 0 ){
			auto ptr = pool.pop!(false, file, line) ;
			ptr._ctor(a);
			return Boxed(ptr, file, line) ;
		}
		
		static if( TYPE.hasSlice ) {
			ref auto slice(string file = __FILE__, int line = __LINE__)(size_t size) {
				return pool.slice!(file, line)(size);
			}
		}
		
		static if( TYPE.hasDebug ) {

			auto inUsed(string file = __FILE__, int line = __LINE__)(ref Type node) {
				enforce!(file, line)(!node.isNull, "null") ;
				return node.m_raw_ptr.m_inused ;
			}

			auto getFile(string file = __FILE__, int line = __LINE__)(ref Type node) {
				enforce!(file, line)(!node.isNull, "null") ;
				return node.m_raw_ptr.m_file ;
			}

			auto getLine(string file = __FILE__, int line = __LINE__)(ref Type node) {
				enforce!(file, line)(!node.isNull, "null") ;
				return node.m_raw_ptr.m_line ;
			}

			auto getTime(string file = __FILE__, int line = __LINE__)(ref Type node) {
				enforce!(file, line)(!node.isNull, "null") ;
				return node.m_raw_ptr.m_time ;
			}
			
			bool isSliced(string file = __FILE__, int line = __LINE__)(ref Type node) const {
				enforce!(file, line)(!node.isNull, "null") ;
				return node.m_raw_ptr.m_sliced ;
			}
		} 
		
		static if( !TYPE.hasDebug ) {
			@property size_t getIndex(string file = __FILE__, int line = __LINE__)(ref Type node) const {
				enforce!(file, line)(!node.isNull, "null") ;
				return cast(size_t) node.m_raw_ptr ;
			}
		} else {
			size_t getIndex(string file = __FILE__, int line = __LINE__)(ref Type node) const {
				enforce!(file, line)(!node.isNull, "null") ;
				assert( node.m_raw_ptr.m_index >= 0 ) ;
				assert( node.m_raw_ptr.m_index < pool.m_pool_indexs.m_depth ) ;
				assert( pool.m_pool_indexs.m_array[ node.m_raw_ptr.m_index ] is node.m_raw_ptr ) ;
				return node.m_raw_ptr.m_index + 1 ;
			}
			static Node* getByIndex(string file = __FILE__, int line = __LINE__)(size_t index) const {
				enforce!(file,line)( index > 0 ) ;
				enforce!(file,line)( index <= pool.m_pool_indexs.m_depth ) ;
				index--;
				enforce!( pool.m_pool_indexs.array[ index ].m_index is index) ;
				auto _ptr = pool.m_pool_indexs.array[ index ] ;
				return &_ptr.data ;
			}
		}
	}
}


unittest {
	// mutable borrow quit scope, need return the ownership to parent, so it need has one pointer to the parent 
	// only one mutable borrow to a resource  
	// can have more than one immutable borrow
	// need static check scope if eq or bigger, smaller
	// slice borrow by range, will not able to change ?
	struct Node {
		int i;
	}
	alias T1 = Box!(Node, BoxType.List) ;
	
	auto s1 = T1.slice(2) ;
	assert( s1.length is 2) ;
	
	auto x = s1.pop ;
	printf("%s:%d %s \n", __FILE__.ptr, __LINE__, typeof(x).stringof.ptr);
	assert( s1.length is 1) ;
	s1	~= x ;
	assert( s1.length is 2) ;
	
	
	/*
	auto x2 = s1.pop ;
	assert( s1.length is 0) ;
	
	
	auto f = s1.first ;
	assert( f.isNull ) ;
	
	s1	~= x ;
	assert( x.isNull ) ;
	assert( s1.length is 1) ;
	
	
	auto s2 = T1.slice(3) ;
	assert( s2.length is 3) ;
	
	s1	~= s2;
	assert( s2.length is 0) ;
	assert( s1.length is 5) ;
	
	auto y = s1.pop ;
	assert( s1.length is 4) ;

	auto f2 = s1.next(f) ;
	
	foreach(p; s1) {
		assert( s1.has(p) ) ;
		auto x1 = p.i ;
		if( !s1.isLast(p) ) {
			auto f3 = s1.next(p) ;
		}
		if( !s1.isFirst(p) ) {
			auto f4 = s1.prev(p) ;
		}
	}
*/
}


