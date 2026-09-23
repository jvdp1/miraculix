from pathlib import Path

import numpy as np


_BED_HEADER = bytes((0x6C, 0x1B, 0x01))


def _require_plink_triplet(bed_path: Path) -> tuple[Path, Path, Path]:
    if bed_path.suffix != ".bed":
        raise ValueError(f"Expected a .bed file, got: {bed_path}")
    fam_path = bed_path.with_suffix(".fam")
    bim_path = bed_path.with_suffix(".bim")
    if not fam_path.is_file() or not bim_path.is_file():
        raise FileNotFoundError(f"Missing supplementary PLINK files for {bed_path}")
    return bed_path, bim_path, fam_path


def _count_lines(path: Path) -> int:
    with path.open("r", encoding="utf-8") as handle:
        return sum(1 for line in handle if line.strip())


def read_bed(path: str | Path, *, calc_freq: bool = True) -> tuple[np.ndarray, np.ndarray | None, int, int]:
    bed_path = Path(path).expanduser().resolve()
    bed_path, bim_path, fam_path = _require_plink_triplet(bed_path)

    n_indiv = _count_lines(fam_path)
    n_snps = _count_lines(bim_path)
    n_bytes_per_col = (n_indiv + 3) // 4

    with bed_path.open("rb") as handle:
        header = handle.read(3)
        if header != _BED_HEADER:
            raise ValueError(f"Not a SNP-major PLINK .bed file: {bed_path}")
        raw = handle.read()

    expected = n_snps * n_bytes_per_col
    if len(raw) != expected:
        raise ValueError(
            f"Unexpected .bed size for {bed_path}: expected {expected} payload bytes, got {len(raw)}"
        )

    plink = np.frombuffer(raw, dtype=np.uint8).reshape((n_snps, n_bytes_per_col)).T.copy(order="F")

    freq = None
    if calc_freq:
        bit_counts = np.unpackbits(plink, axis=0, bitorder="little").sum(axis=0)
        freq = bit_counts.astype(np.float64) / (2.0 * n_indiv)

    return plink, freq, n_snps, n_indiv


def transpose_plink(plink: np.ndarray, *, snps: int, indiv: int) -> np.ndarray:
    expected_shape = ((indiv + 3) // 4, snps)
    if plink.shape != expected_shape:
        raise ValueError(f"plink must have shape {expected_shape}, got {plink.shape}")

    plink_transposed = np.zeros(((snps + 3) // 4, indiv), dtype=np.uint8, order="F")
    for snp_group in range(0, snps, 4):
        for indiv_group in range(0, indiv, 4):
            upper_limit = min(3, snps - snp_group - 1)
            for j in range(upper_limit + 1):
                indiv_index = indiv_group // 4
                entry = int(plink[indiv_index, snp_group + j])
                for i in range(4):
                    new_col = indiv_group + i
                    if new_col >= indiv:
                        continue
                    new_row = (snp_group + j) // 4
                    plink_transposed[new_row, new_col] |= np.uint8(((entry >> (2 * i)) & 0x03) << (2 * j))
    return plink_transposed
