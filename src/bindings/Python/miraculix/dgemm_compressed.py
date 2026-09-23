import ctypes

import numpy as np

from ._lib import (
    MiraculixError,
    check_status,
    matrix_pointer,
    require_library,
    require_numpy_matrix,
    require_numpy_vector,
)


class CompressedGenotypeHandle:
    def __init__(self, ptr: ctypes.c_void_p):
        self._ptr = ptr

    @property
    def ptr(self) -> ctypes.c_void_p:
        if self.closed:
            raise MiraculixError("Compressed genotype handle has already been freed.")
        return self._ptr

    @property
    def closed(self) -> bool:
        return not bool(self._ptr.value)

    def close(self) -> None:
        if self.closed:
            return
        lib = require_library()
        lib.free_compressed(ctypes.byref(self._ptr))

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        self.close()
        return False

    def __del__(self):
        try:
            self.close()
        except Exception:
            pass


def set_options(
    *,
    use_gpu: bool = False,
    cores: int = 0,
    not_center: bool = False,
    variant: int = 0,
    verbose: int = 1,
) -> None:
    lib = require_library()
    lib.setOptions_compressed(
        int(use_gpu),
        int(cores),
        0,
        0,
        1,
        int(not_center),
        0,
        0,
        int(variant),
        int(verbose),
    )


def init_compressed(
    plink: np.ndarray,
    plink_transposed: np.ndarray,
    snps: int,
    indiv: int,
    freq: np.ndarray,
    max_ncol: int,
) -> CompressedGenotypeHandle:
    lib = require_library()

    plink = require_numpy_matrix(plink, dtype=np.uint8, name="plink", order="F")
    plink_transposed = require_numpy_matrix(
        plink_transposed, dtype=np.uint8, name="plink_transposed", order="F"
    )
    freq = require_numpy_vector(freq, dtype=np.float64, name="freq")

    expected_plink_shape = ((indiv + 3) // 4, snps)
    expected_transposed_shape = ((snps + 3) // 4, indiv)
    if plink.shape != expected_plink_shape:
        raise ValueError(f"plink must have shape {expected_plink_shape}, got {plink.shape}")
    if plink_transposed.shape != expected_transposed_shape:
        raise ValueError(
            f"plink_transposed must have shape {expected_transposed_shape}, got {plink_transposed.shape}"
        )
    if freq.shape[0] != snps:
        raise ValueError(f"freq must have length {snps}, got {freq.shape[0]}")

    ptr = ctypes.c_void_p()
    lib.plink2compressed(
        matrix_pointer(plink, ctypes.c_uint8),
        matrix_pointer(plink_transposed, ctypes.c_uint8),
        int(snps),
        int(indiv),
        matrix_pointer(freq, ctypes.c_double),
        int(max_ncol),
        ctypes.byref(ptr),
    )
    if not ptr.value:
        raise MiraculixError("plink2compressed returned a null storage object.")
    return CompressedGenotypeHandle(ptr)


def dgemm_compressed(
    handle: CompressedGenotypeHandle,
    B: np.ndarray,
    *,
    snps: int,
    indiv: int,
    transpose: bool = False,
) -> np.ndarray:
    lib = require_library()
    B = require_numpy_matrix(B, dtype=np.float64, name="B", order="F")

    expected_rows = indiv if transpose else snps
    if B.shape[0] != expected_rows:
        raise ValueError(
            f"B must have {expected_rows} rows for transpose={transpose}, got {B.shape[0]}"
        )

    out_rows = snps if transpose else indiv
    C = np.zeros((out_rows, B.shape[1]), dtype=np.float64, order="F")
    trans = b"T" if transpose else b"N"
    lib.dgemm_compressed(
        trans,
        handle.ptr,
        int(B.shape[1]),
        matrix_pointer(B, ctypes.c_double),
        int(B.shape[0]),
        matrix_pointer(C, ctypes.c_double),
        int(C.shape[0]),
    )
    return C
