import numpy as np
#import numba as nb

def _make_lut():
    # Build lookup table once (256 possible byte values)
    lut = np.empty((256, 4), dtype=np.float64)

    for b in range(256):
        # extract 2‑bit codes
        codes = [(b >> (2*k)) & 0x03 for k in range(4)]
        # convert PLINK codes to genotype
        geno = [0.0 if c==0 else 1.0 if c==2 else 2.0 if c==3 else np.nan for c in codes]
        lut[b] = geno

    return lut


LUT = _make_lut()

#@nb.njit
def decompress_bed(plink: np.ndarray, n_indiv: int, n_snps: int) -> np.ndarray:
    """
    Vectorised decompression of a PLINK .bed matrix.
    plink shape = (ceil(n_indiv/4), n_snps)  # bytes per 4 individuals
    Returns genotype matrix (n_indiv, n_snps) as float64.
    """

    # Apply lookup table to every byte 
    decoded = LUT[plink]      # shape (p_ind, n_snps, 4)

    # Reshape to (p_ind*4, n_snps) then trim excess rows
    geno = decoded.transpose(0, 2, 1)        # (p_ind, 4, n_snps)
    geno = geno.reshape(-1, n_snps)[:n_indiv, :]  # (n_indiv, n_snps)

    return geno

