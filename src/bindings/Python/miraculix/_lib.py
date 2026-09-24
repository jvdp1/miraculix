import ctypes
from pathlib import Path

import numpy as np


class MiraculixError(RuntimeError):
    pass


_LIBRARY_PATH = None
_LIBRARY_HANDLE = None


def _default_library_path() -> Path:
    return Path(__file__).resolve().parents[3] / "miraculix" / "miraculix.so"


def set_library_path(path: str | Path) -> None:
    global _LIBRARY_PATH

    resolved = Path(path).expanduser().resolve()
    if not resolved.is_file():
        raise FileNotFoundError(f"The specified library path does not exist: {resolved}")
    _LIBRARY_PATH = resolved


def get_library_path() -> Path:
    if _LIBRARY_PATH is None:
        raise MiraculixError("Library path not set. Call set_library_path() first.")
    return _LIBRARY_PATH


def load_shared_library(path: str | Path | None = None) -> ctypes.CDLL:
    global _LIBRARY_HANDLE

    if path is not None:
        set_library_path(path)
    elif _LIBRARY_PATH is None:
        default_path = _default_library_path()
        if default_path.is_file():
            set_library_path(default_path)
        else:
            raise MiraculixError(
                "Library path not set and default library path does not exist. "
                "Call set_library_path() with src/miraculix/miraculix.so."
            )

    _LIBRARY_HANDLE = ctypes.CDLL(str(get_library_path()))
    _configure_signatures(_LIBRARY_HANDLE)
    return _LIBRARY_HANDLE


def is_library_loaded() -> bool:
    return _LIBRARY_HANDLE is not None


def require_library() -> ctypes.CDLL:
    if _LIBRARY_HANDLE is None:
        raise MiraculixError("Shared library not loaded. Call load_shared_library() first.")
    return _LIBRARY_HANDLE


def close_shared_library() -> None:
    global _LIBRARY_HANDLE
    _LIBRARY_HANDLE = None


def _configure_signatures(lib: ctypes.CDLL) -> None:
    void_p = ctypes.c_void_p
    int_p = ctypes.POINTER(ctypes.c_int)
    void_pp = ctypes.POINTER(void_p)

    lib.setOptions_compressed.argtypes = [
        ctypes.c_int,
        ctypes.c_int,
        ctypes.c_int,
        ctypes.c_int,
        ctypes.c_int,
        ctypes.c_int,
        ctypes.c_int,
        ctypes.c_int,
        ctypes.c_int,
        ctypes.c_int,
    ]
    lib.setOptions_compressed.restype = None

    lib.plink2compressed.argtypes = [
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.c_int,
        ctypes.c_int,
        ctypes.POINTER(ctypes.c_double),
        ctypes.c_int,
        void_pp,
    ]
    lib.plink2compressed.restype = None

    lib.dgemm_compressed.argtypes = [
        ctypes.c_char_p,
        void_p,
        ctypes.c_int,
        ctypes.POINTER(ctypes.c_double),
        ctypes.c_int,
        ctypes.POINTER(ctypes.c_double),
        ctypes.c_int,
    ]
    lib.dgemm_compressed.restype = None

    lib.free_compressed.argtypes = [void_pp]
    lib.free_compressed.restype = None

    sparse2gpu = getattr(lib, "sparse2gpu", None)
    if sparse2gpu is not None:
        sparse2gpu.argtypes = [
            ctypes.POINTER(ctypes.c_double),
            ctypes.POINTER(ctypes.c_long),
            ctypes.POINTER(ctypes.c_long),
            ctypes.c_long,
            ctypes.c_long,
            ctypes.c_long,
            ctypes.c_int,
            void_pp,
            int_p,
        ]
        sparse2gpu.restype = None

    sparse_solve = getattr(lib, "dcsrtrsv_solve_gpu", None)
    if sparse_solve is not None:
        sparse_solve.argtypes = [
            void_p,
            ctypes.c_char,
            ctypes.POINTER(ctypes.c_double),
            ctypes.c_long,
            ctypes.POINTER(ctypes.c_double),
            int_p,
        ]
        sparse_solve.restype = None

    free_sparse = getattr(lib, "free_sparse_gpu", None)
    if free_sparse is not None:
        free_sparse.argtypes = [void_pp, int_p]
        free_sparse.restype = None

    dense_solve = getattr(lib, "potrs_solve_gpu", None)
    if dense_solve is not None:
        dense_solve.argtypes = [
            ctypes.POINTER(ctypes.c_double),
            ctypes.c_uint,
            ctypes.POINTER(ctypes.c_double),
            ctypes.c_uint,
            ctypes.POINTER(ctypes.c_double),
            ctypes.POINTER(ctypes.c_double),
            ctypes.c_int,
            int_p,
        ]
        dense_solve.restype = None


def require_symbol(name: str):
    lib = require_library()
    symbol = getattr(lib, name, None)
    if symbol is None:
        raise MiraculixError(
            f"The loaded library does not export '{name}'. "
            "This build may not include the requested GPU/solve functionality."
        )
    return symbol


def has_symbol(name: str) -> bool:
    lib = require_library()
    return getattr(lib, name, None) is not None


def has_cuda_solve_symbols() -> bool:
    return all(
        has_symbol(name)
        for name in ("sparse2gpu", "dcsrtrsv_solve_gpu", "free_sparse_gpu", "potrs_solve_gpu")
    )


def has_cuda_dgemm_support() -> bool:
    # The public dgemm entrypoint is shared between CPU and GPU modes.
    # In the current build layout, a CUDA-linked shared library also exports
    # the dedicated solve/GPU symbols, so reuse that as the capability signal.
    return has_cuda_solve_symbols()


def require_cuda_solve_support() -> None:
    if not has_cuda_solve_symbols():
        raise MiraculixError(
            "The loaded library does not include CUDA solve symbols. "
            "Build a CUDA-enabled miraculix.so before using sparse/dense GPU solve APIs."
        )


def require_cuda_dgemm_support() -> None:
    if not has_cuda_dgemm_support():
        raise MiraculixError(
            "The loaded library does not appear to be CUDA-enabled for dgemm_compressed. "
            "Build miraculix.so with CUDA support before calling set_options(use_gpu=True)."
        )


def require_numpy_matrix(array: np.ndarray, *, dtype, name: str, order: str = "F") -> np.ndarray:
    if not isinstance(array, np.ndarray):
        raise TypeError(f"{name} must be a numpy.ndarray")
    if array.ndim != 2:
        raise ValueError(f"{name} must be a 2D array")
    return np.array(array, dtype=dtype, order=order, copy=False)


def require_numpy_vector(array: np.ndarray, *, dtype, name: str) -> np.ndarray:
    if not isinstance(array, np.ndarray):
        raise TypeError(f"{name} must be a numpy.ndarray")
    if array.ndim != 1:
        raise ValueError(f"{name} must be a 1D array")
    return np.ascontiguousarray(array, dtype=dtype)


def matrix_pointer(array: np.ndarray, c_type):
    return array.ctypes.data_as(ctypes.POINTER(c_type))


def vector_pointer(array: np.ndarray, c_type):
    return array.ctypes.data_as(ctypes.POINTER(c_type))


def check_status(status: ctypes.c_int, routine: str) -> None:
    if status.value != 0:
        raise MiraculixError(f"{routine} failed with status {status.value}")
