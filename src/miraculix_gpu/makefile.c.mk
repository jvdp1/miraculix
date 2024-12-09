
# compilation flags
ifeq ($(COMPILER), gcc)
CC=g++
Ccompiler=gcc
FORTRAN=gfortran
CFLAGS=-I/usr/local/include -O2 $(DEBUGGING_FLAG) 
CCFLAGS=-I/usr/local/include -O2 -fopenmp -pthread $(DEBUGGING_FLAG)
FFLAGS=-O2 
LINK_FLAGS=-llapack -lblas -lgfortran -lm -lquadmath -fopenmp




SSSE3_FLAG=-mssse3 
SSE41_FLAG=-msse4.1 
AVX_FLAG=-mavx
#AVX2_FLAG=-mavx2 
AVX2_FLAG=-mavx2
AVX512_FLAG=-mavx512 
MAX_AVX512_FLAG=-mavx512
LINKER=-std=gnu++14 -L/usr/local/lib -L/usr/lib64

else ifeq ($(COMPILER), intel)

CC=icc
Ccompiler=icc
FORTRAN=ifort
CFLAGS=-O2 -diag-disable=10441 $(DEBUGGING_FLAG) 
CCFLAGS=-O2 -qopenmp -parallel -pthread -diag-disable=10441 $(DEBUGGING_FLAG)
FFLAGS=-O2 
FFLAGS+=-I${MKLROOT}/include -I${MKLROOT}/include/intel64/lp64 -L${MKLROOT}/lib/intel64
LINK_FLAGS=-liomp5 -lmkl_blas95_lp64 -lmkl_lapack95_lp64 -lmkl_intel_lp64 -lmkl_intel_thread -lmkl_core  -lpthread -lm -ldl

SSSE3_FLAG=-xSSSE3
SSE41_FLAG=-xSSE4.1
AVX_FLAG=-xAVX
AVX2_FLAG=-xCORE-AVX2
AVX512_FLAG=-xCOMMON-AVX512
MAX_AVX512_FLAG=-xCORE-AVX512
LINKER=-std=gnu++14

else ifeq ($(COMPILER), clang)

CC=clang++
Ccompiler=clang
FORTRAN=gfortran
SANITIZE_FLAGS=-fsanitize=undefined -fsanitize=integer -fsanitize=address -fno-sanitize=float-divide-by-zero -fno-sanitize=alignment -fno-omit-frame-pointer -frtti
SANITIZE_FLAGS=-fsanitize=address -fno-sanitize=alignment
CFLAGS=-I/usr/local/include -O2 $(DEBUGGING_FLAG) $(SANITIZE_FLAGS)
CCFLAGS=-I/usr/local/include -O2 -fopenmp -pthread $(DEBUGGING_FLAG) $(SANITIZE_FLAGS)
FFLAGS=-O2 
LINK_FLAGS=-llapack -lblas -lgfortran -lm -lquadmath -fopenmp -lasan -L /usr/local/lib 

CCFLAGS+   format -Wformat-security -Wformat-y2k -Wuninitialized -Wall -Wextra -Wshadow -Wpointer-arith -pedantic -Wswitch-default -march=native -Wno-unused-variable -Wno-unused-function -mtune=native -Wno-ignored-attributes -Wno-deprecated-declarations -Wno-parentheses  -Wformat-overflow=2

CCFLAGS+=-g  -pipe


SSSE3_FLAG=-mssse3  
AVX_FLAG=-mavx
#AVX2_FLAG=-mavx2 
AVX2_FLAG=-mavx2
AVX512_FLAG=-mavx512 
MAX_AVX512_FLAG=-mavx512
LINKER=-std=gnu++14 -L/usr/local/lib -L/usr/lib64


endif




# Flags for internal purposes
PURPOSE_FLAG=-DREQUIRED_SIMD=2 -DLINUXCPUID


MY_CC_FILES=5codesGPU.o
MY_C_FILES=5codesAPI.o


ALL_CC:=$(MY_CC_FILES)
ALL_C:=$(MY_C_FILES)

ALL:=$(ALL_CC) $(ALL_C)


alle : msg $(ALL)

allparallel : msg_parallel msg do_parallel Main

msg_parallel :
	echo ******** PARALLEL ******** 

msg :
	@echo ""
	@echo SRC=$(SRC)


%.o: $(SRC)/%.cc
	$(CC) -c $< -o $@ $(CCFLAGS)

%.o: $(SRC)/%.c
	$(Ccompiler) -c $< -o $@ $(CFLAGS)



Main: 
	$(CC) $(LINKER) -o run_$(COMPILER) $(ALL) $(LINK_FLAGS)


cleaner:
	rm *.o

