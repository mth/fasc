#!/bin/sh

nim c -d:musl fasc.nim && strip --strip-all fasc
