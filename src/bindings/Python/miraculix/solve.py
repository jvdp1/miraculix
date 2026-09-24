import ctypes

import numpy as np

from ._lib import (
    MiraculixError,
    check_status,
    matrix_pointer,
    require_library,
    require_cuda_solve_support,
    require_numpy_matrix,
    require_numpy_vector,
    require_symbol,
    vector_pointer,
)


class SparseSolveHandle:
    def __init__(self, ptr: ctypes.c_void_p):
        self._ptr = ptr

    @property
    def ptr(self) -> ctypes.c_void_p:
        if self.closed:
            raise MiraculixError("Sparse solve handle has already been freed.")
        return self._ptr

    @property
    def closed(self) -> bool:
        return not bool(self._ptr.value)

    def close(self) -> None:
        if self.closed:
            return
        lib = require_library()
        require_cuda_solve_support()
        require_symbol("free_sparse_gpu")
        status = ctypes.c_int(0)
        lib.free_sparse_gpu(ctypes.byref(self._ptr), ctypes.byref(status))
        check_status(status, "free_sparse_gpu")

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


def sparse_init(
    V: np.ndarray,
    I: np.ndarray,
    J: np.ndarray,
    *,
    nnz: int,
    m: int,
    max_ncol: int,
    is_lower: bool,
) -> SparseSolveHandle:
    lib = require_library()
    require_cuda_solve_support()
    require_symbol("sparse2gpu")
    V = require_numpy_vector(V, dtype=np.float64, name="V")
    I = require_numpy_vector(I, dtype=np.int64, name="I")
    J = require_numpy_vector(J, dtype=np.int64, name="J")

    if len(V) != nnz or len(I) != nnz or len(J) != nnz:
        raise ValueError("V, I, and J must all have length nnz")

    ptr = ctypes.c_void_p()
    status = ctypes.c_int(0)
    lib.sparse2gpu(
        vector_pointer(V, ctypes.c_double),
        vector_pointer(I, ctypes.c_long),
        vector_pointer(J, ctypes.c_long),
        int(nnz),
        int(m),
        int(max_ncol),
        int(is_lower),
        ctypes.byref(ptr),
        ctypes.byref(status),
    )
    check_status(status, "sparse2gpu")
    if not ptr.value:
        raise MiraculixError("sparse2gpu returned a null storage object.")
    return SparseSolveHandle(ptr)


def sparse_solve(handle: SparseSolveHandle, transA: str, B: np.ndarray, *, m: int) -> np.ndarray:
    lib = require_library()
    require_cuda_solve_support()
    require_symbol("dcsrtrsv_solve_gpu")
    if transA not in {"n", "N", "t", "T"}:
        raise ValueError("transA must be one of 'n', 'N', 't', or 'T'")

    B = require_numpy_matrix(B, dtype=np.float64, name="B", order="C")
    if B.shape[0] != m:
        raise ValueError(f"B must have {m} rows, got {B.shape[0]}")

    X = np.zeros_like(B, order="C")
    status = ctypes.c_int(0)
    lib.dcsrtrsv_solve_gpu(
        handle.ptr,
        transA.encode("ascii")[0:1],
        matrix_pointer(B, ctypes.c_double),
        int(B.shape[1]),
        matrix_pointer(X, ctypes.c_double),
        ctypes.byref(status),
    )
    check_status(status, "dcsrtrsv_solve_gpu")
    return X


def dense_solve(
    M: np.ndarray,
    B: np.ndarray,
    *,
    calc_logdet: bool = True,
    oversubscribe: bool = False,
):
    lib = require_library()
    require_cuda_solve_support()
    require_symbol("potrs_solve_gpu")
    M = require_numpy_matrix(M, dtype=np.float64, name="M", order="C")
    B = require_numpy_matrix(B, dtype=np.float64, name="B", order="C")

    if M.shape[0] != M.shape[1]:
        raise ValueError("M must be square")
    if B.shape[0] != M.shape[0]:
        raise ValueError("B must have the same row count as M")

    X = np.zeros_like(B, order="C")
    status = ctypes.c_int(0)
    logdet = ctypes.c_double(0.0)
    logdet_ptr = ctypes.byref(logdet) if calc_logdet else None

    lib.potrs_solve_gpu(
        matrix_pointer(M, ctypes.c_double),
        int(M.shape[0]),
        matrix_pointer(B, ctypes.c_double),
        int(B.shape[1]),
        matrix_pointer(X, ctypes.c_double),
        logdet_ptr,
        int(oversubscribe),
        ctypes.byref(status),
    )
    check_status(status, "potrs_solve_gpu")

    if calc_logdet:
        return X, logdet.value
    return X
