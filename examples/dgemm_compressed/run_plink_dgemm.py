from __future__ import annotations

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


def main() -> None:
    args = parse_args()

    mx.set_library_path(args.library)
    mx.load_shared_library()
    mx.set_options(use_gpu=False, verbose=0)

    plink, freq, n_snps, n_indiv = mx.read_bed(args.bed, calc_freq=True)
    plink_transposed = mx.transpose_plink(plink, snps=n_snps, indiv=n_indiv)

    rng = np.random.default_rng(args.seed)
    B = np.asfortranarray(rng.standard_normal((n_snps, args.ncol), dtype=np.float64))

    with mx.init_compressed(plink, plink_transposed, n_snps, n_indiv, freq, max_ncol=args.ncol) as handle:
        C = mx.dgemm_compressed(handle, B, snps=n_snps, indiv=n_indiv, transpose=False)

    print(f"Read {n_snps} SNPs x {n_indiv} individuals from {args.bed}")
    print(f"Computed C = G * B with shape {C.shape}")
    print("First rows of C:")
    print(C[: min(5, C.shape[0]), : min(5, C.shape[1])])


if __name__ == "__main__":
    main()
