
CUDA=true
COMPILER=gcc

ifeq ($(COMPILER), gcc)
 FORTRAN=gfortran
 FFLAGS=-O3 -ftree-vectorize -mtune=native -march=native 
 FFLAGS+=-cpp -fopenmp 
 LDFLAGS=-lgfortran -lm -fopenmp -lstdc++

else ifeq ($(COMPILER), intel)
 FORTRAN=ifort
 FFLAGS=-O3 -mavx2 -mtune=native -march=native
 FFLAGS+=-I${MKLROOT}/include -I${MKLROOT}/include/intel64/lp64 -L${MKLROOT}/lib/intel64
 FFLAGS+=-fpp -qopenmp -qopt-matmul
 LDFLAGS=-liomp5 -lmkl_blas95_lp64 -lmkl_lapack95_lp64 -lmkl_intel_lp64 -lmkl_intel_thread -lmkl_core  -lpthread -lm -ldl -lstdc++

endif

SRC_DIR=$(PWD)/../../src
FFLAGS+=-I$(SRC_DIR)/bindings/Fortran
LDFLAGS+=-L$(SRC_DIR)/miraculix_gpu -L$(SRC_DIR)/bindings/Fortran -L$(SRC_DIR)/cuda
LDFLAGS+= -Wl,-rpath=$(SRC_DIR)/miraculix_gpu -Wl,-rpath=$(SRC_DIR)/bindings/Fortran -Wl,-rpath=$(SRC_DIR)/cuda 
LDFLAGS+=-lmiraculix -lfortran 


ifeq ($(CUDA), true)
LDFLAGS+=-L${CUDA_HOME}/lib64  -ldgemm_compressed_cuda -lcuda -lcudart -lcublas -lcusolver -lcusparse -lcusolver -lstdc++
FFLAGS+=-DCUDA
endif


OBJ = $(SRC:.f90=.o)
MODS = $(OBJ:.o=.mod)

LIBFORTRAN = $(SRC_DIR)/bindings/Fortran/libfortran.a
LIBMIRACULIX = $(SRC_DIR)/miraculix_gpu/libmiraculix.a

EXE = test_5codesapi
EXET = test_5codesapi_t



all: $(EXE) $(EXET)


$(EXE): $(EXE).o $(LIBMIRACULIX) $(LIBFORTRAN)
	$(FORTRAN) $(FFLAGS) $(EXE).o -o $@ $(LDFLAGS) 

$(EXET): $(EXET).o $(LIBMIRACULIX) $(LIBFORTRAN)
	$(FORTRAN) $(FFLAGS) $(EXET).o -o $@ $(LDFLAGS)

%.o: %.f90
	$(FORTRAN) $(FFLAGS) -c $<

$(EXE).o: $(LIBFORTRAN)
$(EXET).o: $(LIBFORTRAN)

clean:
	$(RM) $(OBJ) $(MODS) $(LIB) $(EXE) $(EXET) $(ALL) *.optrpt

tests: all
	./$(EXE) ../data/small.bed ../data/small.freq

testm: all
	./$(EXE) ../data/medium.bed ../data/medium.freq


testl: all
	./$(EXE) ../data/large.bed ../data/large.freq


testt: all  
	./$(EXET) ../data/small.bed ../data/small.freq


vtest: all
	valgrind --tool=memcheck --leak-check=full --num-callers=20 ./$(EXE) data/small.bed data/small.freq


vtestt: all
	valgrind --tool=memcheck --leak-check=full --num-callers=20 ./$(EXET) data/small.bed data/small.freq
