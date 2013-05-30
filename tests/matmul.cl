#define CLK_LOCAL_MEM_FENCE 0

__kernel void matmul_elem(
  const int dim,
//  const int Mdim,
//  const int Ndim,
//  const int Pdim,
  __global float* A,
  __global float* B,
  __global float* C)
{
  int k;
  int i = get_global_id(0);
  int j = get_global_id(1);
  float tmp;
  //if( (i < Ndim) && (j <Mdim))
  if ( (i < dim) && (j < dim) )
  {
    tmp = 0.0f;
    //for(k=0; k<Pdim; k++)
    for(k=0; k<dim; k++)
    {
      //tmp         += A[i*Ndim+k] *  B[k*Pdim+j];
      tmp         += A[i*dim+k] *  B[k*dim+j];
    }
    //C[i*Ndim+j] = tmp;
    C[i*dim+j] = tmp;
  }
}

__kernel void matmul_row(
  const int dim,
//  const int Mdim,
//  const int Ndim,
//  const int Pdim,
  __global float* A,
  __global float* B,
  __global float* C)
{
  int k,j;
  int i = get_global_id(0);
  float tmp;
//  if( (i < Ndim) )
  if( (i < dim) )
  {
//    for(j=0;j<Mdim;j++){
    for(j=0;j<dim;j++){
      tmp = 0.0f;
//      for(k=0;k<Pdim;k++)
      for(k=0;k<dim;k++)
//        tmp         += A[i*Ndim+k] *  B[k*Pdim+j];
        tmp         += A[i*dim+k] *  B[k*dim+j];
//      C[i*Ndim+j] = tmp;
      C[i*dim+j] = tmp;
    }
  }
}

__kernel void matmul_row_priv(
  const int dim,
//  const int Mdim,
//  const int Ndim,
//  const int Pdim,
  __global float* A,
  __global float* B,
  __global float* C)
{
  int k,j;
  int i = get_global_id(0);
  float Awrk[16];
  float tmp;
//  if( (i < Ndim) )
  if( (i < dim) )
  {
//    for(k=0;k<Pdim;k++)
    for(k=0;k<dim;k++)
//      Awrk[k] = A[i*Ndim+k];
      Awrk[k] = A[i*dim+k];

//    for(j=0;j<Mdim;j++){
    for(j=0;j<dim;j++){
      tmp = 0.0f;
//      for(k=0;k<Pdim;k++)
      for(k=0;k<dim;k++)
//        tmp         += Awrk[k] *  B[k*Pdim+j];
        tmp         += Awrk[k] *  B[k*dim+j];
//      C[i*Ndim+j] = tmp;
      C[i*dim+j] = tmp;
    }
  }
}

__kernel void matmul_row_local(
  const int Mdim,
  const int Ndim,
  const int Pdim,
  __global float* A,
  __global float* B,
  __global float* C,
  __local  float* Bwrk)
{
  int k,j;
  int i    = get_global_id(0);
  int iloc = get_local_id(0);
  int nloc = get_local_size(0);
  float Awrk[1024];
  float tmp;
  if( (i < Ndim) )
  {
    for(k=0;k<Pdim;k++)
      Awrk[k] = A[i*Ndim+k];

    for(j=0;j<Mdim;j++){
      for(k=iloc;k<Pdim;k=k+nloc)
        Bwrk[k] = B[k*Pdim+j];
      barrier(CLK_LOCAL_MEM_FENCE);
      tmp = 0.0f;
      for(k=0;k<Pdim;k++)
        tmp         += Awrk[k] *  Bwrk[k];
      C[i*Ndim+j] = tmp;
    }
  }
}

/*
 * Copyright 1993-2010 NVIDIA Corporation.  All rights reserved.
 *
 * Please refer to the NVIDIA end user license agreement (EULA) associated
 * with this source code for terms and conditions that govern your use of
 * this software. Any use, reproduction, disclosure, or distribution of
 * this software and related documentation outside the terms of the EULA
 * is strictly prohibited.
 *
 */

/* Matrix multiplication: C = A * B.
 * Device code.
 */
#define BLOCK_SIZE 16
#define AS(i, j) As[j + i * BLOCK_SIZE]
#define BS(i, j) Bs[j + i * BLOCK_SIZE]

///////////////////////////////////////////////////////////////////////////////
//! Matrix multiplication on the device: C = A * B
//! uiWA is A's width and uiWB is B's width
////////////////////////////////////////////////////////////////////////////////
__kernel void
matmul_block(int uiWA, int uiWB, int uiWC,
             __global float* C, __global float* A, __global float* B,
             __local float* As, __local float* Bs)
{
  // Block index
  int bx = get_group_id(0);
  int by = get_group_id(1);

  // Thread index
  int tx = get_local_id(0);
  int ty = get_local_id(1);

  // Index of the first sub-matrix of A processed by the block
  int aBegin = uiWA * BLOCK_SIZE * by;

  // Index of the last sub-matrix of A processed by the block
  int aEnd   = aBegin + uiWA - 1;

  // Step size used to iterate through the sub-matrices of A
  int aStep  = BLOCK_SIZE;

  // Index of the first sub-matrix of B processed by the block
  int bBegin = BLOCK_SIZE * bx;

  // Step size used to iterate through the sub-matrices of B
  int bStep  = BLOCK_SIZE * uiWB;

  // Csub is used to store the element of the block sub-matrix
  // that is computed by the thread
  float Csub = 0.0f;

  // Loop over all the sub-matrices of A and B
  // required to compute the block sub-matrix
  for (int a = aBegin, b = bBegin;
       a <= aEnd;
       a += aStep, b += bStep) {

    // Load the matrices from device memory
    // to shared memory; each thread loads
    // one element of each matrix
    AS(ty, tx) = A[a + uiWA * ty + tx];
    BS(ty, tx) = B[b + uiWB * ty + tx];

    // Synchronize to make sure the matrices are loaded
    barrier(CLK_LOCAL_MEM_FENCE);

    // Multiply the two matrices together;
    // each thread computes one element
    // of the block sub-matrix
#pragma unroll
    for (int k = 0; k < BLOCK_SIZE; ++k)
      Csub += AS(ty, k) * BS(k, tx);

    // Synchronize to make sure that the preceding
    // computation is done before loading two new
    // sub-matrices of A and B in the next iteration
    barrier(CLK_LOCAL_MEM_FENCE);
  }

  // Write the block sub-matrix to device memory;
  // each thread writes one element
  C[get_global_id(1) * get_global_size(0) + get_global_id(0)] = Csub;

}