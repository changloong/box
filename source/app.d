module box.app;

import box.core.memory;
import box.core.thread;
import box.core.buffer;
import box.container.rbtree;
import core.stdc.stdio;
import std.typecons ;

version(D_BetterC) {
	extern(C) int main() {
		test();
		return 0;
	}
} else {
	import core.runtime;
	import core.exception;
	import core.demangle;
	import core.stdc.stdio;
	import std.stdio;
	void main(){
		test();
	}
}

struct Node {
	int i ;
	
	this(int i) {
		this.i	= i ;
		printf("%s:%d this() id=%x\n", __FILE__.ptr, __LINE__, &this);
	}
	
	~this() {
		printf("%s:%d ~this(i=%d)  id=%x\n", __FILE__.ptr, __LINE__, i, &this);
	}
	
	int opCmp(Node o) {
		return o.i - i ;
	}
	
}

void test()()
{
	
	ubyte[1024] tmp;
	auto bu = Buffer(tmp[]) ;
	bu(`PI`)('=')(3.14125).putByte('\n')(`汉字`)(`4字节`d)(`双字节`w);
	printf("%s\n", bu.slice.ptr ) ;
	
	alias Tree = RedBlack!Node ;
	
	alias NodeT	= Box!(Node, BoxType.Clear | BoxType.List ) ; 
	
	auto n = NodeT.make(31) ;
	printf("x.count=%d, n.i=%d\n", n.getRefCount, n.i);
	auto x2 = n ;
	printf("n.count=%d\n", n.getRefCount);
	
	auto slice = NodeT.slice(5) ;
	
	printf("slice.length=%d\n", slice.length ) ;
	int i = 0 ;
	foreach( y ; slice ) {
		y.i = i++;
		printf("y.getIndex=%d, y.getRefCount=%d y.i=%d\n", y.getIndex, y.getRefCount, y.i) ;
	}
	
	auto s2 = NodeT.slice(2) ;
	slice ~= s2 ;
	
}
