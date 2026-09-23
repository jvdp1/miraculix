## Python interfaces to miraculix

This directory contains a source-only Python binding for the existing `miraculix.so` C ABI.

### Scope

The Python binding intentionally stays low-level in its first version:
- compressed genotype matrix multiplication
- sparse GPU solve wrappers
- dense GPU solve wrapper

It does not currently provide Julia-style higher-level helpers such as GRM/LD workflows.

### Usage

Build `src/miraculix/miraculix.so` first, then point the Python module at it explicitly:

```python
import numpy as np
import miraculix as mx

mx.set_library_path("/path/to/src/miraculix/miraculix.so")
mx.load_shared_library()
mx.set_options(use_gpu=False, verbose=0)
```

The wrappers expect:
- packed genotype matrices as PLINK `.bed`-coded `numpy.uint8`
- dense matrices and frequencies as `numpy.float64`
- sparse COO indices as `numpy.int64`

### Development

To import from source, add `src/bindings/Python` to `PYTHONPATH`.
