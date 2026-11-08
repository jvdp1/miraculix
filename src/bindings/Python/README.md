## Python interfaces to miraculix

This directory contains a source-only Python binding for the existing `miraculix.so` C ABI.

### Scope

The Python binding intentionally stays low-level in its first version:
- compressed genotype matrix multiplication

It does not currently provide Julia-style higher-level helpers such as GRM/LD workflows.

### Usage

Build `src/miraculix/miraculix.so` first with CUDA support configured (`CUDA_HOME`), then point the Python module at it explicitly:

```sh
make -C src shared_lib
```

```python
import numpy as np
import miraculix as mx

mx.set_library_path("/path/to/src/miraculix/miraculix.so")
mx.load_shared_library()
mx.set_options(use_gpu=True, verbose=0)
```

The wrappers expect:
- packed genotype matrices as PLINK `.bed`-coded `numpy.uint8`
- dense matrices and frequencies as `numpy.float64`

PLINK BED file reading, genotype decoding, and transpose can be used without a
GPU. The compressed GEMM API supports both CPU and NVIDIA GPU execution. GPU
GEMM requires a CUDA-enabled library build and an NVIDIA GPU.

### Development

To import from source, add `src/bindings/Python` to `PYTHONPATH`. NumPy is
required; Numba is an optional acceleration for packed genotype transposition.
