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


#include <stdio.h>
#include <stdlib.h>
#include "5codesAPI.h"


// if value unknown set it to 0.
void setOptions_compressed(int use_gpu, // 0 == use CPU
			   int cores,   // 0 == use global env
			   int floatLoop, // 0 == use doubles
			   int meanSubstract, // 1 == increase numerical precis.
			   int ignore_missings,// 0==respect missings (untested)
			   int do_not_center, // 0 == do centering
			   int do_normalize,  // 0 == do not normalize
			   int use_miraculix_freq, // 0==use Fortran freq 
			   int variant,  // 0 == use internal {0,32,128,256}
			   int print_details) {//1 == get some messages

    printf("get started\n");
    printf("GPU setting options in setOptions_compressed\n");
}


int is(char *trans) {
  if (*trans == 'T' || *trans == 't' || *trans == 'Y' || *trans =='y') return 1;
  if (*trans != 'N' && *trans != 'n') exit(99);
  return 0;
}


void plink2compressed(char *plink,
                      char *plink_transposed, 
		      int snps, int indiv,
                      double *f, 
                      int max_n,
		      void**compressed) {
  plinkToSxI(plink, plink_transposed, snps, indiv, f, max_n, compressed);
  return; 
}

void dgemm_compressed(char *trans, // 'N', 'T'
                      void *compressed,
                      int n, // number of columns of the matrix B
                      double *B,	
                      int Ldb, // how should it be size_t ldb
                      double *C, int Ldc) {

  if (is(trans))
    genoVector5api(compressed, B, n, Ldb, C, Ldc);
  else
    vectorGeno5api(compressed, B, n, Ldb, C, Ldc);
  return;
}



void free_compressed(void **compressed){
   free5(compressed);
}

  
