CUDA=true
COMPILER=intel

SRC=./

ifeq ($(COMPILER), gcc)
 CC=g++
 CCOMPILER=gcc
 CFLAGS=-I/usr/local/include -O2 $(DEBUGGING_FLAG) -mtune=native -march=native
 CCFLAGS=-I/usr/local/include -O2 -fopenmp -pthread $(DEBUGGING_FLAG) -mtune=native -march=native

else ifeq ($(COMPILER), intel)

 CC=icc
 CCOMPILER=icc
 CFLAGS=-O2 -diag-disable=10441 $(DEBUGGING_FLAG) 
 CCFLAGS=-O2 -qopenmp -parallel -pthread -diag-disable=10441 $(DEBUGGING_FLAG)

endif


LIB = libmiraculix.a


ifeq ($(CUDA), true)
CCFLAGS+=-DCUDA # Indicates that CUDA functions need to be linked 
FFLAGS+=-DCUDA
LINK=g++
endif

lib: $(LIB)

ALL:=5codesgpu.o 5codesAPI.o

alle : $(ALL)

%.o: $(SRC)/%.cc
	$(CC) -c $< -o $@ $(CCFLAGS)

%.o: $(SRC)/%.c
	$(CCOMPILER) -c $< -o $@ $(CFLAGS)

$(LIB): $(ALL)
	ar cr $@ $(ALL)



.PHONY: clean lib
clean: 
	rm *.o
