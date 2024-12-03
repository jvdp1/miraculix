
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

#ifndef Miraculix_def_H
#define Miraculix_def_H 1

#define STAND_ALONE 1


// #define this_file this_file_in_miraculix

#define MIRACULIX_VERSION 10

#define MaxUnitsPerAddress 2U // OK
#define MY_LDABITALIGN_2BIT 512U
#define MY_LDABITALIGN_ONEBYTE 256U
#define MY_LDABITALIGN_PLINK 256U
#define MAX_LDABITALIGN 512U


#if defined MY_VARIANT && ! defined MY_LDABITALIGN
#if MY_VARIANT ==  32
#define PlainInteger32 1
#define NO_SSE2 1
#elif MY_VARIANT ==  64
#define PlainInteger64 1
#define NO_SSE2 1
#elif MY_VARIANT == 128 
#define NO_AVX 1
#elif MY_VARIANT == 256
#define NO_AVX512 1
#elif MY_VARIANT == 512
#else
#error unknown MY_VARIANT
#endif
#endif


#if defined BitsPerCode && ! defined MY_CODING
#if BitsPerCode == 1
#define MY_CODING OneBitGeno
#define MY_LDABITALIGN MY_LDABITALIGN_2BIT
#elif BitsPerCode ==  2
#define MY_CODING TwoBitGeno
#define MY_LDABITALIGN MY_LDABITALIGN_2BIT
#elif BitsPerCode ==  3
#define MY_CODING ThreeBit
#elif BitsPerCode ==  8
#define MY_CODING OneByteGeno
#define MY_LDABITALIGN MY_LDABITALIGN_ONEBYTE
#elif BitsPerCode == 32
#define MY_CODING FourByteGeno
#define MY_LDABITALIGN 32 
#else
#error unknown BitsPerCode
#endif
#endif


#define INTEGERX INTEGER

extern bool debugging;


#endif
