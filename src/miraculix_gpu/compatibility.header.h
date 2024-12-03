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

#ifndef compatibility_header_h 
#define compatibility_header_h 1

#if defined STAND_ALONE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <err.h>
#else
#include <R.h>
#include <Rmath.h>
#include <Rinternals.h>
#endif

#endif
