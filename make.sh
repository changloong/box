#!/usr/bin/env bash
if [ "$(uname)" == "Darwin" ]; then
    DFLAGS="-L-dead_strip"
else
    DFLAGS="-L--gc-sections"
fi

dmd -betterC source/app.d source/box/core/*.d source/box/container/*.d -L-luv -I~/.projects/d/libuv/ -L-lpthread $DFLAGS $*

if [ $? -ne 0 ]; then
	exit
fi

if [ -x "./app" ]; then
	./app
fi


# -release -O -inline -boundscheck=off
