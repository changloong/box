module box.app;

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


void test()()
{
	
}
