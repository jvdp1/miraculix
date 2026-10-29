import argparse
import sys
import time
from pathlib import Path

import numpy as np

ROOT_DIR = Path(__file__).resolve().parents[2]
PYTHON_BINDING_DIR = ROOT_DIR / "src" / "bindings" / "Python"
sys.path.insert(0, str(PYTHON_BINDING_DIR))

import miraculix as mx


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Read PLINK .bed/.bim/.fam files and multiply the genotype matrix with a dense matrix."
    )
    parser.add_argument("bed", help="Path to the PLINK .bed file")
    parser.add_argument(
        "--library",
        default=str(ROOT_DIR / "src" / "miraculix" / "miraculix.so"),
        help="Path to miraculix.so",
    )
    parser.add_argument(
        "--gpu",
        action=argparse.BooleanOptionalAction,
        help="Test with NVIDIA GPU",
    )
    parser.add_argument(
        "--ncol",
        type=int,
        default=4,
        help="Number of columns in the dense matrix B",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=0,
        help="Random seed for generating the dense matrix B",
    )
    return parser.parse_args()


def header(C: np.ndarray) -> None:
    print(f"\nComputed C = G * B with shape {C.shape}")
    print("First rows of C:")
    print(C[: min(5, C.shape[0]), : min(5, C.shape[1])])


def gemm(
    seed: int,
    use_gpu: bool,
    plink: np.ndarray,
    freq: np.ndarray,
    n_snps: int,
    n_indiv: int,
    ncol: int,
) -> None:
    print("\nGEMM")

    plink_transposed = None
    if use_gpu:
        plink_transposed = mx.transpose_plink(plink, snps=n_snps, indiv=n_indiv)

    # Random matrix
    rng = np.random.default_rng(seed)
    B = np.asfortranarray(rng.standard_normal((n_snps, ncol), dtype=np.float64))

    # Miraculix computation
    handle = mx.init_compressed(
        plink, plink_transposed, n_snps, n_indiv, freq, max_ncol=ncol, use_gpu=use_gpu
    )

    start = time.perf_counter()
    C = mx.dgemm_compressed(handle, B, snps=n_snps, indiv=n_indiv, transpose=False)
    end = time.perf_counter()
    print(f"Miraculix: Wall clock time (s): {end - start:.6f}")

    handle.close()

    header(C)

    # Numpy computation
    geno = mx.decompress_bed(plink, n_indiv, n_snps)

    geno = geno - 2 * freq

    start = time.perf_counter()
    C_np = geno @ B
    end = time.perf_counter()
    print(f"Numpy: Wall clock time (s): {end - start:.6f}")

    header(C_np)

    # assert that C and C_np are equal
    assert np.allclose(C, C_np, rtol=1e-7, atol=1e-9)


def gemm_transposed(
    seed: int,
    use_gpu: bool,
    plink: np.ndarray,
    freq: np.ndarray,
    n_snps: int,
    n_indiv: int,
    ncol: int,
) -> None:
    print("\nGEMM_TRANSPOSED")

    plink_transposed = None
    if use_gpu:
        plink_transposed = mx.transpose_plink(plink, snps=n_snps, indiv=n_indiv)

    # Random matrix
    rng = np.random.default_rng(seed)
    B = np.asfortranarray(rng.standard_normal((n_indiv, ncol), dtype=np.float64))

    # Miraculix computation
    handle = mx.init_compressed(
        plink, plink_transposed, n_snps, n_indiv, freq, max_ncol=ncol, use_gpu=use_gpu
    )

    start = time.perf_counter()
    C = mx.dgemm_compressed(handle, B, snps=n_snps, indiv=n_indiv, transpose=True)
    end = time.perf_counter()
    print(f"Miraculix (t): Wall clock time (s): {end - start:.6f}")

    handle.close()

    header(C)

    # Numpy computation
    geno = mx.decompress_bed(plink, n_indiv, n_snps)

    geno = geno - 2 * freq

    start = time.perf_counter()
    C_np = geno.T @ B
    end = time.perf_counter()
    print(f"Numpy (t): Wall clock time (s): {end - start:.6f}")

    header(C_np)

    # assert that C and C_np are equal
    assert np.allclose(C, C_np, rtol=1e-7, atol=1e-9)


def loop_gemm(
    seed: int,
    use_gpu: bool,
    plink: np.ndarray,
    freq: np.ndarray,
    n_snps: int,
    n_indiv: int,
    ncol: int,
    niter: int = 10,
) -> None:
    print("\nLOOP_GEMM")

    plink_transposed = None
    if use_gpu:
        plink_transposed = mx.transpose_plink(plink, snps=n_snps, indiv=n_indiv)

    rng = np.random.default_rng(seed)

    handle = mx.init_compressed(
        plink, plink_transposed, n_snps, n_indiv, freq, max_ncol=ncol, use_gpu=use_gpu
    )

    # Numpy computation
    geno = mx.decompress_bed(plink, n_indiv, n_snps)
    geno = geno - 2 * freq

    # Warm-up
    # Random matrix
    B = np.asfortranarray(rng.standard_normal((n_snps, ncol), dtype=np.float64))

    # Miraculix computation
    C = mx.dgemm_compressed(handle, B, snps=n_snps, indiv=n_indiv, transpose=False)

    times_n = 0
    times_np_n = 0
    times_t = 0
    times_np_t = 0

    for iter in range(niter):
        # Random matrix
        B = np.asfortranarray(rng.standard_normal((n_snps, ncol), dtype=np.float64))

        # Miraculix computation
        start = time.perf_counter()
        C = mx.dgemm_compressed(handle, B, snps=n_snps, indiv=n_indiv, transpose=False)
        end = time.perf_counter()

        times_n += end - start

        # Numpy computation
        start = time.perf_counter()
        C_np = geno @ B
        end = time.perf_counter()

        times_np_n += end - start

        assert np.allclose(C, C_np, rtol=1e-7, atol=1e-9)

        # Random matrix
        Bt = np.asfortranarray(rng.standard_normal((n_indiv, ncol), dtype=np.float64))

        # Miraculix computation
        start = time.perf_counter()
        Ct = mx.dgemm_compressed(handle, Bt, snps=n_snps, indiv=n_indiv, transpose=True)
        end = time.perf_counter()

        times_t += end - start

        # Numpy computation
        start = time.perf_counter()
        C_np_t = geno.T @ Bt
        end = time.perf_counter()

        times_np_t += end - start

        assert np.allclose(Ct, C_np_t, rtol=1e-7, atol=1e-9)

    handle.close()

    print(f"Miraculix - N - average wall clock time: {times_n / niter}")
    print(f"Miraculix - T - average wall clock time: {times_t / niter}")

    print(f"Numpy - N - average wall clock time: {times_np_n / niter}")
    print(f"Numpy - T - average wall clock time: {times_np_t / niter}")


def main() -> None:
    args = parse_args()

    np.__config__.show()

    use_gpu = False
    if args.gpu:
        print("Test with NVIDIA GPU")
        use_gpu = True

    # Load Miraculix
    mx.set_library_path(args.library)
    mx.load_shared_library()
    mx.set_options(use_gpu=use_gpu, verbose=0)

    # Read Plink file
    plink, freq, n_snps, n_indiv = mx.read_bed(args.bed, calc_freq=True)

    print(f"Read {n_snps} SNPs x {n_indiv} individuals from {args.bed}")

    # test gemm
    gemm(args.seed, use_gpu, plink, freq, n_snps, n_indiv, args.ncol)

    # test gemm + transposed
    gemm_transposed(args.seed, use_gpu, plink, freq, n_snps, n_indiv, args.ncol)

    # Multiple gemm
    loop_gemm(args.seed, use_gpu, plink, freq, n_snps, n_indiv, args.ncol)


if __name__ == "__main__":
    main()
