import argparse
import sys
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
    print(f"Computed C = G * B with shape {C.shape}")
    print("First rows of C:")
    print(C[: min(5, C.shape[0]), : min(5, C.shape[1])])

def gemm(seed: int, plink: np.ndarray, freq: np.ndarray, n_snps: int, n_indiv: int, ncol: int) -> None:
    #plink_transposed = mx.transpose_plink(plink, snps=n_snps, indiv=n_indiv)

    # Random matrix
    rng = np.random.default_rng(seed)
    B = np.asfortranarray(rng.standard_normal((n_snps, ncol), dtype=np.float64))

    # Miraculix computation
    handle = mx.init_compressed(plink, None, n_snps, n_indiv, freq, max_ncol=ncol, lgpu=False)

    C = mx.dgemm_compressed(handle, B, snps=n_snps, indiv=n_indiv, transpose=False)

    handle.close()

    header(C)

    # Numpy computation
    geno = mx.decompress_bed(plink, n_indiv, n_snps)

    geno = geno - 2 * freq

    C_np = geno @ B

    header(C_np)

    # assert that C and C_np are equal
    assert np.allclose(C, C_np, rtol=1e-7, atol=1e-9)

def gemm_transposed(seed: int, plink: np.ndarray, freq: np.ndarray, n_snps: int, n_indiv: int, ncol: int) -> None:
    #plink_transposed = mx.transpose_plink(plink, snps=n_snps, indiv=n_indiv)

    # Random matrix
    rng = np.random.default_rng(seed)
    B = np.asfortranarray(rng.standard_normal((n_indiv, ncol), dtype=np.float64))

    # Miraculix computation
    handle = mx.init_compressed(plink, None, n_snps, n_indiv, freq, max_ncol=ncol, lgpu=False)

    C = mx.dgemm_compressed(handle, B, snps=n_snps, indiv=n_indiv, transpose=True)

    handle.close()

    header(C)

    # Numpy computation
    geno = mx.decompress_bed(plink, n_indiv, n_snps)

    geno = geno - 2 * freq

    C_np = geno.T @ B

    header(C_np)

    # assert that C and C_np are equal
    assert np.allclose(C, C_np, rtol=1e-7, atol=1e-9)


def main() -> None:
    args = parse_args()

    # Load Miraculix
    mx.set_library_path(args.library)
    mx.load_shared_library()
    mx.set_options(use_gpu=False, verbose=0)

    # Read Plink file
    plink, freq, n_snps, n_indiv = mx.read_bed(args.bed, calc_freq=True)

    print(f"Read {n_snps} SNPs x {n_indiv} individuals from {args.bed}")


    # test gemm
    gemm(args.seed, plink, freq, n_snps, n_indiv, args.ncol)

    # test gemm + transposed
    gemm_transposed(args.seed, plink, freq, n_snps, n_indiv, args.ncol)


if __name__ == "__main__":
    main()
