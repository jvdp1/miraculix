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

  
  void plinkToSxI(char *plink, char *plink_transposed, 
		  long snps, long indiv, // long OK
		  double *f, 
		  int max_n,
		  void**compressed);
  void genoVector5api(void *SxI, double *V,
		      long repetV, long LdV, double *ans, long LdAns);// long OK
  void vectorGeno5api(void *SxI, double *V,
		      long repetV, long LdV, double *ans, long LdAns);// long OK
  
  void free5(void **compressed);
  
