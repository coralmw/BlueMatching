# A literal space.
space :=
space +=

# Joins elements of the list in arg 2 with the given separator.
#   1. Element separator.
#   2. The list.
join-with = $(subst $(space),$1,$(strip $2))

BSINCLUDE=+
# BSINCLUDE+=/home/tparks/Projects/POETS/tinsel/rtl
# BSINCLUDE+=/home/tparks/Projects/POETS/BlueStuff
# BSINCLUDE+=/home/tparks/Projects/POETS/BlueStuff/BlueUtils
# BSINCLUDE+=/home/tparks/Projects/POETS/BlueStuff/BlueBasics
# BSINCLUDE+=/home/tparks/Projects/POETS/BlueStuff/AXI

BSC=bsc -p $(call join-with,:,$(BSINCLUDE)) -steps-max-intervals 1000000000

build/%.bo: %.bsv
	${BSC} -u --bdir build --vdir build $<


build/mk%.v: build/%.bo
	${BSC} -u --bdir build --vdir build -verilog -g mk$* $*.bsv

build/mk%.ba: %.bsv
	${BSC} -u --sim --bdir build --vdir build $<

# build/%_systemc.cxx: build/%.ba
# 	bsc -systemc --bdir build -simdir build -e mk$* build/mk$*.ba

build/sim: build/mkTestMatch.ba Match.bsv
	${BSC} -sim -e mkTestMatch -simdir build -keep-fires -o build/sim  build/mkTestMatch.ba

clean:
	rm -rf build/*
