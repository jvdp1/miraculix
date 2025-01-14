
/*
    Authors
    Alexander Freudenberg
    Copyright (C) 2020 -- 2023 Alexander Freudenberg

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.


    This file provides interfaces to the solving functionality in the cuSOLVER and cuSPARSE libraries by NVIDIA. These libraries are released as part of the CUDA toolkit under the copyright
    Copyright (C) 2012 -- 2023, NVIDIA Corporation & Affiliates.
*/


/*
    The functionality in this file is currently being integrated into the remainder of the repository -- heavily WIP
*/


#include <cusolverDn.h>
#include <cusolverMg.h>
#include <cusolverSp.h>
#include <cusparse.h>

#include <chrono>
#include <cublasLt.h>
#include <cublas_v2.h>
#include <cuda_runtime.h>
#include <cuda_runtime_api.h>
#include <stdio.h>
#include <time.h>
#include <omp.h>
#include <vector>

#include <thrust/gather.h>
#include <thrust/sequence.h>
#include <thrust/sort.h>
#include <thrust/execution_policy.h>


#include "solve_gpu.h"
#include "cuda_utils.h"

extern "C" {

/*
int cholSparse(double *csrVal, int *csrRowPtr, int *csrColInd, int m, int nnz, double *b, double *x);

int main(){
    const int m = 4;
    const int nnzA = 7;
    std::vector<int> csrRowPtrA = {1, 2, 3, 4, 8};
    std::vector<int>     {1, 2, 3, 1, 2, 3, 4};
    std::vector<double> csrValA = {1.0, 2.0, 3.0, 0.1, 0.1, 0.1, 4.0};
    std::vector<double> b = {1.0, 1.0, 1.0, 1.0};
    std::vector<double> x(m);
    cholSparse(csrValA.data(), csrRowPtrA.data(), csrColIndA.data(), m, nnzA, b.data(), x.data());
    for(int i = 0; i< m; i++)printf("%lf\n",x[i]);
    return x[0];
}
*/

__global__ void logdet_kernel(double* d_matrix, long* d_size, double* d_logdet)
{
    /* This CUDA kernel calculates the logdeterminant of a matrix by determining the trace of its cholesky decomposition
    Input:
        d_matrix pointer to matrix
        d_size size of matrix
    Output:
        d_logdet pointer to logdeterminant on device
    */

    __shared__ double logdet_loc;
    __shared__ double submatrix[THREADS_PER_BLOCK];
    logdet_loc = 0.0;
    *d_logdet = 0.0;
    long idx = blockDim.x * blockIdx.x + threadIdx.x,
         thread = threadIdx.x;
    if (idx < *d_size) {
        // double *d_submatrix = d_matrix + idx * (*d_size)-1;
        submatrix[thread] = d_matrix[idx * (*d_size + 1)];
    }
    __syncthreads();
    atomicAdd(&logdet_loc, idx >= *d_size ? 0 : (log(submatrix[thread])));

    __syncthreads();
    if (threadIdx.x == 0) {
        atomicAdd(d_logdet, logdet_loc);
    };
};

int cholGPU(double* matrix, Uint input_size, double* B, Uint rhs_cols,
    double* RESULT)
{
    /*
        This function solves the problem
            A x = b
        on   an available GPU and writes the solution to the original memory
        Input:
            matrix: pointer to rowwise allocated matrix A
            individuals: number of individuals in matrix, i.e. dimension
            vector: pointer to vector b
        Ouput:
            vector: contains solution x after the function has been called
    */
    clock_t start = clock();
    // declare/define process variables
    unsigned long size = (unsigned long)input_size;
    size_t bufferSize_device = 0,
           bufferSize_host = 0;
    cudaDataType dataTypeA = CUDA_R_64F;
    int* info = NULL;
    int h_info = 0;
    double *buffer_device = NULL,
           *buffer_host = NULL;
    cublasFillMode_t uplo = CUBLAS_FILL_MODE_LOWER;
    cusolverDnHandle_t handle = NULL;
    cusolverDnParams_t params = NULL;
    cudaStream_t stream = NULL;
    cusolverStatus_t status = CUSOLVER_STATUS_SUCCESS;
    // declare device variables
    double* d_matrix = NULL;
    double* d_B = NULL;
    double* d_logdet = NULL;
    long* d_size = NULL;

    // Nice functionality but only available in CUDA >= 11.7
    //    status = cusolverDnLoggerOpenFile("log.txt");
    //    if(status != CUSOLVER_STATUS_SUCCESS)printf("Status logging %d", status);
    // FILE file = fopen("log.txt","w+");
    // status = cusolverDnLoggerSetFile(FILE);
    // if(status != CUSOLVER_STATUS_SUCCESS)printf("Status logging %d", status);
    // cusolverDnLoggerSetLevel(5);

    int ManagedAvailable = 0;
    cudaDeviceGetAttribute(&ManagedAvailable, cudaDevAttrManagedMemory, 0);
    // initialize handle and stream, calculate buffer size needed for cholesky
    cusolverDnCreate(&handle);
    cudaStreamCreateWithFlags(&stream, cudaStreamNonBlocking);
    cusolverDnSetStream(handle, stream);

    cusolverDnCreateParams(&params);

    cudaMalloc(&info, sizeof(int));
    cudaMalloc(&buffer_device, sizeof(double) * bufferSize_device);
    cudaMallocHost(&buffer_host, sizeof(double) * bufferSize_host);

    // allocate memory on device
    cudaMalloc((void**)&d_matrix, sizeof(double) * size * size);
    cudaMalloc((void**)&d_B, sizeof(double) * size * rhs_cols);
    cudaMemset(info, 0, sizeof(int));
    // printf("Size of alloc %ld",  sizeof(double) * size * size);

    // copy data to device
    cudaMemcpy(d_matrix, matrix, sizeof(double) * size * size, cudaMemcpyHostToDevice);
    cudaMemcpy(d_B, B, sizeof(double) * size * rhs_cols, cudaMemcpyHostToDevice);
    cudaDeviceSynchronize();
    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess)
        printf("Memcpy %s\n", cudaGetErrorString(err));

    status = cusolverDnXpotrf_bufferSize(handle, params, uplo, size, dataTypeA, d_matrix,
        size, dataTypeA, &bufferSize_device, &bufferSize_host);
    cudaDeviceSynchronize();
    if (status != CUSOLVER_STATUS_SUCCESS)
        printf("Status Xpotrf %d\n", status);
    // write cholesky factorization to device copy of A
    status = cusolverDnXpotrf(handle, params, uplo, size, dataTypeA,
        d_matrix, size, dataTypeA, buffer_device, bufferSize_device, buffer_host, bufferSize_host, info);
    // Synchronize is necessary, otherwise error code "info" returns nonsense
    cudaDeviceSynchronize();
    err = cudaGetLastError();
    if (err != cudaSuccess)
        printf("Getrf %s\n", cudaGetErrorString(err));

    // check for errors
    cudaMemcpy(&h_info, info, sizeof(int), cudaMemcpyDeviceToHost);
    cudaDeviceSynchronize();

    if (0 != h_info) {
        if (h_info > 0)
            printf("Error: Cholesky factorization failed at minor %d \n", h_info);
        if (h_info < 0)
            printf("Error: Wrong parameter in cholesky factorization at %d entry\n", h_info);
        err = cudaDeviceReset();
        if (err != cudaSuccess)
            printf("Device reset not successful");
        return (1);
    }
    // calculate x = A\b
    status = cusolverDnXpotrs(handle, params, uplo, size, rhs_cols, dataTypeA,
        d_matrix, size, dataTypeA, d_B, size, info);
    cudaDeviceSynchronize();
    err = cudaGetLastError();
    if (err != cudaSuccess)
        printf("Getrs %s\n", cudaGetErrorString(err));
    if (false) {
        // if(LogDet != NULL){
        cudaMalloc((void**)&d_logdet, sizeof(double));
        cudaMalloc((void**)&d_size, sizeof(long));
        err = cudaGetLastError();
        if (err != cudaSuccess)
            printf("Logdet Malloc: %s\n", cudaGetErrorString(err));
        cudaMemcpy(d_size, &size, sizeof(long), cudaMemcpyHostToDevice);
        cudaDeviceSynchronize();
        err = cudaGetLastError();
        if (err != cudaSuccess)
            printf("Logdet Memcpy1: %s\n", cudaGetErrorString(err));
        logdet_kernel<<<(size - 1) / THREADS_PER_BLOCK + 1, THREADS_PER_BLOCK>>>(d_matrix, d_size, d_logdet);
        cudaDeviceSynchronize();
        err = cudaGetLastError();
        if (err != cudaSuccess)
            printf("Logdet Kernel: %s\n", cudaGetErrorString(err));
        // cudaMemcpy(LogDet, d_logdet, sizeof(double), cudaMemcpyDeviceToHost);
        cudaDeviceSynchronize();
        err = cudaGetLastError();
        if (err != cudaSuccess)
            printf("Logdet Memcpy: %s\n", cudaGetErrorString(err));
        cudaFree(d_size);
        cudaFree(d_logdet);
    }
    err = cudaGetLastError();
    if (err != cudaSuccess)
        printf("Err at Logdet: %s\n", cudaGetErrorString(err));
    // copy  solution from device to vector on host
    err = cudaMemcpy(RESULT, d_B, sizeof(double) * size * rhs_cols, cudaMemcpyDeviceToHost);
    if (err != cudaSuccess)
        printf("Memcpy: %s\n", cudaGetErrorString(err));

    err = cudaGetLastError();
    if (err != cudaSuccess)
        printf("Memcpy: %s\n", cudaGetErrorString(err));
    // free allocated memory
    cudaFree(info);
    cudaFree(buffer_device);
    cudaFree(buffer_host);
    cudaFree(d_matrix);
    cudaFree(d_B);
    cusolverDnDestroy(handle);
    cudaStreamDestroy(stream);
    printf("Time: %.3f", (double)(clock() - start) / CLOCKS_PER_SEC);
    return 0;
};

int cholSparse(double* csrVal, int* csrRowPtr, int* csrColInd, int m, int nnz, double* b, int ncol, double* x)
{
    /*
        This function provides an interface to the sparse cholesky factorization supplied by CUDA. Its inputs are arrays of sparse memory format. The input matrix must be symmetric. Though CUDA uses a Compressed Sparse Row (CSR) format, this function also works with CSC format, since they coincide for symmetric input matrices.
    */
    // Declare CUDA overhead objects
    cudaError_t err;

#define REPET 10

    // Declare device pointers and
    double *d_x = NULL,
           *d_b = NULL,
           *d_csrVal = NULL;
    int *d_csrRowPtr = NULL,
        *d_csrColInd = NULL;
    int singularity = 0;


    // Allocate memory for device objects
    cudaMalloc((void**)&d_x, sizeof(double) * m * ncol);
    cudaMalloc((void**)&d_b, sizeof(double) * m * ncol);
    cudaMalloc((void**)&d_csrVal, sizeof(double) * nnz);
    cudaMalloc((void**)&d_csrRowPtr, sizeof(int) * (m + 1));
    cudaMalloc((void**)&d_csrColInd, sizeof(int) * nnz);
    err = cudaGetLastError();
    if (err != cudaSuccess)
        printf("Chol Alloc %s\n", cudaGetErrorString(err));

    // Copy objects to device
    cudaMemcpy(d_b, b, sizeof(double) * m * ncol, cudaMemcpyHostToDevice);
    cudaMemcpy(d_csrVal, csrVal, sizeof(double) * nnz, cudaMemcpyHostToDevice);
    cudaMemcpy(d_csrRowPtr, csrRowPtr, sizeof(int) * (m + 1), cudaMemcpyHostToDevice);
    cudaMemcpy(d_csrColInd, csrColInd, sizeof(int) * nnz, cudaMemcpyHostToDevice);
    err = cudaGetLastError();
    if (err != cudaSuccess)
        printf("Chol Memcpy %s\n", cudaGetErrorString(err));

    auto start = std::chrono::high_resolution_clock::now();
    for (int k = 0; k < REPET; k++) {
#pragma omp parallel num_threads(ncol)
        for (int i = 0; i < ncol; i++) {
            csrqrInfo_t info = NULL;

            cusolverSpHandle_t handle = NULL;
            cusparseMatDescr_t descrA = NULL;
            cudaStream_t pStream;
            cudaStreamCreate(&pStream);

            // Initialize overhead objects
            cusolverSpCreate(&handle);
            cusolverSpSetStream(handle, pStream);
            cusparseCreateMatDescr(&descrA);
            cusolverSpCreateCsrqrInfo(&info);

            // Set function parameters
            cusparseSetMatType(descrA, CUSPARSE_MATRIX_TYPE_GENERAL);
            cusparseSetMatIndexBase(descrA, CUSPARSE_INDEX_BASE_ONE);
            cudaStreamSynchronize(pStream);
            err = cudaGetLastError();
            if (err != cudaSuccess)
              printf("Chol Sparse init %s\n", cudaGetErrorString(err));

            // Perform cholesky factorization
            cusolverSpDcsrlsvchol(handle, m, nnz, descrA, d_csrVal, d_csrRowPtr,
                                  d_csrColInd, d_b + i * m, 0.0, 0, d_x + i * m,
                                  &singularity);
            cudaStreamSynchronize(pStream);
            err = cudaGetLastError();
            if (err != cudaSuccess)
              printf("Chol %s\n", cudaGetErrorString(err));

            cusolverSpDestroy(handle);
            cudaStreamDestroy(pStream);
        }
    }
    cudaDeviceSynchronize();
    auto stop = std::chrono::high_resolution_clock::now();

    // Calculate calculatiom time
    std::chrono::duration<double> duration = (stop - start);
    FILE *temp = fopen("time.log", "a");

    time_t current_time;
    current_time = time(NULL);
    fprintf(temp, "Run on %s %s\n", ctime(&current_time));

    fprintf(temp, "Duration perf %.5lf\n", duration.count() / REPET);
    fflush(temp);
    fclose(temp);

    // Copy results back to host
    cudaMemcpy(x, d_x, sizeof(double) * m * ncol, cudaMemcpyDeviceToHost);
    err = cudaGetLastError();
    if (err != cudaSuccess)
        printf("Copy back %s\n", cudaGetErrorString(err));

    // Free memory and overhead objects
    cudaFree(d_x);
    cudaFree(d_csrVal);
    cudaFree(d_csrRowPtr);
    cudaFree(d_csrColInd);

    fflush(NULL);
    return 0;
}

void sparse2gpu(
     double *V,     // Vector of matrix values (COO format)
     int *I,        // Vector of row indices (COO format)
     int *J,        // Vector of column indices (COO format)
     long nnz,       // Number of nonzero values (length of V)
     long m,         // Number of rows and columns of matrix
     long max_ncol,  // Maximum number of columns of RHS in equation systems
     void **GPU_obj, // Pointer in which GPU object for iterative solver will be
                    // stored
     int *status
){

    // Print compile info
    printf("------------");
    printf("------------");
    printf("------------");
    printf("------------");
    printf("------------\n");
    printf("\tmiraculix - cuSPARSE triangular solve interface\n");
#if defined COMMIT_ID
    printf("Compiled on %s %s, git commit %s\n", __DATE__, __TIME__, COMMIT_ID);
#endif
    printf("------------");
    printf("------------");
    printf("------------");
    printf("------------");
    printf("------------\n");

    //
    // Initialize CUDA variables
    //
    cusparseHandle_t handle;
    cusparseMatDescr_t descrL, descrLt;
    bsrsm2Info_t info_csc, info_csr;
    cusparseStatus_t sp_status;
    cudaError_t err;

    // Declare device pointers
    double *d_X               = NULL,
           *d_V               = NULL,
           *d_B               = NULL,
           *d_cscVal          = NULL,
           *d_csrVal          = NULL;
    int    *d_I               = NULL,
           *d_J               = NULL,
           *d_cscColPtr       = NULL,
           *d_csrRowPtr       = NULL,
           *d_cscRowInd       = NULL,
           *d_csrColInd       = NULL;
    void   *d_pBuffer_csc     = NULL,
           *d_pBuffer_csr     = NULL,
           *d_pBuffer_CSC2CSR = NULL;

    int    pBufferSizeInBytes_csc = 0,
           pBufferSizeInBytes_csr = 0,
           structural_zero        = 0;
    size_t pBufferSizeCSC2CSR     = 0;

    // Check CUDA installation
    if (checkCuda() != 0) {
        *status = 1;
        return;
    }

    size_t required_mem = (2 * m * max_ncol + nnz) * sizeof(double) +
                          sizeof(int) * (2 * nnz + (m + 1));
    
    if(checkDevMemory(required_mem) != 0){
        *status = 1;
        return;
    }
    // Allocate memory for device objects
    cudaMalloc((void**)&d_X, sizeof(double) * m * max_ncol);
    cudaMalloc((void**)&d_B, sizeof(double) * m * max_ncol);
    cudaMalloc((void**)&d_I, sizeof(int) * nnz);
    cudaMalloc((void**)&d_J, sizeof(int) * nnz);
    cudaMalloc((void**)&d_V, sizeof(double) * nnz);

    cudaMalloc((void **)&d_cscColPtr, sizeof(int) * (m + 1));
    cudaMalloc((void **)&d_csrRowPtr, sizeof(int) * (m + 1));
    cudaMalloc((void **)&d_csrColInd, sizeof(int) * nnz);
    cudaMalloc((void**)&d_csrVal, sizeof(double) * nnz);

    err = cudaGetLastError();
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        return;
    }

    // Copy I J V data to device
    cudaMemcpy(d_I, I, sizeof(int) * nnz, cudaMemcpyHostToDevice);
    cudaMemcpy(d_J, J, sizeof(int) * nnz, cudaMemcpyHostToDevice);
    cudaMemcpy(d_V, V, sizeof(double) * nnz, cudaMemcpyHostToDevice);

    err = cudaGetLastError();
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        return;
    }

    // Set up auxiliary stuff
    cusparseCreate(&handle);
    cusparseCreateMatDescr(&descrLt);
    cusparseCreateMatDescr(&descrL);
    cusparseSetMatDiagType(descrLt, CUSPARSE_DIAG_TYPE_NON_UNIT);
    cusparseSetMatDiagType(descrL, CUSPARSE_DIAG_TYPE_NON_UNIT);
    cusparseSetMatFillMode(descrLt, CUSPARSE_FILL_MODE_UPPER);
    cusparseSetMatFillMode(descrL, CUSPARSE_FILL_MODE_LOWER);
    cusparseSetMatIndexBase(descrLt, CUSPARSE_INDEX_BASE_ONE);
    cusparseSetMatIndexBase(descrL, CUSPARSE_INDEX_BASE_ONE);
    cusparseSetMatType(descrLt, CUSPARSE_MATRIX_TYPE_GENERAL);
    cusparseSetMatType(descrL, CUSPARSE_MATRIX_TYPE_GENERAL);

    //
    // Sort COO data by column -- this is strictly required as CSR routine fails
    // otherwise
    //
    debug_info("Calculating buffer");
    sp_status = cusparseXcoosort_bufferSizeExt(handle, m, m, nnz, d_I, d_J,
                                               &pBufferSizeCSC2CSR);
    if (checkError(__func__, __LINE__, sp_status) != 0) {
        *status = 1;
        return;
    }
    debug_info("Allocatingx");
    cudaMalloc((void**)&d_pBuffer_CSC2CSR, pBufferSizeCSC2CSR);
    debug_info("Sequencing");
    thrust::sequence(thrust::device, d_csrColInd, d_csrColInd + nnz);

    debug_info("Sorting");
    sp_status = cusparseXcoosortByColumn(handle, m, m, nnz, d_I, d_J, d_csrColInd, d_pBuffer_CSC2CSR);
    if (checkError(__func__, __LINE__, sp_status) != 0) {
        *status = 1;
        return;
    }
    cudaDeviceSynchronize();

    debug_info("Sorting Values");
    thrust::gather(thrust::device, d_csrColInd, d_csrColInd + nnz, d_V, d_csrVal);
    cudaDeviceSynchronize();

    cudaMemcpy(d_V, d_csrVal, sizeof(double) * nnz, cudaMemcpyDeviceToDevice);
    cudaFree(d_pBuffer_CSC2CSR);
    cudaMemset(d_csrColInd, 0, sizeof(int) * nnz);
    cudaMemset(d_csrVal, 0, sizeof(double) * nnz);

    // Initialize CSC data
    sp_status = cusparseXcoo2csr(handle, d_J, nnz, m, d_cscColPtr,
                                 CUSPARSE_INDEX_BASE_ONE);
    if (checkError(__func__, __LINE__, sp_status) != 0) {
        *status = 1;
        return;
    }

    d_cscRowInd = d_I;
    d_cscVal    = d_V;
    cudaFree(d_J);

    // Initialize CSR data -- construct from CSC by transposing

    sp_status = cusparseCsr2cscEx2_bufferSize(
        handle, m, m, nnz, d_cscVal, d_cscColPtr, d_cscRowInd, d_csrVal,
        d_csrRowPtr, d_csrColInd, CUDA_R_64F, CUSPARSE_ACTION_NUMERIC,
        CUSPARSE_INDEX_BASE_ONE, CUSPARSE_CSR2CSC_ALG1,
        &pBufferSizeCSC2CSR); // The cusparseCsr2CscAlg_t alg argument is
                              // undocumented in the official docs -- cf
                              // cusparse.h
    if (checkError(__func__, __LINE__, sp_status) != 0) {
        *status = 1;
        return;
    }

    // Allocate buffer memory for CSC2CSR procedure
    required_mem += pBufferSizeCSC2CSR;
    if (checkDevMemory(required_mem) != 0) {
        *status = 1;
        return;
    }
    cudaMalloc((void**)&d_pBuffer_CSC2CSR, pBufferSizeCSC2CSR);
    

#ifdef DEBUG
    int *h_csrRowPtr = NULL, *h_csrColInd = NULL;
    cudaMallocHost((void **)&h_csrRowPtr, sizeof(int) * (m + 1));
    cudaMallocHost((void **)&h_csrColInd, max(sizeof(double) * nnz, pBufferSizeCSC2CSR));
    err = cudaMemcpy(h_csrRowPtr, d_cscColPtr, sizeof(int) * (m + 1),
               cudaMemcpyDeviceToHost);
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        return;
    }

    err = cudaMemcpy(h_csrColInd, d_cscRowInd, sizeof(int) * nnz,
               cudaMemcpyDeviceToHost);
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        return;
    }

    debug_info("m %d, nnz %d", m, nnz);
    for (int i = 0; i < min(m + 1, (long) 20); i++)
        printf("%d, ", h_csrRowPtr[i]);
    debug_info(" - cscColPtr\n");
    for (int i = 0; i < min(nnz, (long) 20); i++)
        printf("%d, ", h_csrColInd[i]);
    debug_info(" - RowInd\n");
#endif


    debug_info("m %d nnz %d, Buffer %zu", m, nnz, pBufferSizeCSC2CSR);
    err = cudaGetLastError();
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        return;
    }

    sp_status = cusparseCsr2cscEx2(
        handle, m, m, nnz, (void *)d_cscVal, d_cscColPtr, d_cscRowInd,
        (void *)d_csrVal, d_csrRowPtr, d_csrColInd, CUDA_R_64F,
        CUSPARSE_ACTION_NUMERIC, CUSPARSE_INDEX_BASE_ONE,
        CUSPARSE_CSR2CSC_ALG1, d_pBuffer_CSC2CSR);
    cudaDeviceSynchronize();
    if (checkError(__func__, __LINE__, sp_status) != 0) {
        *status = 1;
        return;
    }

    err = cudaGetLastError();
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        cudaDeviceReset();
        return;
    }
    cudaFree(d_pBuffer_CSC2CSR);

    //
    // Init phase for triangular solve
    //
    sp_status = cusparseCreateBsrsm2Info(&info_csc);
    if (checkError(__func__, __LINE__, sp_status) != 0) {
        *status = 1;
        return;
    }
    sp_status = cusparseCreateBsrsm2Info(&info_csr);
    if (checkError(__func__, __LINE__, sp_status) != 0) {
        *status = 1;
        return;
    }

    // Get required buffer size of triangular solve
    sp_status = cusparseDbsrsm2_bufferSize(
        handle, CUSPARSE_DIRECTION_ROW, CUSPARSE_OPERATION_NON_TRANSPOSE,
        CUSPARSE_OPERATION_NON_TRANSPOSE, m, max_ncol, nnz, descrLt, d_cscVal,
        d_cscColPtr, d_cscRowInd, 1, info_csc, &pBufferSizeInBytes_csc);
    cudaDeviceSynchronize();

    debug_info("Buffer size CSC %d", pBufferSizeInBytes_csc);
    if (checkError(__func__, __LINE__, sp_status) != 0) {
        *status = 1;
        return;
    }

    sp_status = cusparseDbsrsm2_bufferSize(
        handle, CUSPARSE_DIRECTION_ROW, CUSPARSE_OPERATION_NON_TRANSPOSE,
        CUSPARSE_OPERATION_NON_TRANSPOSE, m, max_ncol, nnz, descrL, d_csrVal,
        d_csrRowPtr, d_csrColInd, 1, info_csr, &pBufferSizeInBytes_csr);
    cudaDeviceSynchronize();

    debug_info("Buffer size CSR %d", pBufferSizeInBytes_csr);
    if (checkError(__func__, __LINE__, sp_status) != 0) {
        *status = 1;
        return;
    }

    // Allocate buffer memory for triangular solve
    required_mem += 2*pBufferSizeInBytes_csc;
    if (checkDevMemory(required_mem) != 0) {
        *status = 1;
        return;
    }
    cudaMalloc((void**)&d_pBuffer_csc, pBufferSizeInBytes_csc);
    cudaMalloc((void**)&d_pBuffer_csr, pBufferSizeInBytes_csr);

    // Perform analysis phase of triangular solve 
    sp_status = cusparseDbsrsm2_analysis(
        handle, CUSPARSE_DIRECTION_ROW, CUSPARSE_OPERATION_NON_TRANSPOSE,
        CUSPARSE_OPERATION_NON_TRANSPOSE, m, max_ncol, nnz, descrLt, d_cscVal,
        d_cscColPtr, d_cscRowInd, 1, info_csc, CUSPARSE_SOLVE_POLICY_NO_LEVEL,
        d_pBuffer_csc);
    cudaDeviceSynchronize();

    if (checkError(__func__, __LINE__, sp_status) != 0) {
        *status = 1;
        return;
    }

    // Check for solvability in Cholesky root L
    sp_status = cusparseXbsrsm2_zeroPivot(handle, info_csc, &structural_zero);
    if (CUSPARSE_STATUS_ZERO_PIVOT == sp_status) {
        printf("Structural zero in Cholesky root CSC: L(%d,%d) is missing\n",
               structural_zero, structural_zero);
        *status = 1;
        return;
    }

    sp_status = cusparseDbsrsm2_analysis(
        handle, CUSPARSE_DIRECTION_ROW, CUSPARSE_OPERATION_NON_TRANSPOSE,
        CUSPARSE_OPERATION_NON_TRANSPOSE, m, max_ncol, nnz, descrL, d_csrVal,
        d_csrRowPtr, d_csrColInd, 1, info_csr, CUSPARSE_SOLVE_POLICY_NO_LEVEL,
        d_pBuffer_csr);
    cudaDeviceSynchronize();

    if (checkError(__func__, __LINE__, sp_status) != 0) {
        *status = 1;
        return;
    }

    // Check for solvability in Cholesky root L 
    sp_status = cusparseXbsrsm2_zeroPivot(handle, info_csr, &structural_zero);
    if (CUSPARSE_STATUS_ZERO_PIVOT == sp_status) {
        printf("Structural zero in Cholesky root CSR: L(%d,%d) is missing\n",
               structural_zero, structural_zero);
        *status = 1;
        return;
    }

    err = cudaGetLastError();
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        return;
    }

    //
    // Initialize GPU_sparse_storage object
    //
    struct GPU_sparse_storage *GPU_storage_obj =
        (struct GPU_sparse_storage *)malloc(sizeof(struct GPU_sparse_storage));
    GPU_storage_obj->d_cscColPtr   = d_cscColPtr;
    GPU_storage_obj->d_cscRowInd   = d_cscRowInd;
    GPU_storage_obj->d_cscVal      = d_cscVal;
    GPU_storage_obj->d_csrRowPtr   = d_csrRowPtr;
    GPU_storage_obj->d_csrColInd   = d_csrColInd;
    GPU_storage_obj->d_csrVal      = d_csrVal;
    GPU_storage_obj->nnz           = nnz;
    GPU_storage_obj->m             = m;
    GPU_storage_obj->max_ncol      = max_ncol;
    GPU_storage_obj->d_X           = d_X;
    GPU_storage_obj->d_B           = d_B;
    GPU_storage_obj->d_pBuffer_csc = d_pBuffer_csc;
    GPU_storage_obj->d_pBuffer_csr = d_pBuffer_csr;
    GPU_storage_obj->info_csc      = info_csc;
    GPU_storage_obj->info_csr      = info_csr;

    debug_info("Pointer pBuffer_csc %d", d_pBuffer_csc);

    // Set pointer to initialized object
    *GPU_obj = (void *)GPU_storage_obj;

    sp_status = cusparseDestroy(handle);
    if (checkError(__func__, __LINE__, sp_status) != 0) {
        *status = 1;
        return;
    }

    err = cudaGetLastError();
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        return;
    }
};



void dcsrtrsv_solve(void *GPU_obj, // Pointer to GPU object
                   double *B,     // Pointer to RHS matrix of size m x ncol
                   int ncol,      // Number of columns of B and X
                   double *X,     // Solution matrix of size size m x ncol
                   int *status
){

    //
    // Initialize CUDA variables
    //
    cusparseHandle_t handle;
    cusparseMatDescr_t descrL, descrLt;
    bsrsm2Info_t info_csc, info_csr;
    cusparseStatus_t sp_status;
    cudaError_t err;

    // Check CUDA installation
    if (checkCuda() != 0) {
        *status = 1;
        return;
    }

    // Get GPU storage object
    struct GPU_sparse_storage *GPU_storage_obj =
        (struct GPU_sparse_storage *)GPU_obj;

    // Get problem dimensions
    long m        = GPU_storage_obj->m,
         nnz      = GPU_storage_obj->nnz;
    int  max_ncol = GPU_storage_obj->max_ncol;

    if (ncol > max_ncol) {
        printf("Sparse solve interface has been initialized with %d columns, "
               "but %d columns are requested by the calculation function.\n",
               max_ncol, ncol);
        *status = 1;
        return;
    }
    debug_info("Start calc");
    debug_info("%d %d %d", m, nnz, max_ncol);
    err = cudaGetLastError();
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        return;
    }

    // Declare device pointers
    double *d_X           = GPU_storage_obj->d_X,
           *d_B           = GPU_storage_obj->d_B,
           *d_cscVal      = GPU_storage_obj->d_cscVal,
           *d_csrVal      = GPU_storage_obj->d_csrVal ;
    int    *d_cscColPtr   = GPU_storage_obj->d_cscColPtr,
           *d_cscRowInd   = GPU_storage_obj->d_cscRowInd,
           *d_csrRowPtr   = GPU_storage_obj->d_csrRowPtr,
           *d_csrColInd   = GPU_storage_obj->d_csrColInd;
    void   *d_pBuffer_csc = GPU_storage_obj->d_pBuffer_csc,
           *d_pBuffer_csr = GPU_storage_obj->d_pBuffer_csr;

    int numerical_zero = 0;
    const double alpha = 1.0;

    // Get CUDA auxiliary variables
    info_csc    = GPU_storage_obj->info_csc;
    info_csr    = GPU_storage_obj->info_csr;
    cusparseCreate(&handle);

    cusparseCreateMatDescr(&descrLt);
    cusparseCreateMatDescr(&descrL);
    cusparseSetMatDiagType(descrLt, CUSPARSE_DIAG_TYPE_NON_UNIT);
    cusparseSetMatDiagType(descrL, CUSPARSE_DIAG_TYPE_NON_UNIT);
    cusparseSetMatFillMode(descrLt, CUSPARSE_FILL_MODE_UPPER);
    cusparseSetMatFillMode(descrL, CUSPARSE_FILL_MODE_LOWER);
    cusparseSetMatIndexBase(descrLt, CUSPARSE_INDEX_BASE_ONE);
    cusparseSetMatIndexBase(descrL, CUSPARSE_INDEX_BASE_ONE);
    cusparseSetMatType(descrLt, CUSPARSE_MATRIX_TYPE_GENERAL);
    cusparseSetMatType(descrL, CUSPARSE_MATRIX_TYPE_GENERAL);

    err = cudaGetLastError();
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        return;
    }

    // Reset memory for X and B on device
    err = cudaMemset(d_B, 0.0, sizeof(double) * m * max_ncol);
    if (checkError(__func__, __LINE__, err) != 0){
        *status = 1;
        return;
    }
    err = cudaMemset(d_X, 0.0, sizeof(double) * m * max_ncol);
    if (checkError(__func__, __LINE__, err) != 0){
        *status = 1;
        return;
    }
    err = cudaGetLastError();
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        return;
    }

    // Copy data to device
    err = cudaMemcpy(d_B, B, sizeof(double) * m * ncol, cudaMemcpyHostToDevice);
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        return;
    }
    err = cudaGetLastError();
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        return;
    }

    //
    // Solving equation system on device - forward substitution
    // 
    auto start = clock();

    sp_status = cusparseDbsrsm2_solve(
        handle, CUSPARSE_DIRECTION_ROW, CUSPARSE_OPERATION_NON_TRANSPOSE,
        CUSPARSE_OPERATION_NON_TRANSPOSE, m, ncol, nnz, &alpha, descrL,
        d_csrVal, d_csrRowPtr, d_csrColInd, 1, info_csr, d_B, m, d_X, m,
        CUSPARSE_SOLVE_POLICY_NO_LEVEL, d_pBuffer_csr);

    cudaDeviceSynchronize();
    if (checkError(__func__, __LINE__, sp_status) != 0) {
        *status = 1;
        return;
    }

    sp_status = cusparseXbsrsm2_zeroPivot(handle, info_csr, &numerical_zero);
    if (CUSPARSE_STATUS_ZERO_PIVOT == sp_status) {
        printf("Numerical zero during solving: L(%d,%d) is zero\n", numerical_zero, numerical_zero);
        *status = 1;
        return;
    }

    err = cudaGetLastError();
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        return;
    }

    // Backward substitution to get result of L L^T X = B
    sp_status = cusparseDbsrsm2_solve(
        handle, CUSPARSE_DIRECTION_ROW, CUSPARSE_OPERATION_NON_TRANSPOSE,
        CUSPARSE_OPERATION_NON_TRANSPOSE, m, ncol, nnz, &alpha, descrLt,
        d_cscVal, d_cscColPtr, d_cscRowInd, 1, info_csc, d_X, m, d_B, m,
        CUSPARSE_SOLVE_POLICY_NO_LEVEL, d_pBuffer_csc);

    cudaDeviceSynchronize();
    if (checkError(__func__, __LINE__, sp_status) != 0) {
        *status = 1;
        return;
    }

    sp_status = cusparseXbsrsm2_zeroPivot(handle, info_csc, &numerical_zero);
    if (CUSPARSE_STATUS_ZERO_PIVOT == sp_status) {
        printf("Numerical zero during solving: L(%d,%d) is zero\n",
               numerical_zero, numerical_zero);
        *status = 1;
        return;
    }

    err = cudaGetLastError();
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        return;
    }
    printf("Time: %.3f", (double)(clock() - start) / CLOCKS_PER_SEC);

    // Copy results back to device
    err = cudaMemcpy(X, d_B, sizeof(double) * m * ncol, cudaMemcpyDeviceToHost);
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        return;
    }
    
    debug_info("Returning");
    cusparseDestroyMatDescr(descrLt);
    cusparseDestroyMatDescr(descrL);
    cusparseDestroy(handle);
};


void freegpu_sparse(void *GPU_obj, int *status){
    cudaError_t err;
    bsrsm2Info_t info_csc, info_csr;

    // Check CUDA installation
    if (checkCuda() != 0) {
        *status = 1;
        return;
    }
    cudaDeviceSynchronize();

    // Get GPU storage object
    struct GPU_sparse_storage *GPU_storage_obj =
        (struct GPU_sparse_storage *)GPU_obj;

    // Declare device pointers
    double *d_X           = GPU_storage_obj->d_X,
           *d_B           = GPU_storage_obj->d_B,
           *d_cscVal      = GPU_storage_obj->d_cscVal,
           *d_csrVal      = GPU_storage_obj->d_csrVal;
    int    *d_cscColPtr   = GPU_storage_obj->d_cscColPtr,
           *d_cscRowInd   = GPU_storage_obj->d_cscRowInd,
           *d_csrRowPtr   = GPU_storage_obj->d_csrRowPtr,
           *d_csrColInd   = GPU_storage_obj->d_csrColInd;
    void   *d_pBuffer_csc = GPU_storage_obj->d_pBuffer_csc,
           *d_pBuffer_csr = GPU_storage_obj->d_pBuffer_csr;

    debug_info("Pointer pBuffer_csc %d", d_pBuffer_csc);

    info_csc = GPU_storage_obj->info_csc;
    info_csr = GPU_storage_obj->info_csr;

    err = cudaFree(d_X);
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        return;
    }
    err = cudaFree(d_B);
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        return;
    }
    err = cudaFree(d_cscVal);
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        return;
    }
    err = cudaFree(d_cscColPtr);
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        return;
    }
    err = cudaFree(d_cscRowInd);
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        return;
    }
    err = cudaFree(d_pBuffer_csc);
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        return;
    }
    err = cudaFree(d_csrVal);
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        return;
    }
    err = cudaFree(d_csrRowPtr);
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        return;
    }
    err = cudaFree(d_csrColInd);
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        return;
    }
    err = cudaFree(d_pBuffer_csr);
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        return;
    }

    cusparseDestroyBsrsm2Info(info_csc);
    cusparseDestroyBsrsm2Info(info_csr);
    free(GPU_storage_obj);

    cudaDeviceReset();

    err = cudaGetLastError();
    if (checkError(__func__, __LINE__, err) != 0) {
        *status = 1;
        return;
    }
};
/*
int full_solve(double* V, int* I, int* J, int m, int nnz, double* b, int ncol, double* x){
    cusparseHandle_t handle;
    cusparseStatus_t sp_status;
    cusparseMatDescr_t descrL;
    cusparseMatDescr_t descrLt;
    bsrsm2Info_t info;
  // bsrsv2Info_t info;
    cudaError_t err;

    // Declare device pointers 
    double *d_x         = NULL,
           *d_V         = NULL,
           *d_b         = NULL,
           *d_cscVal    = NULL,
           *d_csrVal    = NULL;
    int    *d_I         = NULL,
           *d_J         = NULL,
           *d_cscColPtr = NULL,
           *d_cscRowInd = NULL,
           *d_csrRowPtr = NULL,
           *d_csrColInd = NULL;
    int    *h_csrRowPtr = NULL,
           *h_csrColInd = NULL;
    double *h_csrVal    = NULL;
    
    void   *d_pBuffer_csc         = NULL;
    int    pBufferSizeInBytes_csc = 0;
    int    structural_zero    = 0,
           numerical_zero     = 0;

    // Allocate memory for device objects
    cudaMalloc((void**)&d_x, sizeof(double) * m * ncol);
    cudaMalloc((void**)&d_b, sizeof(double) * m * ncol);
    cudaMalloc((void**)&d_I, sizeof(int) * nnz);
    cudaMalloc((void**)&d_J, sizeof(int) * nnz);
    cudaMalloc((void**)&d_V, sizeof(double) * nnz);

    cudaMalloc((void**)&d_cscColPtr, sizeof(int) * (m + 1));
    cudaMalloc((void**)&d_csrRowPtr, sizeof(int) * (m + 1));

    err = cudaGetLastError();
    if (err != cudaSuccess)
        printf("Chol mem allocation %s\n", cudaGetErrorString(err));

    // Copy I J V data to device
    cudaMemcpy(d_b, b, sizeof(double) * m * ncol, cudaMemcpyHostToDevice);
    cudaMemcpy(d_I, I, sizeof(int) * nnz, cudaMemcpyHostToDevice);
    cudaMemcpy(d_J, J, sizeof(int) * nnz, cudaMemcpyHostToDevice);
    cudaMemcpy(d_V, V, sizeof(double) * nnz, cudaMemcpyHostToDevice);

    err = cudaGetLastError();
    if (err != cudaSuccess)
        printf("Chol Memcpy %s\n", cudaGetErrorString(err));

    // Set up auxiliary stuff
    cusparseCreate(&handle);
    cusparseCreateMatDescr(&descrL);
    cusparseCreateMatDescr(&descrLt);
    cusparseSetMatDiagType(descrL, CUSPARSE_DIAG_TYPE_NON_UNIT);
    cusparseSetMatDiagType(descrLt, CUSPARSE_DIAG_TYPE_NON_UNIT);
    cusparseSetMatFillMode(descrL, CUSPARSE_FILL_MODE_LOWER);
    cusparseSetMatFillMode(descrLt, CUSPARSE_FILL_MODE_UPPER);
    cusparseSetMatIndexBase(descrL, CUSPARSE_INDEX_BASE_ONE);
    cusparseSetMatIndexBase(descrLt, CUSPARSE_INDEX_BASE_ONE);
    cusparseSetMatType(descrL, CUSPARSE_MATRIX_TYPE_GENERAL);
    cusparseSetMatType(descrLt, CUSPARSE_MATRIX_TYPE_GENERAL);

    // Initialize CSC and CSR data
    sp_status = cusparseXcoo2csr(handle, d_I, nnz, m, d_csrRowPtr, CUSPARSE_INDEX_BASE_ONE);
    if (sp_status != CUSPARSE_STATUS_SUCCESS)
        printf("CSR init error %s\n",
               cusparseGetErrorString(sp_status));
    sp_status = cusparseXcoo2csr(handle, d_J, nnz, m, d_cscColPtr, CUSPARSE_INDEX_BASE_ONE);
    if (sp_status != CUSPARSE_STATUS_SUCCESS)
        printf("CSR init error %s\n",
               cusparseGetErrorString(sp_status));

    d_csrColInd = d_J;
    d_cscRowInd = d_I;
    d_csrVal    = d_V;
    d_cscVal    = d_V;

    bool verbose = false;
    if(verbose){
        cudaMallocHost((void **)&h_csrRowPtr, sizeof(int) * (m + 1));
        cudaMallocHost((void **)&h_csrColInd, sizeof(int) * nnz);
        cudaMemcpy(h_csrRowPtr, d_csrRowPtr, sizeof(int) * (m+1), cudaMemcpyDeviceToHost);
        cudaMemcpy(h_csrColInd, d_csrColInd, sizeof(int) * nnz, cudaMemcpyDeviceToHost);
        for (int i = 0; i < m + 1; i++)
            printf("%d, ", h_csrRowPtr[i]);
        printf("\n");
        for (int i = 0; i < nnz; i++)
            printf("%d, ", h_csrColInd[i]);
        printf("\n");
    }
    // Init phase for triangular solve
    sp_status = cusparseCreateBsrsm2Info(&info);
    // sp_status = cusparseCreateBsrsv2Info(&info);
    if (sp_status != CUSPARSE_STATUS_SUCCESS)
        printf("CSR init error %s\n",
               cusparseGetErrorString(sp_status));

    sp_status = cusparseDbsrsm2_bufferSize(
                        handle, 
                        CUSPARSE_DIRECTION_ROW, 
                        CUSPARSE_OPERATION_NON_TRANSPOSE,
                        CUSPARSE_OPERATION_NON_TRANSPOSE, 
                        m, 
                        ncol, 
                        nnz, 
                        descrLt, 
                        d_cscVal,
                        d_cscColPtr, 
                        d_cscRowInd, 
                        1, 
                        info, 
                        &pBufferSizeInBytes_csc);
    cudaDeviceSynchronize();

    if (sp_status != CUSPARSE_STATUS_SUCCESS)
        printf("CSR init error %s\n",
               cusparseGetErrorString(sp_status));

    cudaMalloc(&d_pBuffer_csc, pBufferSizeInBytes_csc);

    sp_status = cusparseDbsrsm2_analysis(
                        handle,
                        CUSPARSE_DIRECTION_ROW,
                        CUSPARSE_OPERATION_NON_TRANSPOSE,
                        CUSPARSE_OPERATION_NON_TRANSPOSE,
                        m,
                        ncol, 
                        nnz, 
                        descrLt, 
                        d_cscVal,
                        d_cscColPtr, 
                        d_cscRowInd, 
                        1, 
                        info,
                        CUSPARSE_SOLVE_POLICY_NO_LEVEL,
                        d_pBuffer_csc);
    cudaDeviceSynchronize();
    
    if (sp_status != CUSPARSE_STATUS_SUCCESS)
        printf("CSR analysis error %s\n",
               cusparseGetErrorString(sp_status));

    sp_status = cusparseXbsrsm2_zeroPivot(handle, info, &structural_zero);
    if (CUSPARSE_STATUS_ZERO_PIVOT == sp_status) {
        printf("L(%d,%d) is missing\n", structural_zero, structural_zero);
    }

    err = cudaGetLastError();
    if (err != cudaSuccess)
        printf("CSR Init phase %s\n", cudaGetErrorString(err));

        
    // Start solving
    const double alpha = 1.0;

#define REPET 10
    auto start = std::chrono::high_resolution_clock::now();
    for (int k = 0; k < REPET; k++) {
        sp_status = cusparseDbsrsm2_solve(
                            handle,
                            CUSPARSE_DIRECTION_ROW,
                        CUSPARSE_OPERATION_NON_TRANSPOSE,
                            CUSPARSE_OPERATION_NON_TRANSPOSE,
                            m,
                            ncol, 
                            nnz, 
                            &alpha,
                            descrLt, 
                            d_cscVal,
                            d_cscColPtr, 
                            d_cscRowInd,  
                            1, 
                            info,
                            d_b,
                            m,
                            d_x,
                            m,
                            CUSPARSE_SOLVE_POLICY_NO_LEVEL,
                            d_pBuffer_csc);
        cudaDeviceSynchronize();
        if (sp_status != CUSPARSE_STATUS_SUCCESS)
            printf("CSR solve error %s\n",
                cusparseGetErrorString(sp_status));

        sp_status = cusparseXbsrsm2_zeroPivot(handle, info, &numerical_zero);
        if (CUSPARSE_STATUS_ZERO_PIVOT == sp_status) {
            printf("L(%d,%d) is zero\n", numerical_zero, numerical_zero);

        err = cudaGetLastError();
        if (err != cudaSuccess)
            printf("CSR solve %s\n", cudaGetErrorString(err));
            }
        // Copy results back to device
        cudaMemcpy(x, d_x, sizeof(double) * m * ncol, cudaMemcpyDeviceToHost);
    }
    cudaDeviceSynchronize();
    auto stop = std::chrono::high_resolution_clock::now();

    // Calculate calculatiom time
    std::chrono::duration<double> duration = (stop - start);
    FILE *temp = fopen("time.log", "a");

    time_t current_time;
    current_time = time(NULL);
    fprintf(temp, "Run on %s %s\n", ctime(&current_time));

    fprintf(temp, "Duration perf %.5lf\n", duration.count() / REPET);
    fflush(temp);
    fclose(temp);
    printf("Duration perf %.5lf\n", duration.count() / REPET);


    // Post processing
    cusparseDestroy(handle);
    cudaFree(d_x);
    cudaFree(d_b);
    cudaFree(d_I);
    cudaFree(d_J);
    cudaFree(d_V);
    cudaFree(d_csrRowPtr);
    cudaFree(d_cscColPtr);

    return 0;
}
*/

};
