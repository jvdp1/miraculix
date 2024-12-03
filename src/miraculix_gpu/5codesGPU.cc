
/*
 Authors 
 Martin Schlather, martin.schlather@uni-mannheim.de

 Copyright (C) 2022-2023 Martin Schlather

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
*/

//#include "Basic_miraculix.h"
#ifndef basic_miraculix_H

#define basic_miraculix_H 1

#include "def.h"
#include "compatibility.general.h"

#endif


#include "5codesgpu.h"
#include "GPUapi.h"


#if !defined CUDA
void plink2gpu(char VARIABLE_IS_NOT_USED  *plink, // including three-byte
	       // header, size in bytes: ceiling(indiv/4) * snps + 3
    char VARIABLE_IS_NOT_USED *plink_transposed, // @JV: If I remember correctly, you need to
                            // transpose the matrix anyway? so it should be
                            // easier to have this as an argument, and not
                            // transpose it again on the GPU
    int VARIABLE_IS_NOT_USED snps,
    int VARIABLE_IS_NOT_USED indiv, // actual number of individuals, not N/4 rounded up
	       double VARIABLE_IS_NOT_USED *f,  // vector guaranteed to be of length  dsnps
    int VARIABLE_IS_NOT_USED n, 
    void VARIABLE_IS_NOT_USED **GPU_obj) {
  BUG;
    }
void dgemm_compressed_gpu(
    bool VARIABLE_IS_NOT_USED trans, //
    void VARIABLE_IS_NOT_USED *GPU_obj,
    //    double *f,
    int VARIABLE_IS_NOT_USED n,     // number of columns of matrix B
    double VARIABLE_IS_NOT_USED *B,  // matrix of dimensions (nsnps, n) if trans =
                // "N" and (nindiv,n) if trans = "T"
    int VARIABLE_IS_NOT_USED ldb,
    int VARIABLE_IS_NOT_USED centered,
    int VARIABLE_IS_NOT_USED normalized,
    double VARIABLE_IS_NOT_USED *C,
    int VARIABLE_IS_NOT_USED ldc
			  ) {
  BUG;
}
void freegpu(void VARIABLE_IS_NOT_USED **GPU_obj){
  BUG;
}
#endif

		   
void plinkToSxI(char *plink, char *plink_tr, 
	      Long snps, Long indiv,
	      int Coding,
	      double *f, 
	      int max_n,
	      void**compressed) {

    plink2gpu((char*) plink, (char*) plink_tr, (int) snps, (int) indiv, f,
	      max_n, compressed);

    return;
}


void vectorGeno5api(void *compressed, double *V, Long repetV, Long LdV, 
		    double *ans, Long LdAns) {
   dgemm_compressed_gpu(false, compressed, (int) repetV, V, (int) LdV,
			 1,
			 0,
			ans, (int) LdAns);
}


void genoVector5api(void *compressed, double *V, Long repetV, Long LdV, 
		 double *ans, Long LdAns) {

      dgemm_compressed_gpu(true, compressed, (int) repetV, V, (int) LdV, 
			 1,
			 0,
			   ans, (int) LdAns);
} 



void free5(void **compressed) {
    freegpu(compressed);
}


