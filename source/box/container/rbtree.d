module box.container.rbtree;

/**
 * https://gist.github.com/nandor/9249431
 */

import std.traits ;
import box.core.memory ;
import box.core.buffer ;
import core.stdc.stdio;

struct RedBlack (Node, size_t STEP = 1024, BoxType BOX_TYPE = BoxType.None )
{

	enum  CTYPE = getBoxType(BOX_TYPE | BoxType.Clear ) ;
	
	static assert( is( Node == struct ) ) ;
	static assert( is( typeof(Node.opCmp) == function ) ) ;
	private alias opCmpFn	= typeof(Node.opCmp) ;
	static assert( isSigned!( ReturnType!opCmpFn ) ) ;
	private alias opCmpFnP	= Parameters!opCmpFn ;
	static assert( opCmpFnP.length is 1) ;
	static assert(__traits(isSame, Node, opCmpFnP[0]));
	private alias opCmpFnS	= ParameterStorageClassTuple!opCmpFn ;
   // static assert( opCmpFnS[0] & ParameterStorageClass.ref_ ||  opCmpFnS[0] & ParameterStorageClass.out_ ) ;
	
	enum Color : bool {RED = false, BLACK = true}
	
	static private struct Value {
		@disable 	this() ;
		@disable 	this(this) ;
		alias 		node this ;
		Node		node ;
		
		private  {
			Value*	parent, right, left ;
			Color	color = Color.RED ;
		} 
	}
	
	static alias Pool = Box!(Value, CTYPE, STEP) ;
	
	private {
		 Value*		root ;
		 size_t 	size ;
	}
	
	void drop() {
		pragma(inline)
		static void clearNode(ref Pool.Boxed box, Value* ptr) {
			if( ptr.left ) clearNode(box, ptr.left) ;
			if( ptr.right ) clearNode(box, ptr.right) ;
			// printf("%s:%d i=%d\n", __FILE__.ptr, __LINE__, ptr.i);
			box.fromRaw(ptr) ;
			box.drop() ;
		}
		if( root ) {
			Pool.Boxed	box ;
			clearNode(box, root) ;
			size	= 0 ;
			root	= null ;
		}
	}
	
	static if( CTYPE.hasSlice ) {
		alias Slice	= pool.Slice ;
	}
	
	ref auto make(string file= __FILE__, size_t line = __LINE__, A...)(auto ref A a) return {
		auto ptr = Pool.make!(file,line)(a) ;
		assert(ptr.left is null) ;
		assert(ptr.right is null) ;
		assert(ptr.parent is null) ;
		return ptr ;
	}
	
	@disable this(this);
	
	~this(){
		drop;
	}
	
	ref auto find(ref Node node) return {
	    auto p = root ;
		
	    while( p !is null ) {
			auto ret = p.node.opCmp(node) ;
			if( ret is 0 ) {
				break ;
			}
	        if( ret > 0 )
	            p = p.left;
	        else
	            p = p.right;
	    }
	    return Pool.Boxed(p) ;
	}
	
	bool insert(ref Pool.Boxed box) {
		if( box.isNull ) {
			return false ;
		}
		Value*	p = box.intoRaw ;
		assert(box.isNull) ;
		
		Value*  z = p ;
	    Value*	y = null ;
	    Value*	x = root;

	    while( x !is null)  {
	        y = x ;
			auto ret	= p.node.opCmp(x.node) ;
			if( ret is 0 ) {
				// already exists
				box.fromRaw(p) ;
				return false ;
			}
	        if( ret < 0 )
	            x = x.left;
	        else
	            x = x.right;
	    }

	    z.parent = y;
	    if(y is null) {
	        root = z;
		} else{
			auto ret	= z.node.opCmp(y.node) ;
			if( ret is 0 ) {
				assert(false) ;
			}
			if(  ret < 0 ) {
				y.left = z;
			} else {
				y.right = z;
			}
		} 
		
		if( z !is root ) {
			assert( z.parent !is null) ;
		}
		fixInsert(z) ;
		assert(root.parent is null);
		size++ ;
		
		// create a copy, put into box
		box.takeRaw(p) ;
		
		return true ;
	}
	
	bool remove(ref Pool.Boxed box) {
		if( box.isNull ) {
			return false ;
		}
		auto node = find(box) ;
		if( node.isNull ) {
			return false ;
		}
		auto	p = node.intoRaw ;
		
		Value*  z = p ;
	    Value*	y = z ;
	    Value*	x = null ;
		Color	y_original_color = y.color ;
		
		if(z.left is null) {
		        x = z.right;
		        transplant(z, z.right);
		} else if(z.right is null) {
		        x = z.left;
		        transplant(z, z.left);
		} else {
		        y = minimum(z.right);
		        y_original_color = y.color;
		        x = y.right;
		        if(y.parent == z) {
		            x.parent = z ;
				} else {
		            transplant(y, y.right);
		            y.right = z.right;
		            y.right.parent = y;
		        }
		        transplant(z, y);
		        y.left = z.left;
		        y.left.parent = y;
		        y.color = z.color;
		}
		
	    if( y_original_color is Color.BLACK ) {
           	fixDelete(x);
	    }
		
		node.fromRaw(p) ;
		node.drop ;

		size-- ;
		return true ;
	}
	
	private pragma(inline) {
		static Value* minimum(Value* p) {
			assert( p !is null) ;
	    	while(p.left !is null) {
	        	p = p.left;
	    	}
	    	return p;
		}
	
		void fixInsert(Value* z) {
			assert( z !is null) ;
			while( z.parent && z.parent.color is Color.RED) {
				if( z.parent.parent is null ) {
					break ;
				}
				if(z.parent is z.parent.parent.left) {
		               Value* y = z.parent.parent.right;
		               if( y && y.color == Color.RED ) {
		                   z.parent.color = Color.BLACK;
		                   y.color = Color.BLACK;
		                   z.parent.parent.color = Color.RED;
		                   z = z.parent.parent;
					   } else {
		                   if(z is z.parent.right) {
		                       z = z.parent;
		                       leftRotate(z);
		                   }
		                   z.parent.color = Color.BLACK;
		                   z.parent.parent.color = Color.RED;
		                   rightRotate(z.parent.parent);
		               }
				 } else {
		               Value* y = z.parent.parent.left;
		               if( y && y.color == Color.RED) {
		                   z.parent.color = Color.BLACK;
		                   y.color = Color.BLACK;
		                   z.parent.parent.color = Color.RED;
		                   z = z.parent.parent;
					   } else {
		                   if( z is z.parent.left) {
		                       z = z.parent;
		                       rightRotate(z);
		                   }
		                   z.parent.color = Color.BLACK;
		                   z.parent.parent.color = Color.RED;
		                   leftRotate(z.parent.parent);
		               }
		          }
		    }
		    root.color = Color.BLACK;
		}
	
		void fixDelete(Value* x) {
			if(  x is null  ) {
				return ;
			}
			while(x !is root && x.color is Color.BLACK) {
				if( x.parent is null ) {
					break ;
				}
			    if( x == x.parent.left )  {
			            Value* w = x.parent.right;
			            if(w.color is Color.RED) {
			                w.color = Color.BLACK;
			                w.parent.color = Color.RED;
			                rightRotate(w);
			                w = x.parent.right;
			            }

			            if(w.left.color is Color.BLACK && w.right.color is Color.BLACK)  {
			                w.color = Color.RED;
			                x = x.parent;
						}  else {
			                if(w.right.color is Color.BLACK) {
			                    w.left.color = Color.BLACK;
			                    w.color = Color.RED;
			                    rightRotate(w);
			                    w = x.parent.right;
			                }
			                w.color = x.parent.color;
			                x.parent.color = Color.BLACK;
			                w.right.color = Color.BLACK;
			                leftRotate(x.parent);
			                x = root;
			            }
					} else {
			            Value* w = x.parent.left;
			            if(w.color is Color.RED)  {
			                w.color = Color.BLACK;
			                w.parent.color = Color.RED;
			                leftRotate(w);
			                w = x.parent.left;
			            }

			            if(w.left.color is Color.BLACK && w.right.color is Color.BLACK) {
			                w.color = Color.RED;
			                x = x.parent;
						} else {
			                if(w.left.color is Color.BLACK) {
			                    w.right.color = Color.BLACK;
			                    w.color = Color.RED;
			                    leftRotate(w);
			                    w = x.parent.left;
			                }
			                w.color = x.parent.color;
			                x.parent.color = Color.BLACK;
			                w.left.color = Color.BLACK;
			                rightRotate(x.parent);
			                x = root;
			            }
			        }
			    }
			    x.color = Color.BLACK;
		}
	
		void transplant(Value* u, Value* v) {
			assert( u !is null) ;
	    	if(u.parent is null ) {
				assert(v !is null) ;
	        	root = v;
			} else if( u is u.parent.left) {
	        	u.parent.left = v;
			} else {
	        	u.parent.right = v;
	    	}
			if( v ) {
		    	v.parent = u.parent;
			}
		}
	
		void leftRotate(Value* x) {
			if( x.right is null ) {
				assert(false) ;
				// return ;
			}
			Value* y = x.right; //Set y
			x.right = y.left; //Turn y's left subtree into x's subtree
			if( y.left !is null ) {
				y.left.parent = x;
			}
			y.parent = x.parent;  //Link x's parent to y
			y.left = x;
			if( x.parent is null ) {
			     root = y;
			} else if( x == x.parent.left ){
				 x.parent.left = y;
			} else {
				x.parent.right = y;
			}
		    x.parent = y;
		}
	
		void rightRotate(Value* y) {
		    if( y.left is null ) {
				assert(false) ;
		        // return ;
		    }
		    Value* x = y.left;
		    y.left = x.right;
		    if(x.right !is null) {
		        x.right.parent = y;
		    } 
		    x.parent = y.parent;
		    x.right = y;
		    if(y.parent is null) {
		        root = x;
			} else if(y is y.parent.left)  {
		        y.parent.left = x;
			} else {
		        y.parent.right = x;
		    }
		    y.parent = x;
		}
	}
}


version(XX) :
unittest {
	static __gshared cnt = 0 ;
	struct Node {
		int i ;
		this(int i) {
			this.i	= i ;
			// printf("%s:%d this(%d)\n", __FILE__.ptr, __LINE__, i);
		}
		int opCmp(ref Node o) {
			return o.i - i ;
		}
		
		~this(){
			// printf("%s:%d ~this(%d)\n", __FILE__.ptr, __LINE__, i);
		}
	}
	alias T = RedBlack!Node ;
	T tree ;
	auto p = tree.make(3) ;
	assert(p.i is 3) ;
	auto ret = tree.insert(p) ;
	assert(ret) ;
	assert( p.i is 3) ;
	
	auto p4 =  tree.make(4) ;
	tree.insert(p4) ;
	
	auto p0 =  tree.make(0) ;
	tree.insert(p0) ;
	
	auto p7 =  tree.make(7) ;
	tree.insert(p7) ;
	
	Node x = Node(4) ;
	auto _p = tree.find(x) ;
	assert(!_p.isNull);
	assert(_p.i is 4) ;
	
	ret = tree.remove(_p) ;
	assert(ret) ;
	_p = tree.find(x) ;
	assert(_p.isNull);
	
}