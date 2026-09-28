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
    using BenchmarkTools
end

# =====================
# Global definitions
# =====================

global_logger(ConsoleLogger(stderr, Logging.Debug))
global_logger(ConsoleLogger(stderr, Logging.Info))

filename = ARGS[1]

ROOT_DIR = string(@__DIR__) * "/.."

MODULE_PATH = ROOT_DIR * "/src/bindings/Julia/miraculix.jl"
LIBRARY_PATH = ROOT_DIR * "/src/miraculix/miraculix.so"
DATA_DIR = ROOT_DIR * "/data"

#DATA_FILE = DATA_DIR * "/n2500_m5000.bed"
DATA_FILE = DATA_DIR * "/" * filename

#GRM_FILE = DATA_DIR * "/mobps_simulation.rel"

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

@timev "\n## Preprocessing" begin
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
@info "\nCalculating Cross-Product"

@timev "\n## Cross-Product (Warm-up)" begin
    CP = miraculix.crossproduct.snp_crossprod(plink_transposed, n_snps, n_indiv, is_snpmajor = false, is_plink_format = false) #warm-up
end

@info "\nShow CP"
@show CP[1:5, 1:5]

# Benchmark

@timev "\n## Cross-Product" begin
    CP = miraculix.crossproduct.snp_crossprod(plink_transposed, n_snps, n_indiv, is_snpmajor = false, is_plink_format = false)
end

# micro‑benchmark (multiple runs, excludes compilation)
b = @benchmark miraculix.crossproduct.snp_crossprod(plink_transposed, n_snps, n_indiv,
                                                   is_snpmajor=false, is_plink_format=false) setup=(GC.gc())

println("\n#######################################")
println("#### Cross-Product")
println(b)                     # full statistics
println(minimum(b))            # best time
println(mean(b))               # average time
println(median(b))             # median time
println("#######################################")



# Calculate the GRM in miraculix
@info "\nCalculating the genomic relationship matrix following VanRaden 1 approach"

@timev "\n## GRM VanRaden 1" begin
    G = miraculix.crossproduct.grm(plink_transposed, n_snps, n_indiv, is_plink_format = false, allele_freq = vec(freq), do_scale = true)
end

@info "\nShow G"
@show G[1:5,1:5]

# micro‑benchmark (multiple runs, excludes compilation)
b = @benchmark miraculix.crossproduct.grm(plink_transposed, n_snps, n_indiv, is_plink_format = false, allele_freq = vec(freq), do_scale = true) setup=(GC.gc())

println("\n#######################################")
println("#### GRM VanRaden 1")
println(b)                     # full statistics
println(minimum(b))            # best time
println(mean(b))               # average time
println(median(b))             # median time
println("#######################################")



#@testset "GRM comparison" begin
#    G2 = Matrix(CSV.read(GRM_FILE, delim = '\t', header = 0, DataFrame))
#    @test norm(G - G2)<1e-4
#end


