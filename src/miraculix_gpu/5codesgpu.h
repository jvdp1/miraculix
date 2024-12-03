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



#ifndef miraculix_5codes_H
#define miraculix_5codes_H 1

#if defined  basic_miraculix_H

#define ORIGBITSperFIVE 10 // 5 * 2bits

#endif



#ifdef __cplusplus
extern "C" {
#endif
  
  
  void setOptions5(int gpu, int cores, int floatprecision,
		   int meanV, int meanSubstract,		   
		   int missingsFully0,
		   int centered, int normalized,
		   int use_miraculix_freq, 
		   int variant, int print_details);
  void plinkToSxI(char *plink, char *plink_transposed, 
		  long snps, long indiv, // long OK
		  int coding,
		  double *f, 
		  int max_n,
		  void**compressed);
  void free5(void **compressed) ;
  void genoVector5api(void *SxI, double *V,
		      long repetV, long LdV, double *ans, long LdAns);// long OK
  void vectorGeno5api(void *SxI, double *V,
		      long repetV, long LdV, double *ans, long LdAns);// long OK
  
  void getFreq5(void *compressed,  double *f) ;

  void getStartedOptions();
  

  void vectorGenoPlinkApi(char *compressed,
			   int snps, 
			   int indiv,
			   double *f,
			   double *B,
			   int n,
			   int LdB,
			   double *C,
			   int Ldc);
    
  
  void check_started();
  void plink2compressed(char *plink, char *plink_transposed,
			int snps, int indiv,
			double *f, 
			int max_n,
			void**compressed);
  void dgemm_compressed(char *t, // transposed?,
			void *compressed,
			int n, // number of columns of the matrix B
			//			double *f,
			double *B,
			int Ldb, 
			double *C, int Ldc);
  void free_compressed(void **compressed) ;
  
  void free5(void **compressed);
  
//  void get_compressed_freq(void *compressed, double *f);
  
#ifdef __cplusplus
}
#endif


#endif
