
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

#ifndef basic_miraculix_H

#define basic_miraculix_H 1

#include "def.h"
#include "compatibility.general.h"

#endif


#include "5codesgpu.h"
#include "GPUapi.h"

void plinkToSxI(char *plink, char *plink_tr, 
	      Long snps, Long indiv,
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


