#  Authors 
#  Jeremie Vandenplas, jeremie.vandenplas@wur.nl

#  Copyright (C) 2026 Jeremie Vandenplas

#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.


using Base;
@time "Loading libraries" begin
    using LinearAlgebra;
    using LoopVectorization;
#    using Test
    using Logging
end

# =====================
# Global definitions
# =====================

global_logger(ConsoleLogger(stderr, Logging.Debug))

ROOT_DIR = string(@__DIR__) * "/.."

MODULE_PATH = ROOT_DIR * "/src/bindings/Julia/miraculix.jl"
LIBRARY_PATH = ROOT_DIR * "/src/miraculix/miraculix.so"
DATA_DIR = ROOT_DIR * "/data"

DATA_FILE = DATA_DIR * "/mobps_simulation.bed"
GRM_FILE = DATA_DIR * "/mobps_simulation.rel"

# Control miraculix verbosity
ENV["PRINT_LEVEL"] = "1";

# Get thread number
@assert haskey(ENV, "OMP_NUM_THREADS") "OMP_NUM_THREADS not set"
OMP_NUM_THREADS = ENV["OMP_NUM_THREADS"];
BLAS.set_num_threads(parse(Int,OMP_NUM_THREADS))
println("OMP threads set to $OMP_NUM_THREADS")
include(MODULE_PATH)

# =====================
# Main
# =====================

println("Load library and set options")
miraculix.set_library_path(LIBRARY_PATH)
miraculix.load_shared_library()
miraculix.dgemm_compressed.set_options(use_gpu=true, verbose=1)

# Read-in data from PLINK binary format
@info "Reading in data from $DATA_FILE and transpose it"
@timev "Preprocessing" begin
    # Read PLINK data and calculate allele frequencies
    wtime = @elapsed plink, freq, n_snps, n_indiv = miraculix.read_plink.read_bed(DATA_FILE, coding_twobit = true, calc_freq = true, check_for_missings = false)
    @debug "Time for reading: $wtime s."

    if (length(ARGS) > 0) && (ARGS[1] == "test")
        n_snps = 1000
        plink = plink[:,1:n_snps]
        freq = freq[1:n_snps]
    end
    
    # Transpose matrix
    wtime = @elapsed plink_transposed = miraculix.compressed_operations.transpose_genotype_matrix(plink, n_snps, n_indiv)
    @debug "Time for transposing: $wtime s."

    GC.gc()
end

# Calculate the cross-product in miraculix
@info "Calculating Cross-Product"

@timev "Cross-Product" begin
    CP = miraculix.crossproduct.snp_crossprod(plink_transposed, n_snps, n_indiv, is_snpmajor = false, is_plink_format = false)
end

@show CP[1:5, 1:5]

# Calculate the GRM in miraculix
@info "Calculating the genomic relationship matrix following VanRaden 1 approach"

@timev "GRM VanRaden 1" begin
    G = miraculix.crossproduct.grm(plink_transposed, n_snps, n_indiv, is_plink_format = false, allele_freq = vec(freq), do_scale = true)
end

@show G[1:5,1:5]


#@testset "GRM comparison" begin
#    G2 = Matrix(CSV.read(GRM_FILE, delim = '\t', header = 0, DataFrame))
#    @test norm(G - G2)<1e-4
#end


