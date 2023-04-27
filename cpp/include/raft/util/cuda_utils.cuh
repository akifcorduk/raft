/*
 * Copyright (c) 2018-2023, NVIDIA CORPORATION.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#pragma once

#include <math_constants.h>
#include <stdint.h>
#include <type_traits>

#include <raft/core/cudart_utils.hpp>
#include <raft/core/math.hpp>
#include <raft/core/operators.hpp>
#include <raft/util/cuda_dev_essentials.cuh>

namespace raft {

/** Device function to have atomic add support for older archs */
template <typename Type>
DI void myAtomicAdd(Type* address, Type val)
{
  atomicAdd(address, val);
}

#if defined(__CUDA_ARCH__) && (__CUDA_ARCH__ < 600)
// Ref:
// http://on-demand.gputechconf.com/gtc/2013/presentations/S3101-Atomic-Memory-Operations.pdf
template <>
DI void myAtomicAdd(double* address, double val)
{
  unsigned long long int* address_as_ull = (unsigned long long int*)address;
  unsigned long long int old             = *address_as_ull, assumed;
  do {
    assumed = old;
    old =
      atomicCAS(address_as_ull, assumed, __double_as_longlong(val + __longlong_as_double(assumed)));
  } while (assumed != old);
}
#endif

template <typename T, typename ReduceLambda>
DI void myAtomicReduce(T* address, T val, ReduceLambda op);

template <typename ReduceLambda>
DI void myAtomicReduce(double* address, double val, ReduceLambda op)
{
  unsigned long long int* address_as_ull = (unsigned long long int*)address;
  unsigned long long int old             = *address_as_ull, assumed;
  do {
    assumed = old;
    old     = atomicCAS(
      address_as_ull, assumed, __double_as_longlong(op(val, __longlong_as_double(assumed))));
  } while (assumed != old);
}

template <typename ReduceLambda>
DI void myAtomicReduce(float* address, float val, ReduceLambda op)
{
  unsigned int* address_as_uint = (unsigned int*)address;
  unsigned int old              = *address_as_uint, assumed;
  do {
    assumed = old;
    old = atomicCAS(address_as_uint, assumed, __float_as_uint(op(val, __uint_as_float(assumed))));
  } while (assumed != old);
}

template <typename ReduceLambda>
DI void myAtomicReduce(int* address, int val, ReduceLambda op)
{
  int old = *address, assumed;
  do {
    assumed = old;
    old     = atomicCAS(address, assumed, op(val, assumed));
  } while (assumed != old);
}

template <typename ReduceLambda>
DI void myAtomicReduce(long long* address, long long val, ReduceLambda op)
{
  long long old = *address, assumed;
  do {
    assumed = old;
    old     = atomicCAS(address, assumed, op(val, assumed));
  } while (assumed != old);
}

template <typename ReduceLambda>
DI void myAtomicReduce(unsigned long long* address, unsigned long long val, ReduceLambda op)
{
  unsigned long long old = *address, assumed;
  do {
    assumed = old;
    old     = atomicCAS(address, assumed, op(val, assumed));
  } while (assumed != old);
}

/**
 * @brief Provide atomic min operation.
 * @tparam T: data type for input data (float or double).
 * @param[in] address: address to read old value from, and to atomically update w/ min(old value,
 * val)
 * @param[in] val: new value to compare with old
 */
template <typename T>
DI T myAtomicMin(T* address, T val);

/**
 * @brief Provide atomic max operation.
 * @tparam T: data type for input data (float or double).
 * @param[in] address: address to read old value from, and to atomically update w/ max(old value,
 * val)
 * @param[in] val: new value to compare with old
 */
template <typename T>
DI T myAtomicMax(T* address, T val);

DI float myAtomicMin(float* address, float val)
{
  myAtomicReduce<float(float, float)>(address, val, fminf);
  return *address;
}

DI float myAtomicMax(float* address, float val)
{
  myAtomicReduce<float(float, float)>(address, val, fmaxf);
  return *address;
}

DI double myAtomicMin(double* address, double val)
{
  myAtomicReduce<double(double, double)>(address, val, fmin);
  return *address;
}

DI double myAtomicMax(double* address, double val)
{
  myAtomicReduce<double(double, double)>(address, val, fmax);
  return *address;
}

/**
 * @defgroup Max maximum of two numbers
 * @{
 */
template <typename T>
HDI T myMax(T x, T y);
template <>
[[deprecated("use raft::max from raft/core/math.hpp instead")]] HDI float myMax<float>(float x,
                                                                                       float y)
{
  return fmaxf(x, y);
}
template <>
[[deprecated("use raft::max from raft/core/math.hpp instead")]] HDI double myMax<double>(double x,
                                                                                         double y)
{
  return fmax(x, y);
}
/** @} */

/**
 * @defgroup Min minimum of two numbers
 * @{
 */
template <typename T>
HDI T myMin(T x, T y);
template <>
[[deprecated("use raft::min from raft/core/math.hpp instead")]] HDI float myMin<float>(float x,
                                                                                       float y)
{
  return fminf(x, y);
}
template <>
[[deprecated("use raft::min from raft/core/math.hpp instead")]] HDI double myMin<double>(double x,
                                                                                         double y)
{
  return fmin(x, y);
}
/** @} */

/**
 * @brief Provide atomic min operation.
 * @tparam T: data type for input data (float or double).
 * @param[in] address: address to read old value from, and to atomically update w/ min(old value,
 * val)
 * @param[in] val: new value to compare with old
 */
template <typename T>
DI T myAtomicMin(T* address, T val)
{
  myAtomicReduce(address, val, raft::min_op{});
  return *address;
}

/**
 * @brief Provide atomic max operation.
 * @tparam T: data type for input data (float or double).
 * @param[in] address: address to read old value from, and to atomically update w/ max(old value,
 * val)
 * @param[in] val: new value to compare with old
 */
template <typename T>
DI T myAtomicMax(T* address, T val)
{
  myAtomicReduce(address, val, raft::max_op{});
  return *address;
}

/**
 * @defgroup Exp Exponential function
 * @{
 */
template <typename T>
HDI T myExp(T x);
template <>
[[deprecated("use raft::exp from raft/core/math.hpp instead")]] HDI float myExp(float x)
{
  return expf(x);
}
template <>
[[deprecated("use raft::exp from raft/core/math.hpp instead")]] HDI double myExp(double x)
{
  return ::exp(x);
}
/** @} */

/**
 * @defgroup Cuda infinity values
 * @{
 */
template <typename T>
inline __device__ T myInf();
template <>
inline __device__ float myInf<float>()
{
  return CUDART_INF_F;
}
template <>
inline __device__ double myInf<double>()
{
  return CUDART_INF;
}
/** @} */

/**
 * @defgroup Log Natural logarithm
 * @{
 */
template <typename T>
HDI T myLog(T x);
template <>
[[deprecated("use raft::log from raft/core/math.hpp instead")]] HDI float myLog(float x)
{
  return logf(x);
}
template <>
[[deprecated("use raft::log from raft/core/math.hpp instead")]] HDI double myLog(double x)
{
  return ::log(x);
}
/** @} */

/**
 * @defgroup Sqrt Square root
 * @{
 */
template <typename T>
HDI T mySqrt(T x);
template <>
[[deprecated("use raft::sqrt from raft/core/math.hpp instead")]] HDI float mySqrt(float x)
{
  return sqrtf(x);
}
template <>
[[deprecated("use raft::sqrt from raft/core/math.hpp instead")]] HDI double mySqrt(double x)
{
  return ::sqrt(x);
}
/** @} */

/**
 * @defgroup SineCosine Sine and cosine calculation
 * @{
 */
template <typename T>
DI void mySinCos(T x, T& s, T& c);
template <>
[[deprecated("use raft::sincos from raft/core/math.hpp instead")]] DI void mySinCos(float x,
                                                                                    float& s,
                                                                                    float& c)
{
  sincosf(x, &s, &c);
}
template <>
[[deprecated("use raft::sincos from raft/core/math.hpp instead")]] DI void mySinCos(double x,
                                                                                    double& s,
                                                                                    double& c)
{
  ::sincos(x, &s, &c);
}
/** @} */

/**
 * @defgroup Sine Sine calculation
 * @{
 */
template <typename T>
DI T mySin(T x);
template <>
[[deprecated("use raft::sin from raft/core/math.hpp instead")]] DI float mySin(float x)
{
  return sinf(x);
}
template <>
[[deprecated("use raft::sin from raft/core/math.hpp instead")]] DI double mySin(double x)
{
  return ::sin(x);
}
/** @} */

/**
 * @defgroup Abs Absolute value
 * @{
 */
template <typename T>
DI T myAbs(T x)
{
  return x < 0 ? -x : x;
}
template <>
[[deprecated("use raft::abs from raft/core/math.hpp instead")]] DI float myAbs(float x)
{
  return fabsf(x);
}
template <>
[[deprecated("use raft::abs from raft/core/math.hpp instead")]] DI double myAbs(double x)
{
  return fabs(x);
}
/** @} */

/**
 * @defgroup Pow Power function
 * @{
 */
template <typename T>
HDI T myPow(T x, T power);
template <>
[[deprecated("use raft::pow from raft/core/math.hpp instead")]] HDI float myPow(float x,
                                                                                float power)
{
  return powf(x, power);
}
template <>
[[deprecated("use raft::pow from raft/core/math.hpp instead")]] HDI double myPow(double x,
                                                                                 double power)
{
  return ::pow(x, power);
}
/** @} */

/**
 * @defgroup myTanh tanh function
 * @{
 */
template <typename T>
HDI T myTanh(T x);
template <>
[[deprecated("use raft::tanh from raft/core/math.hpp instead")]] HDI float myTanh(float x)
{
  return tanhf(x);
}
template <>
[[deprecated("use raft::tanh from raft/core/math.hpp instead")]] HDI double myTanh(double x)
{
  return ::tanh(x);
}
/** @} */

/**
 * @defgroup myATanh arctanh function
 * @{
 */
template <typename T>
HDI T myATanh(T x);
template <>
[[deprecated("use raft::atanh from raft/core/math.hpp instead")]] HDI float myATanh(float x)
{
  return atanhf(x);
}
template <>
[[deprecated("use raft::atanh from raft/core/math.hpp instead")]] HDI double myATanh(double x)
{
  return ::atanh(x);
}
/** @} */

/**
 * @defgroup LambdaOps Legacy lambda operations, to be deprecated
 * @{
 */
template <typename Type, typename IdxType = int>
struct Nop {
  [[deprecated("Nop is deprecated. Use identity_op instead.")]] HDI Type
  operator()(Type in, IdxType i = 0) const
  {
    return in;
  }
};

template <typename Type, typename IdxType = int>
struct SqrtOp {
  [[deprecated("SqrtOp is deprecated. Use sqrt_op instead.")]] HDI Type
  operator()(Type in, IdxType i = 0) const
  {
    return raft::sqrt(in);
  }
};

template <typename Type, typename IdxType = int>
struct L0Op {
  [[deprecated("L0Op is deprecated. Use nz_op instead.")]] HDI Type operator()(Type in,
                                                                               IdxType i = 0) const
  {
    return in != Type(0) ? Type(1) : Type(0);
  }
};

template <typename Type, typename IdxType = int>
struct L1Op {
  [[deprecated("L1Op is deprecated. Use abs_op instead.")]] HDI Type operator()(Type in,
                                                                                IdxType i = 0) const
  {
    return raft::abs(in);
  }
};

template <typename Type, typename IdxType = int>
struct L2Op {
  [[deprecated("L2Op is deprecated. Use sq_op instead.")]] HDI Type operator()(Type in,
                                                                               IdxType i = 0) const
  {
    return in * in;
  }
};

template <typename InT, typename OutT = InT>
struct Sum {
  [[deprecated("Sum is deprecated. Use add_op instead.")]] HDI OutT operator()(InT a, InT b) const
  {
    return a + b;
  }
};

template <typename Type>
struct Max {
  [[deprecated("Max is deprecated. Use max_op instead.")]] HDI Type operator()(Type a, Type b) const
  {
    if (b > a) { return b; }
    return a;
  }
};
/** @} */

/**
 * @defgroup Sign Obtain sign value
 * @brief Obtain sign of x
 * @param x input
 * @return +1 if x >= 0 and -1 otherwise
 * @{
 */
template <typename T>
DI T signPrim(T x)
{
  return x < 0 ? -1 : +1;
}
template <>
DI float signPrim(float x)
{
  return signbit(x) == true ? -1.0f : +1.0f;
}
template <>
DI double signPrim(double x)
{
  return signbit(x) == true ? -1.0 : +1.0;
}
/** @} */

/**
 * @defgroup Max maximum of two numbers
 * @brief Obtain maximum of two values
 * @param x one item
 * @param y second item
 * @return maximum of two items
 * @{
 */
template <typename T>
DI T maxPrim(T x, T y)
{
  return x > y ? x : y;
}
template <>
DI float maxPrim(float x, float y)
{
  return fmaxf(x, y);
}
template <>
DI double maxPrim(double x, double y)
{
  return fmax(x, y);
}
/** @} */

/** apply a warp-wide fence (useful from Volta+ archs) */
DI void warpFence()
{
#if __CUDA_ARCH__ >= 700
  __syncwarp();
#endif
}

/** warp-wide any boolean aggregator */
DI bool any(bool inFlag, uint32_t mask = 0xffffffffu)
{
#if CUDART_VERSION >= 9000
  inFlag = __any_sync(mask, inFlag);
#else
  inFlag = __any(inFlag);
#endif
  return inFlag;
}

/** warp-wide all boolean aggregator */
DI bool all(bool inFlag, uint32_t mask = 0xffffffffu)
{
#if CUDART_VERSION >= 9000
  inFlag = __all_sync(mask, inFlag);
#else
  inFlag = __all(inFlag);
#endif
  return inFlag;
}

/** For every thread in the warp, set the corresponding bit to the thread's flag value.  */
DI uint32_t ballot(bool inFlag, uint32_t mask = 0xffffffffu)
{
#if CUDART_VERSION >= 9000
  return __ballot_sync(mask, inFlag);
#else
  return __ballot(inFlag);
#endif
}

/** True CUDA alignment of a type (adapted from CUB) */
template <typename T>
struct cuda_alignment {
  struct Pad {
    T val;
    char byte;
  };

  static constexpr int bytes = sizeof(Pad) - sizeof(T);
};

template <typename LargeT, typename UnitT>
struct is_multiple {
  static constexpr int large_align_bytes = cuda_alignment<LargeT>::bytes;
  static constexpr int unit_align_bytes  = cuda_alignment<UnitT>::bytes;
  static constexpr bool value =
    (sizeof(LargeT) % sizeof(UnitT) == 0) && (large_align_bytes % unit_align_bytes == 0);
};

template <typename LargeT, typename UnitT>
inline constexpr bool is_multiple_v = is_multiple<LargeT, UnitT>::value;

template <typename T>
struct is_shuffleable {
  static constexpr bool value =
    std::is_same_v<T, int> || std::is_same_v<T, unsigned int> || std::is_same_v<T, long> ||
    std::is_same_v<T, unsigned long> || std::is_same_v<T, long long> ||
    std::is_same_v<T, unsigned long long> || std::is_same_v<T, float> || std::is_same_v<T, double>;
};

template <typename T>
inline constexpr bool is_shuffleable_v = is_shuffleable<T>::value;

/**
 * @brief Shuffle the data inside a warp
 * @tparam T the data type
 * @param val value to be shuffled
 * @param srcLane lane from where to shuffle
 * @param width lane width
 * @param mask mask of participating threads (Volta+)
 * @return the shuffled data
 */
template <typename T>
DI std::enable_if_t<is_shuffleable_v<T>, T> shfl(T val,
                                                 int srcLane,
                                                 int width     = WarpSize,
                                                 uint32_t mask = 0xffffffffu)
{
#if CUDART_VERSION >= 9000
  return __shfl_sync(mask, val, srcLane, width);
#else
  return __shfl(val, srcLane, width);
#endif
}

/// Overload of shfl for data types not supported by the CUDA intrinsics
template <typename T>
DI std::enable_if_t<!is_shuffleable_v<T>, T> shfl(T val,
                                                  int srcLane,
                                                  int width     = WarpSize,
                                                  uint32_t mask = 0xffffffffu)
{
  using UnitT =
    std::conditional_t<is_multiple_v<T, int>,
                       unsigned int,
                       std::conditional_t<is_multiple_v<T, short>, unsigned short, unsigned char>>;

  constexpr int n_words = sizeof(T) / sizeof(UnitT);

  T output;
  UnitT* output_alias = reinterpret_cast<UnitT*>(&output);
  UnitT* input_alias  = reinterpret_cast<UnitT*>(&val);

  unsigned int shuffle_word;
  shuffle_word    = shfl((unsigned int)input_alias[0], srcLane, width, mask);
  output_alias[0] = shuffle_word;

#pragma unroll
  for (int i = 1; i < n_words; ++i) {
    shuffle_word    = shfl((unsigned int)input_alias[i], srcLane, width, mask);
    output_alias[i] = shuffle_word;
  }

  return output;
}

/**
 * @brief Shuffle the data inside a warp from lower lane IDs
 * @tparam T the data type
 * @param val value to be shuffled
 * @param delta lower lane ID delta from where to shuffle
 * @param width lane width
 * @param mask mask of participating threads (Volta+)
 * @return the shuffled data
 */
template <typename T>
DI std::enable_if_t<is_shuffleable_v<T>, T> shfl_up(T val,
                                                    int delta,
                                                    int width     = WarpSize,
                                                    uint32_t mask = 0xffffffffu)
{
#if CUDART_VERSION >= 9000
  return __shfl_up_sync(mask, val, delta, width);
#else
  return __shfl_up(val, delta, width);
#endif
}

/// Overload of shfl_up for data types not supported by the CUDA intrinsics
template <typename T>
DI std::enable_if_t<!is_shuffleable_v<T>, T> shfl_up(T val,
                                                     int delta,
                                                     int width     = WarpSize,
                                                     uint32_t mask = 0xffffffffu)
{
  using UnitT =
    std::conditional_t<is_multiple_v<T, int>,
                       unsigned int,
                       std::conditional_t<is_multiple_v<T, short>, unsigned short, unsigned char>>;

  constexpr int n_words = sizeof(T) / sizeof(UnitT);

  T output;
  UnitT* output_alias = reinterpret_cast<UnitT*>(&output);
  UnitT* input_alias  = reinterpret_cast<UnitT*>(&val);

  unsigned int shuffle_word;
  shuffle_word    = shfl_up((unsigned int)input_alias[0], delta, width, mask);
  output_alias[0] = shuffle_word;

#pragma unroll
  for (int i = 1; i < n_words; ++i) {
    shuffle_word    = shfl_up((unsigned int)input_alias[i], delta, width, mask);
    output_alias[i] = shuffle_word;
  }

  return output;
}

/**
 * @brief Shuffle the data inside a warp
 * @tparam T the data type
 * @param val value to be shuffled
 * @param laneMask mask to be applied in order to perform xor shuffle
 * @param width lane width
 * @param mask mask of participating threads (Volta+)
 * @return the shuffled data
 */
template <typename T>
DI std::enable_if_t<is_shuffleable_v<T>, T> shfl_xor(T val,
                                                     int laneMask,
                                                     int width     = WarpSize,
                                                     uint32_t mask = 0xffffffffu)
{
#if CUDART_VERSION >= 9000
  return __shfl_xor_sync(mask, val, laneMask, width);
#else
  return __shfl_xor(val, laneMask, width);
#endif
}

/// Overload of shfl_xor for data types not supported by the CUDA intrinsics
template <typename T>
DI std::enable_if_t<!is_shuffleable_v<T>, T> shfl_xor(T val,
                                                      int laneMask,
                                                      int width     = WarpSize,
                                                      uint32_t mask = 0xffffffffu)
{
  using UnitT =
    std::conditional_t<is_multiple_v<T, int>,
                       unsigned int,
                       std::conditional_t<is_multiple_v<T, short>, unsigned short, unsigned char>>;

  constexpr int n_words = sizeof(T) / sizeof(UnitT);

  T output;
  UnitT* output_alias = reinterpret_cast<UnitT*>(&output);
  UnitT* input_alias  = reinterpret_cast<UnitT*>(&val);

  unsigned int shuffle_word;
  shuffle_word    = shfl_xor((unsigned int)input_alias[0], laneMask, width, mask);
  output_alias[0] = shuffle_word;

#pragma unroll
  for (int i = 1; i < n_words; ++i) {
    shuffle_word    = shfl_xor((unsigned int)input_alias[i], laneMask, width, mask);
    output_alias[i] = shuffle_word;
  }

  return output;
}

/**
 * @brief Four-way byte dot product-accumulate.
 * @tparam T Four-byte integer: int or unsigned int
 * @tparam S Either same as T or a 4-byte vector of the same signedness.
 *
 * @param a
 * @param b
 * @param c
 * @return dot(a, b) + c
 */
template <typename T, typename S = T>
DI auto dp4a(S a, S b, T c) -> T;

template <>
DI auto dp4a(char4 a, char4 b, int c) -> int
{
#if __CUDA_ARCH__ >= 610
  return __dp4a(a, b, c);
#else
  c += static_cast<int>(a.x) * static_cast<int>(b.x);
  c += static_cast<int>(a.y) * static_cast<int>(b.y);
  c += static_cast<int>(a.z) * static_cast<int>(b.z);
  c += static_cast<int>(a.w) * static_cast<int>(b.w);
  return c;
#endif
}

template <>
DI auto dp4a(uchar4 a, uchar4 b, unsigned int c) -> unsigned int
{
#if __CUDA_ARCH__ >= 610
  return __dp4a(a, b, c);
#else
  c += static_cast<unsigned int>(a.x) * static_cast<unsigned int>(b.x);
  c += static_cast<unsigned int>(a.y) * static_cast<unsigned int>(b.y);
  c += static_cast<unsigned int>(a.z) * static_cast<unsigned int>(b.z);
  c += static_cast<unsigned int>(a.w) * static_cast<unsigned int>(b.w);
  return c;
#endif
}

template <>
DI auto dp4a(int a, int b, int c) -> int
{
#if __CUDA_ARCH__ >= 610
  return __dp4a(a, b, c);
#else
  return dp4a(*reinterpret_cast<char4*>(&a), *reinterpret_cast<char4*>(&b), c);
#endif
}

template <>
DI auto dp4a(unsigned int a, unsigned int b, unsigned int c) -> unsigned int
{
#if __CUDA_ARCH__ >= 610
  return __dp4a(a, b, c);
#else
  return dp4a(*reinterpret_cast<uchar4*>(&a), *reinterpret_cast<uchar4*>(&b), c);
#endif
}

/**
 * @brief Logical-warp-level reduction
 * @tparam logicalWarpSize Logical warp size (2, 4, 8, 16 or 32)
 * @tparam T Value type to be reduced
 * @tparam ReduceLambda Reduction operation type
 * @param val input value
 * @param reduce_op Reduction operation
 * @return Reduction result. All lanes will have the valid result.
 */
template <int logicalWarpSize, typename T, typename ReduceLambda>
DI T logicalWarpReduce(T val, ReduceLambda reduce_op)
{
#pragma unroll
  for (int i = logicalWarpSize / 2; i > 0; i >>= 1) {
    T tmp = shfl_xor(val, i);
    val   = reduce_op(val, tmp);
  }
  return val;
}

/**
 * @brief Warp-level reduction
 * @tparam T Value type to be reduced
 * @tparam ReduceLambda Reduction operation type
 * @param val input value
 * @param reduce_op Reduction operation
 * @return Reduction result. All lanes will have the valid result.
 * @note Why not cub? Because cub doesn't seem to allow working with arbitrary
 *       number of warps in a block. All threads in the warp must enter this
 *       function together
 */
template <typename T, typename ReduceLambda>
DI T warpReduce(T val, ReduceLambda reduce_op)
{
  return logicalWarpReduce<WarpSize>(val, reduce_op);
}

/**
 * @brief Warp-level reduction
 * @tparam T Value type to be reduced
 * @param val input value
 * @return Reduction result. All lanes will have the valid result.
 * @note Why not cub? Because cub doesn't seem to allow working with arbitrary
 *       number of warps in a block. All threads in the warp must enter this
 *       function together
 */
template <typename T>
DI T warpReduce(T val)
{
  return warpReduce(val, raft::add_op{});
}

/**
 * @brief 1-D block-level reduction
 * @param val input value
 * @param smem shared memory region needed for storing intermediate results. It
 *             must alteast be of size: `sizeof(T) * nWarps`
 * @param reduce_op a binary reduction operation.
 * @return only the thread0 will contain valid reduced result
 * @note Why not cub? Because cub doesn't seem to allow working with arbitrary
 *       number of warps in a block. All threads in the block must enter this
 *       function together. cub also uses too many registers
 */
template <typename T, typename ReduceLambda>
DI T blockReduce(T val, char* smem, ReduceLambda reduce_op = raft::add_op{})
{
  auto* sTemp = reinterpret_cast<T*>(smem);
  int nWarps  = (blockDim.x + WarpSize - 1) / WarpSize;
  int lid     = laneId();
  int wid     = threadIdx.x / WarpSize;
  val         = warpReduce(val, reduce_op);
  if (lid == 0) sTemp[wid] = val;
  __syncthreads();
  val = lid < nWarps ? sTemp[lid] : T(0);
  return warpReduce(val, reduce_op);
}

/**
 * @brief 1-D warp-level weighted random reduction which returns the rank.
 * used conditional probability to return the weighted random rank of the result.
 * @param rng random number generator, must have next_u32() function
 * @param weight weight of the rank/index.
 * @param idx index to be used as rank
 * @return only the thread0 will contain valid reduced result
 */
template <typename T, typename rng_t, typename i_t = int>
__device__ inline T warpRandomReduce(rng_t& rng, T& weight, i_t& idx)
{
#pragma unroll
  for (i_t offset = raft::WarpSize / 2; offset > 0; offset /= 2) {
    T tmp_weight = shfl(weight, laneId() + offset);
    i_t tmp_idx  = shfl(idx, laneId() + offset);
    T sum        = (tmp_weight + weight);
    weight       = sum;
    if (sum != 0) {
      i_t rnd_number = (rng.next_u32() % sum);
      if (rnd_number < tmp_weight) { idx = tmp_idx; }
    }
  }
}

/**
 * @brief 1-D block-level weighted random reduction which returns the rank.
 * used conditional probability to return the weighted random rank of the result.
 * @param rng random number generator, must have next_u32() function
 * @param shbuf shared memory region needed for storing intermediate results. It
 *             must alteast be of size: `(sizeof(T) + sizeof(i_t)) * WarpSize`
 * @param weight weight of the rank/index.
 * @param idx index to be used as rank
 * @return only the thread0 will contain valid reduced result
 */
template <typename T, typename rng_t, typename i_t = int>
__inline__ __device__ i_t
blockRandomReduce(rng_t rng, T* shbuf, T weight = 1, i_t idx = threadIdx.x)
{
  T* values    = shbuf;
  i_t* indices = (i_t*)&shbuf[WarpSize];
  i_t wid      = threadIdx.x / WarpSize;
  i_t nWarps   = (blockDim.x + WarpSize - 1) / WarpSize;
  warpRandomReduce(rng, weight, idx);  // Each warp performs partial reduction
  i_t lane = laneId();
  if (lane == 0) {
    values[wid]  = weight;  // Write reduced value to shared memory
    indices[wid] = idx;     // Write reduced value to shared memory
  }

  __syncthreads();  // Wait for all partial reductions

  // read from shared memory only if that warp existed
  if (lane < nWarps) {
    weight = values[lane];
    idx    = indices[lane];
  } else {
    // get the min if it is a max op, get the max if it is a min op
    weight = 0;
    idx    = -1;
  }
  __syncthreads();
  if (wid == 0) warpRandomReduce(rng, weight, idx);
  return idx;
}

/**
 * @brief 1-D warp-level ranked reduction which returns the value and rank.
 * thread 0 will have valid result and rank(idx).
 * @param val input value
 * @param idx index to be used as rank
 * @param reduce_op a binary reduction operation.
 * @return only the thread0 will contain valid reduced result
 */
template <typename T, typename ReduceLambda, typename i_t = int>
__inline__ __device__ void warpRankedReduce(T& val,
                                            i_t& idx,
                                            ReduceLambda reduce_op = raft::min_op{})
{
#pragma unroll
  for (i_t offset = WarpSize / 2; offset > 0; offset /= 2) {
    T tmpVal   = shfl(val, laneId() + offset);
    i_t tmpIdx = shfl(idx, laneId() + offset);
    if (reduce_op(tmpVal, val) == tmpVal) {
      val = tmpVal;
      idx = tmpIdx;
    }
  }
}

/**
 * @brief 1-D block-level ranked reduction which returns the value and rank.
 * thread 0 will have valid result and rank(idx).
 * @param val input value
 * @param smem shared memory region needed for storing intermediate results. It
 *             must alteast be of size: `(sizeof(T) + sizeof(i_t)) * WarpSize`
 * @param idx index to be used as rank
 * @param reduce_op a binary reduction operation.
 * @return only the thread0 will contain valid reduced result
 */
template <typename T, typename ReduceLambda, typename i_t = int>
__inline__ __device__ std::pair<T, i_t> blockRankedReduce(T val,
                                                          T* shbuf,
                                                          i_t idx                = threadIdx.x,
                                                          ReduceLambda reduce_op = raft::min_op{})
{
  T* values    = shbuf;
  i_t* indices = (i_t*)&shbuf[WarpSize];
  i_t wid      = threadIdx.x / WarpSize;
  i_t nWarps   = (blockDim.x + WarpSize - 1) / WarpSize;
  warpRankedReduce(val, idx, reduce_op);  // Each warp performs partial reduction
  i_t lane = laneId();
  if (lane == 0) {
    values[wid]  = val;  // Write reduced value to shared memory
    indices[wid] = idx;  // Write reduced value to shared memory
  }

  __syncthreads();  // Wait for all partial reductions

  // read from shared memory only if that warp existed
  if (lane < nWarps) {
    val = values[lane];
    idx = indices[lane];
  } else {
    // get the min if it is a max op, get the max if it is a min op
    val = reduce_op(std::numeric_limits<T>::min(), std::numeric_limits<T>::max()) ==
              std::numeric_limits<T>::min()
            ? std::numeric_limits<T>::max()
            : std::numeric_limits<T>::min();
    idx = -1;
  }
  __syncthreads();
  if (wid == 0) warpRankedReduce(val, idx, reduce_op);
  return std::pair<T, i_t>{val, idx};
}

/**
 * @brief Executes a 1d binary block reduce
 * @param val binary value to be reduced across the thread block
 * @param reduce_op a binary reduction operation.
 * @return only the thread0 will contain valid reduced result
 */
template <int BLOCK_SIZE, typename i_t>
DI i_t binaryBlockReduce(i_t val, i_t* shared)
{
  static_assert(BLOCK_SIZE <= 1024);
  assert(val == 0 || val == 1);
  const uint32_t mask    = __ballot_sync(~0, val);
  const uint32_t n_items = __popc(mask);

  // Each first thread of the warp
  if (threadIdx.x % WarpSize == 0) shared[threadIdx.x / WarpSize] = n_items;
  __syncthreads();

  val = (threadIdx.x < BLOCK_SIZE / WarpSize) ? shared[threadIdx.x] : 0;

  if (threadIdx.x < WarpSize)
    return warpReduce(val);
  else  // Only first warp gets the results
    return -1;
}

/**
 * @brief Simple utility function to determine whether user_stream or one of the
 * internal streams should be used.
 * @param user_stream main user stream
 * @param int_streams array of internal streams
 * @param n_int_streams number of internal streams
 * @param idx the index for which to query the stream
 */
inline cudaStream_t select_stream(cudaStream_t user_stream,
                                  cudaStream_t* int_streams,
                                  int n_int_streams,
                                  int idx)
{
  return n_int_streams > 0 ? int_streams[idx % n_int_streams] : user_stream;
}

}  // namespace raft
