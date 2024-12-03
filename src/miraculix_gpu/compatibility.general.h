
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


#ifndef compatibility_general_h 
#define compatibility_general_h 1

#ifndef __cplusplus
#include <stdbool.h>
#endif


#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <err.h>

#include <inttypes.h>

typedef unsigned int Uint;
typedef uint64_t Ulong;
typedef int64_t Long;
typedef unsigned char Uchar;

void stopIfNotIntI(Long i, Long line, const char *file);
#define stopIfNotInt(i) stopIfNotIntI(i, __LINE__, __FILE__);

void stopIfNotUIntI(Long i, Long line, const char *file);
#define stopIfNotUInt(i) stopIfNotUIntI(i, __LINE__, __FILE__);

void stopIfNotAnyIntI(Long i, Long line, const char *file);
#define stopIfNotAnyInt(i) stopIfNotAnyIntI(i, __LINE__, __FILE__);

#define stopIfNotSame(i,j)\
  if (sizeof(i) != sizeof(j)) { ERR6("'%s' (%ld) and '%s' (%ld) do not have the same size at line %d in '%s'\n", #i, sizeof(i), #j, sizeof(j), __LINE__, __FILE__) }


typedef long double LongDouble;

#endif
