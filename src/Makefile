OBJECTS=miraculixjl.so
CUOBJECTS=$(patsubst %.cu,%.o,$(wildcard *.cu))
CUOBJECTS+= mmagpu.o 
CUSTANDALONE=test.cu   #matvec_u8x4f64.cu
CUTEST=test.cu

MMAGPU_FILE=../paper_miraculix/miraculix/src/mmagpu.cu
CUTLASS_PATH=./cutlass/include/
CUTLASS_UTILS=./cutlass/tools/util/include

cu_nums= 70 75 80 90 90a
CU_NUMS=$(subst $() $(),;,$(cu_nums))
CU_FLAGS=$(foreach i,$(cu_nums),--generate-code arch=compute_$(i),code=sm_$(i)) -DCUTLASS_NVCC_ARCHS='$(CU_NUMS)' 


NVCC=nvcc
CXXFLAGS=$(CU_FLAGS) -Xcompiler --std=c++17 -Xcompiler -fopenmp  -Xcompiler -fPIC -Xcompiler -g -x cu -DDO_PARALLEL -DJULIA_COMPILE -I$(CUTLASS_PATH) -I$(CUTLASS_UTILS) -I./ -DCOMMIT_ID=\"$(shell git rev-parse --short HEAD)\" 
LIBS=-L${CUDA_HOME}/lib64 -lcudart -lcublas -lcusolver -lcusparse -lcusolver  -Xcompiler -fopenmp

ifdef MKLINCLUDE
CXXFLAGS+=-I$(MKLINCLUDE) -DMKL -I$(MKLROOT)
LIBS+=-L$(MKL_LIB_DIR) -L$(MKL_LIB_COM) -lm -lmkl_intel_lp64 -lmkl_core -lmkl_gnu_thread -lpthread -liomp5 -ldl
endif

.PHONY: all
all: libmiraculixGPU libfortran #$(OBJECTS)

%.o: %.cu 
	$(NVCC) $(CXXFLAGS) -c $< -o $@

.PHONY: solve
solve: solve_gpu.cu cuda_utils.cu
	$(NVCC) $(CXXFLAGS) $(LIBS) --shared $^ -o solve_gpu.so

.PHONY: libmiraculix
libmiraculix:
	cp Makefile_miraculix ./miraculix/Makefile
	cd miraculix && make lib

.PHONY: standalone
standalone: $(CUSTANDALONE)
	$(NVCC) -Xcompiler -w -DSTANDALONE -I./cuda  -L./cuda $(CXXFLAGS) $(LIBS) -ldgemm_compressed_cuda $^ -o ./main.o

.PHONY: libdgemm
libmiraculixGPU:
	cd miraculix_gpu && make lib
	cd cuda && make lib

.PHONY: libfortran
libfortran:
	cd bindings/Fortran && make lib

.PHONY: clean
clean:
	$(RM) $(OBJECTS) $(CUOBJECTS) *.a *.out *.o 
	$(RM) miraculix/*.o miraculix/*.a
	$(RM) miraculix_gpu/*.o miraculix_gpu/*.a
	$(RM) cuda/*.o cuda/*.a
	$(MAKE) --directory=bindings/Fortran clean
