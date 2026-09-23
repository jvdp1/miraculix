from pathlib import Path
import sys

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import miraculix as mx


ROOT = Path(__file__).resolve().parents[4]
LIBRARY_PATH = ROOT / "src" / "miraculix" / "miraculix.so"


def _pack_plink_style(genotypes: np.ndarray) -> np.ndarray:
    indiv, snps = genotypes.shape
    packed = np.zeros(((indiv + 3) // 4, snps), dtype=np.uint8, order="F")
    encode = {0: 0b00, 1: 0b10, 2: 0b11}
    for snp in range(snps):
        for indiv_index in range(indiv):
            byte_index = indiv_index // 4
            offset = (indiv_index % 4) * 2
            packed[byte_index, snp] |= np.uint8(encode[int(genotypes[indiv_index, snp])] << offset)
    return packed


def _transpose_packed(plink: np.ndarray, *, snps: int, indiv: int) -> np.ndarray:
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
                    offset = j
                    plink_transposed[new_row, new_col] |= np.uint8(((entry >> (2 * i)) & 0x03) << (2 * offset))
    return plink_transposed


def _write_plink_triplet(base_path: Path, genotype: np.ndarray) -> tuple[Path, np.ndarray]:
    bed_path = base_path.with_suffix(".bed")
    bim_path = base_path.with_suffix(".bim")
    fam_path = base_path.with_suffix(".fam")
    plink = _pack_plink_style(genotype)

    with bed_path.open("wb") as handle:
        handle.write(bytes((0x6C, 0x1B, 0x01)))
        handle.write(np.ascontiguousarray(plink.T).tobytes())

    n_indiv, n_snps = genotype.shape
    with bim_path.open("w", encoding="utf-8") as handle:
        for snp in range(n_snps):
            handle.write(f"1 rs{snp+1} 0 {snp+1} A G\n")
    with fam_path.open("w", encoding="utf-8") as handle:
        for indiv in range(n_indiv):
            handle.write(f"F{indiv+1} I{indiv+1} 0 0 0 -9\n")

    return bed_path, plink


@pytest.fixture(scope="module")
def loaded_library():
    if not LIBRARY_PATH.is_file():
        pytest.skip("miraculix.so not built")
    mx.set_library_path(LIBRARY_PATH)
    mx.load_shared_library()
    yield
    mx.close_shared_library()


def test_requires_explicit_library_load():
    mx.close_shared_library()
    with pytest.raises(mx.MiraculixError):
        mx.set_options(verbose=0)


def test_compressed_gemm_cpu_roundtrip(loaded_library):
    mx.set_options(use_gpu=False, verbose=0)

    genotype = np.array(
        [
            [0, 1, 2],
            [2, 1, 0],
            [1, 0, 1],
            [0, 2, 1],
            [2, 2, 0],
        ],
        dtype=np.uint8,
    )
    indiv, snps = genotype.shape
    freq = genotype.mean(axis=0, dtype=np.float64) / 2.0
    plink = _pack_plink_style(genotype)
    plink_t = _transpose_packed(plink, snps=snps, indiv=indiv)
    B = np.asfortranarray(np.array([[1.0, -1.0], [0.5, 2.0], [3.0, 0.25]], dtype=np.float64))

    handle = mx.init_compressed(plink, plink_t, snps, indiv, freq, max_ncol=B.shape[1])
    C = mx.dgemm_compressed(handle, B, snps=snps, indiv=indiv, transpose=False)

    expected = (genotype.astype(np.float64) - 2.0 * freq) @ B
    np.testing.assert_allclose(C, expected, atol=1e-8)

    handle.close()
    assert handle.closed


def test_init_compressed_validates_shapes(loaded_library):
    mx.set_options(use_gpu=False, verbose=0)
    plink = np.zeros((1, 3), dtype=np.uint8, order="F")
    plink_t = np.zeros((1, 4), dtype=np.uint8, order="F")
    freq = np.zeros(3, dtype=np.float64)
    with pytest.raises(ValueError):
        mx.init_compressed(plink, plink_t, 3, 5, freq, 2)


def test_read_bed_and_transpose_roundtrip(tmp_path):
    genotype = np.array(
        [
            [0, 1, 2],
            [2, 1, 0],
            [1, 0, 1],
            [0, 2, 1],
            [2, 2, 0],
        ],
        dtype=np.uint8,
    )
    bed_path, packed = _write_plink_triplet(tmp_path / "toy", genotype)

    plink, freq, n_snps, n_indiv = mx.read_bed(bed_path, calc_freq=True)
    plink_t = mx.transpose_plink(plink, snps=n_snps, indiv=n_indiv)

    np.testing.assert_array_equal(plink, packed)
    np.testing.assert_allclose(freq, genotype.mean(axis=0, dtype=np.float64) / 2.0)
    np.testing.assert_array_equal(plink_t, _transpose_packed(packed, snps=n_snps, indiv=n_indiv))
