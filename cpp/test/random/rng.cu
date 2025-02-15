/*
 * Copyright (c) 2018-2022, NVIDIA CORPORATION.
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

#include "../test_utils.h"
#include <cub/cub.cuh>
#include <gtest/gtest.h>
#include <raft/cuda_utils.cuh>
#include <raft/cudart_utils.h>
#include <raft/random/rng.hpp>
#include <raft/stats/mean.hpp>
#include <raft/stats/stddev.hpp>

namespace raft {
namespace random {

using namespace raft::random;

enum RandomType {
  RNG_Normal,
  RNG_LogNormal,
  RNG_Uniform,
  RNG_Gumbel,
  RNG_Logistic,
  RNG_Exp,
  RNG_Rayleigh,
  RNG_Laplace
};

template <typename T, int TPB>
__global__ void meanKernel(T* out, const T* data, int len)
{
  typedef cub::BlockReduce<T, TPB> BlockReduce;
  __shared__ typename BlockReduce::TempStorage temp_storage;
  int tid = threadIdx.x + blockIdx.x * blockDim.x;
  T val   = tid < len ? data[tid] : T(0);
  T x     = BlockReduce(temp_storage).Sum(val);
  __syncthreads();
  T xx = BlockReduce(temp_storage).Sum(val * val);
  __syncthreads();
  if (threadIdx.x == 0) {
    raft::myAtomicAdd(out, x);
    raft::myAtomicAdd(out + 1, xx);
  }
}

template <typename T>
struct RngInputs {
  T tolerance;
  int len;
  // start, end: for uniform
  // mean, sigma: for normal/lognormal
  // mean, beta: for gumbel
  // mean, scale: for logistic and laplace
  // lambda: for exponential
  // sigma: for rayleigh
  T start, end;
  RandomType type;
  GeneratorType gtype;
  unsigned long long int seed;
};

template <typename T>
::std::ostream& operator<<(::std::ostream& os, const RngInputs<T>& dims)
{
  return os;
}

#include <sys/timeb.h>
#include <time.h>

template <typename T>
class RngTest : public ::testing::TestWithParam<RngInputs<T>> {
 public:
  RngTest()
    : params(::testing::TestWithParam<RngInputs<T>>::GetParam()),
      stream(handle.get_stream()),
      data(0, stream),
      stats(2, stream)
  {
    data.resize(params.len, stream);
    RAFT_CUDA_TRY(cudaMemsetAsync(stats.data(), 0, 2 * sizeof(T), stream));
  }

 protected:
  void SetUp() override
  {
    // Tests are configured with their expected test-values sigma. For example,
    // 4 x sigma indicates the test shouldn't fail 99.9% of the time.
    num_sigma = 4;
    Rng r(params.seed, params.gtype);
    switch (params.type) {
      case RNG_Normal: r.normal(data.data(), params.len, params.start, params.end, stream); break;
      case RNG_LogNormal:
        r.lognormal(data.data(), params.len, params.start, params.end, stream);
        break;
      case RNG_Uniform: r.uniform(data.data(), params.len, params.start, params.end, stream); break;
      case RNG_Gumbel: r.gumbel(data.data(), params.len, params.start, params.end, stream); break;
      case RNG_Logistic:
        r.logistic(data.data(), params.len, params.start, params.end, stream);
        break;
      case RNG_Exp: r.exponential(data.data(), params.len, params.start, stream); break;
      case RNG_Rayleigh: r.rayleigh(data.data(), params.len, params.start, stream); break;
      case RNG_Laplace: r.laplace(data.data(), params.len, params.start, params.end, stream); break;
    };
    static const int threads = 128;
    meanKernel<T, threads><<<raft::ceildiv(params.len, threads), threads, 0, stream>>>(
      stats.data(), data.data(), params.len);
    update_host<T>(h_stats, stats.data(), 2, stream);
    RAFT_CUDA_TRY(cudaStreamSynchronize(stream));
    h_stats[0] /= params.len;
    h_stats[1] = (h_stats[1] / params.len) - (h_stats[0] * h_stats[0]);
    RAFT_CUDA_TRY(cudaStreamSynchronize(stream));
  }

  void getExpectedMeanVar(T meanvar[2])
  {
    switch (params.type) {
      case RNG_Normal:
        meanvar[0] = params.start;
        meanvar[1] = params.end * params.end;
        break;
      case RNG_LogNormal: {
        auto var   = params.end * params.end;
        auto mu    = params.start;
        meanvar[0] = raft::myExp(mu + var * T(0.5));
        meanvar[1] = (raft::myExp(var) - T(1.0)) * raft::myExp(T(2.0) * mu + var);
        break;
      }
      case RNG_Uniform:
        meanvar[0] = (params.start + params.end) * T(0.5);
        meanvar[1] = params.end - params.start;
        meanvar[1] = meanvar[1] * meanvar[1] / T(12.0);
        break;
      case RNG_Gumbel: {
        auto gamma = T(0.577215664901532);
        meanvar[0] = params.start + params.end * gamma;
        meanvar[1] = T(3.1415) * T(3.1415) * params.end * params.end / T(6.0);
        break;
      }
      case RNG_Logistic:
        meanvar[0] = params.start;
        meanvar[1] = T(3.1415) * T(3.1415) * params.end * params.end / T(3.0);
        break;
      case RNG_Exp:
        meanvar[0] = T(1.0) / params.start;
        meanvar[1] = meanvar[0] * meanvar[0];
        break;
      case RNG_Rayleigh:
        meanvar[0] = params.start * raft::mySqrt(T(3.1415 / 2.0));
        meanvar[1] = ((T(4.0) - T(3.1415)) / T(2.0)) * params.start * params.start;
        break;
      case RNG_Laplace:
        meanvar[0] = params.start;
        meanvar[1] = T(2.0) * params.end * params.end;
        break;
    };
  }

 protected:
  raft::handle_t handle;
  cudaStream_t stream;

  RngInputs<T> params;
  rmm::device_uvector<T> data, stats;
  T h_stats[2];  // mean, var
  int num_sigma;
};

// The measured mean and standard deviation for each tested distribution are,
// of course, statistical variables. Thus setting an appropriate testing
// tolerance essentially requires one to set a probability of test failure. We
// choose to set this at 3-4 x sigma, i.e., a 99.7-99.9% confidence interval so that
// the test will indeed pass. In quick experiments (using the identical
// distributions given by NumPy/SciPy), the measured standard deviation is the
// variable with the greatest variance and so we determined the variance for
// each distribution and number of samples (32*1024 or 8*1024). Below
// are listed the standard deviation for these tests.

// Distribution: StdDev 32*1024, StdDev 8*1024
// Normal: 0.0055, 0.011
// LogNormal: 0.05, 0.1
// Uniform: 0.003, 0.005
// Gumbel: 0.005, 0.01
// Logistic: 0.005, 0.01
// Exp: 0.008, 0.015
// Rayleigh: 0.0125, 0.025
// Laplace: 0.02, 0.04

// We generally want 4 x sigma >= 99.9% chance of success

typedef RngTest<float> RngTestF;
const std::vector<RngInputs<float>> inputsf = {
  {0.0055, 32 * 1024, 1.f, 1.f, RNG_Normal, GenPhilox, 1234ULL},
  {0.011, 8 * 1024, 1.f, 1.f, RNG_Normal, GenPhilox, 1234ULL},
  {0.05, 32 * 1024, 1.f, 1.f, RNG_LogNormal, GenPhilox, 1234ULL},
  {0.1, 8 * 1024, 1.f, 1.f, RNG_LogNormal, GenPhilox, 1234ULL},
  {0.003, 32 * 1024, -1.f, 1.f, RNG_Uniform, GenPhilox, 1234ULL},
  {0.005, 8 * 1024, -1.f, 1.f, RNG_Uniform, GenPhilox, 1234ULL},
  {0.005, 32 * 1024, 1.f, 1.f, RNG_Gumbel, GenPhilox, 1234ULL},
  {0.01, 8 * 1024, 1.f, 1.f, RNG_Gumbel, GenPhilox, 1234ULL},
  {0.005, 32 * 1024, 1.f, 1.f, RNG_Logistic, GenPhilox, 67632ULL},
  {0.01, 8 * 1024, 1.f, 1.f, RNG_Logistic, GenPhilox, 1234ULL},
  {0.008, 32 * 1024, 1.f, 1.f, RNG_Exp, GenPhilox, 1234ULL},
  {0.015, 8 * 1024, 1.f, 1.f, RNG_Exp, GenPhilox, 1234ULL},
  {0.0125, 32 * 1024, 1.f, 1.f, RNG_Rayleigh, GenPhilox, 1234ULL},
  {0.025, 8 * 1024, 1.f, 1.f, RNG_Rayleigh, GenPhilox, 1234ULL},
  {0.02, 32 * 1024, 1.f, 1.f, RNG_Laplace, GenPhilox, 1234ULL},
  {0.04, 8 * 1024, 1.f, 1.f, RNG_Laplace, GenPhilox, 1234ULL},

  {0.0055, 32 * 1024, 1.f, 1.f, RNG_Normal, GenPC, 1234ULL},
  {0.011, 8 * 1024, 1.f, 1.f, RNG_Normal, GenPC, 1234ULL},
  {0.05, 32 * 1024, 1.f, 1.f, RNG_LogNormal, GenPC, 1234ULL},
  {0.1, 8 * 1024, 1.f, 1.f, RNG_LogNormal, GenPC, 1234ULL},
  {0.003, 32 * 1024, -1.f, 1.f, RNG_Uniform, GenPC, 1234ULL},
  {0.005, 8 * 1024, -1.f, 1.f, RNG_Uniform, GenPC, 1234ULL},
  {0.005, 32 * 1024, 1.f, 1.f, RNG_Gumbel, GenPC, 1234ULL},
  {0.01, 8 * 1024, 1.f, 1.f, RNG_Gumbel, GenPC, 1234ULL},
  {0.005, 32 * 1024, 1.f, 1.f, RNG_Logistic, GenPC, 1234ULL},
  {0.01, 8 * 1024, 1.f, 1.f, RNG_Logistic, GenPC, 1234ULL},
  {0.008, 32 * 1024, 1.f, 1.f, RNG_Exp, GenPC, 1234ULL},
  {0.015, 8 * 1024, 1.f, 1.f, RNG_Exp, GenPC, 1234ULL},
  {0.0125, 32 * 1024, 1.f, 1.f, RNG_Rayleigh, GenPC, 1234ULL},
  {0.025, 8 * 1024, 1.f, 1.f, RNG_Rayleigh, GenPC, 1234ULL},
  {0.02, 32 * 1024, 1.f, 1.f, RNG_Laplace, GenPC, 1234ULL},
  {0.04, 8 * 1024, 1.f, 1.f, RNG_Laplace, GenPC, 1234ULL}};

TEST_P(RngTestF, Result)
{
  float meanvar[2];
  getExpectedMeanVar(meanvar);
  ASSERT_TRUE(match(meanvar[0], h_stats[0], CompareApprox<float>(num_sigma * params.tolerance)));
  ASSERT_TRUE(match(meanvar[1], h_stats[1], CompareApprox<float>(num_sigma * params.tolerance)));
}
INSTANTIATE_TEST_SUITE_P(RngTests, RngTestF, ::testing::ValuesIn(inputsf));

typedef RngTest<double> RngTestD;
const std::vector<RngInputs<double>> inputsd = {
  {0.0055, 32 * 1024, 1.0, 1.0, RNG_Normal, GenPhilox, 1234ULL},
  {0.011, 8 * 1024, 1.0, 1.0, RNG_Normal, GenPhilox, 1234ULL},
  {0.05, 32 * 1024, 1.0, 1.0, RNG_LogNormal, GenPhilox, 1234ULL},
  {0.1, 8 * 1024, 1.0, 1.0, RNG_LogNormal, GenPhilox, 1234ULL},
  {0.003, 32 * 1024, -1.0, 1.0, RNG_Uniform, GenPhilox, 1234ULL},
  {0.005, 8 * 1024, -1.0, 1.0, RNG_Uniform, GenPhilox, 1234ULL},
  {0.005, 32 * 1024, 1.0, 1.0, RNG_Gumbel, GenPhilox, 1234ULL},
  {0.01, 8 * 1024, 1.0, 1.0, RNG_Gumbel, GenPhilox, 1234ULL},
  {0.005, 32 * 1024, 1.0, 1.0, RNG_Logistic, GenPhilox, 67632ULL},
  {0.01, 8 * 1024, 1.0, 1.0, RNG_Logistic, GenPhilox, 1234ULL},
  {0.008, 32 * 1024, 1.0, 1.0, RNG_Exp, GenPhilox, 1234ULL},
  {0.015, 8 * 1024, 1.0, 1.0, RNG_Exp, GenPhilox, 1234ULL},
  {0.0125, 32 * 1024, 1.0, 1.0, RNG_Rayleigh, GenPhilox, 1234ULL},
  {0.025, 8 * 1024, 1.0, 1.0, RNG_Rayleigh, GenPhilox, 1234ULL},
  {0.02, 32 * 1024, 1.0, 1.0, RNG_Laplace, GenPhilox, 1234ULL},
  {0.04, 8 * 1024, 1.0, 1.0, RNG_Laplace, GenPhilox, 1234ULL},

  {0.0055, 32 * 1024, 1.0, 1.0, RNG_Normal, GenPC, 1234ULL},
  {0.011, 8 * 1024, 1.0, 1.0, RNG_Normal, GenPC, 1234ULL},
  {0.05, 32 * 1024, 1.0, 1.0, RNG_LogNormal, GenPC, 1234ULL},
  {0.1, 8 * 1024, 1.0, 1.0, RNG_LogNormal, GenPC, 1234ULL},
  {0.003, 32 * 1024, -1.0, 1.0, RNG_Uniform, GenPC, 1234ULL},
  {0.005, 8 * 1024, -1.0, 1.0, RNG_Uniform, GenPC, 1234ULL},
  {0.005, 32 * 1024, 1.0, 1.0, RNG_Gumbel, GenPC, 1234ULL},
  {0.01, 8 * 1024, 1.0, 1.0, RNG_Gumbel, GenPC, 1234ULL},
  {0.005, 32 * 1024, 1.0, 1.0, RNG_Logistic, GenPC, 1234ULL},
  {0.01, 8 * 1024, 1.0, 1.0, RNG_Logistic, GenPC, 1234ULL},
  {0.008, 32 * 1024, 1.0, 1.0, RNG_Exp, GenPC, 1234ULL},
  {0.015, 8 * 1024, 1.0, 1.0, RNG_Exp, GenPC, 1234ULL},
  {0.0125, 32 * 1024, 1.0, 1.0, RNG_Rayleigh, GenPC, 1234ULL},
  {0.025, 8 * 1024, 1.0, 1.0, RNG_Rayleigh, GenPC, 1234ULL},
  {0.02, 32 * 1024, 1.0, 1.0, RNG_Laplace, GenPC, 1234ULL},
  {0.04, 8 * 1024, 1.0, 1.0, RNG_Laplace, GenPC, 1234ULL}};

TEST_P(RngTestD, Result)
{
  double meanvar[2];
  getExpectedMeanVar(meanvar);
  ASSERT_TRUE(match(meanvar[0], h_stats[0], CompareApprox<double>(num_sigma * params.tolerance)));
  ASSERT_TRUE(match(meanvar[1], h_stats[1], CompareApprox<double>(num_sigma * params.tolerance)));
}
INSTANTIATE_TEST_SUITE_P(RngTests, RngTestD, ::testing::ValuesIn(inputsd));

// ---------------------------------------------------------------------- //
// Test for expected variance in mean calculations

template <typename T>
T quick_mean(const std::vector<T>& d)
{
  T acc = T(0);
  for (const auto& di : d) {
    acc += di;
  }
  return acc / d.size();
}

template <typename T>
T quick_std(const std::vector<T>& d)
{
  T acc    = T(0);
  T d_mean = quick_mean(d);
  for (const auto& di : d) {
    acc += ((di - d_mean) * (di - d_mean));
  }
  return std::sqrt(acc / (d.size() - 1));
}

template <typename T>
std::ostream& operator<<(std::ostream& out, const std::vector<T>& v)
{
  if (!v.empty()) {
    out << '[';
    std::copy(v.begin(), v.end(), std::ostream_iterator<T>(out, ", "));
    out << "\b\b]";
  }
  return out;
}

// The following tests the 3 random number generators by checking that the
// measured mean error is close to the well-known analytical result
// (sigma/sqrt(n_samples)). To compute the mean error, we a number of
// experiments computing the mean, giving us a distribution of the mean
// itself. The mean error is simply the standard deviation of this
// distribution (the standard deviation of the mean).
TEST(Rng, MeanError)
{
  timeb time_struct;
  ftime(&time_struct);
  int seed            = time_struct.millitm;
  int num_samples     = 1024;
  int num_experiments = 1024;
  int len             = num_samples * num_experiments;

  cudaStream_t stream;
  RAFT_CUDA_TRY(cudaStreamCreate(&stream));

  rmm::device_uvector<float> data(len, stream);
  rmm::device_uvector<float> mean_result(num_experiments, stream);
  rmm::device_uvector<float> std_result(num_experiments, stream);

  for (auto rtype : {GenPhilox, GenPC}) {
    Rng r(seed, rtype);
    r.normal(data.data(), len, 3.3f, 0.23f, stream);
    // r.uniform(data, len, -1.0, 2.0);
    raft::stats::mean(
      mean_result.data(), data.data(), num_samples, num_experiments, false, false, stream);
    raft::stats::stddev(std_result.data(),
                        data.data(),
                        mean_result.data(),
                        num_samples,
                        num_experiments,
                        false,
                        false,
                        stream);
    std::vector<float> h_mean_result(num_experiments);
    std::vector<float> h_std_result(num_experiments);
    update_host(h_mean_result.data(), mean_result.data(), num_experiments, stream);
    update_host(h_std_result.data(), std_result.data(), num_experiments, stream);
    RAFT_CUDA_TRY(cudaStreamSynchronize(stream));
    auto d_mean = quick_mean(h_mean_result);

    // std-dev of mean; also known as mean error
    auto d_std_of_mean            = quick_std(h_mean_result);
    auto d_std                    = quick_mean(h_std_result);
    auto d_std_of_mean_analytical = d_std / std::sqrt(num_samples);

    // std::cout << "measured mean error: " << d_std_of_mean << "\n";
    // std::cout << "expected mean error: " << d_std/std::sqrt(num_samples) << "\n";

    auto diff_expected_vs_measured_mean_error =
      std::abs(d_std_of_mean - d_std / std::sqrt(num_samples));

    ASSERT_TRUE((diff_expected_vs_measured_mean_error / d_std_of_mean_analytical < 0.5));
  }
  RAFT_CUDA_TRY(cudaStreamDestroy(stream));

  // std::cout << "mean_res:" << h_mean_result << "\n";
}

template <typename T, int len, int scale>
class ScaledBernoulliTest : public ::testing::Test {
 public:
  ScaledBernoulliTest() : stream(handle.get_stream()), data(len, stream) {}

 protected:
  void SetUp() override
  {
    RAFT_CUDA_TRY(cudaStreamCreate(&stream));
    Rng r(42);
    r.scaled_bernoulli(data.data(), len, T(0.5), T(scale), stream);
  }

  void rangeCheck()
  {
    T* h_data = new T[len];
    update_host(h_data, data.data(), len, stream);
    ASSERT_TRUE(
      std::none_of(h_data, h_data + len, [](const T& a) { return a < -scale || a > scale; }));
    delete[] h_data;
  }

  raft::handle_t handle;
  cudaStream_t stream;

  rmm::device_uvector<T> data;
};

typedef ScaledBernoulliTest<float, 500, 35> ScaledBernoulliTest1;
TEST_F(ScaledBernoulliTest1, RangeCheck) { rangeCheck(); }

typedef ScaledBernoulliTest<double, 100, 220> ScaledBernoulliTest2;
TEST_F(ScaledBernoulliTest2, RangeCheck) { rangeCheck(); }

template <typename T, int len>
class BernoulliTest : public ::testing::Test {
 public:
  BernoulliTest() : stream(handle.get_stream()), data(len, stream) {}

 protected:
  void SetUp() override
  {
    Rng r(42);
    r.bernoulli(data.data(), len, T(0.5), stream);
    RAFT_CUDA_TRY(cudaStreamSynchronize(stream));
  }

  void trueFalseCheck()
  {
    // both true and false values must be present
    bool* h_data = new bool[len];
    update_host(h_data, data.data(), len, stream);
    ASSERT_TRUE(std::any_of(h_data, h_data + len, [](bool a) { return a; }));
    ASSERT_TRUE(std::any_of(h_data, h_data + len, [](bool a) { return !a; }));
    delete[] h_data;
  }

  raft::handle_t handle;
  cudaStream_t stream;

  rmm::device_uvector<bool> data;
};

typedef BernoulliTest<float, 1000> BernoulliTest1;
TEST_F(BernoulliTest1, TrueFalseCheck) { trueFalseCheck(); }

typedef BernoulliTest<double, 1000> BernoulliTest2;
TEST_F(BernoulliTest2, TrueFalseCheck) { trueFalseCheck(); }

/** Rng::normalTable tests */
template <typename T>
struct RngNormalTableInputs {
  T tolerance;
  int rows, cols;
  T mu, sigma;
  GeneratorType gtype;
  unsigned long long int seed;
};

template <typename T>
::std::ostream& operator<<(::std::ostream& os, const RngNormalTableInputs<T>& dims)
{
  return os;
}

template <typename T>
class RngNormalTableTest : public ::testing::TestWithParam<RngNormalTableInputs<T>> {
 public:
  RngNormalTableTest()
    : params(::testing::TestWithParam<RngNormalTableInputs<T>>::GetParam()),
      stream(handle.get_stream()),
      data(params.rows * params.cols, stream),
      stats(2, stream),
      mu_vec(params.cols, stream)
  {
    RAFT_CUDA_TRY(cudaMemsetAsync(stats.data(), 0, 2 * sizeof(T), stream));
  }

 protected:
  void SetUp() override
  {
    // Tests are configured with their expected test-values sigma. For example,
    // 4 x sigma indicates the test shouldn't fail 99.9% of the time.
    num_sigma = 10;
    int len   = params.rows * params.cols;
    Rng r(params.seed, params.gtype);
    r.fill(mu_vec.data(), params.cols, params.mu, stream);
    T* sigma_vec = nullptr;
    r.normalTable(
      data.data(), params.rows, params.cols, mu_vec.data(), sigma_vec, params.sigma, stream);
    static const int threads = 128;
    meanKernel<T, threads>
      <<<raft::ceildiv(len, threads), threads, 0, stream>>>(stats.data(), data.data(), len);
    update_host<T>(h_stats, stats.data(), 2, stream);
    RAFT_CUDA_TRY(cudaStreamSynchronize(stream));
    h_stats[0] /= len;
    h_stats[1] = (h_stats[1] / len) - (h_stats[0] * h_stats[0]);
    RAFT_CUDA_TRY(cudaStreamSynchronize(stream));
  }

  void getExpectedMeanVar(T meanvar[2])
  {
    meanvar[0] = params.mu;
    meanvar[1] = params.sigma * params.sigma;
  }

 protected:
  raft::handle_t handle;
  cudaStream_t stream;

  RngNormalTableInputs<T> params;
  rmm::device_uvector<T> data, stats, mu_vec;
  T h_stats[2];  // mean, var
  int num_sigma;
};

typedef RngNormalTableTest<float> RngNormalTableTestF;
const std::vector<RngNormalTableInputs<float>> inputsf_t = {
  {0.0055, 32, 1024, 1.f, 1.f, GenPhilox, 1234ULL},
  {0.011, 8, 1024, 1.f, 1.f, GenPhilox, 1234ULL},

  {0.0055, 32, 1024, 1.f, 1.f, GenPC, 1234ULL},
  {0.011, 8, 1024, 1.f, 1.f, GenPC, 1234ULL}};

TEST_P(RngNormalTableTestF, Result)
{
  float meanvar[2];
  getExpectedMeanVar(meanvar);
  ASSERT_TRUE(match(meanvar[0], h_stats[0], CompareApprox<float>(num_sigma * params.tolerance)));
  ASSERT_TRUE(match(meanvar[1], h_stats[1], CompareApprox<float>(num_sigma * params.tolerance)));
}
INSTANTIATE_TEST_SUITE_P(RngNormalTableTests, RngNormalTableTestF, ::testing::ValuesIn(inputsf_t));

typedef RngNormalTableTest<double> RngNormalTableTestD;
const std::vector<RngNormalTableInputs<double>> inputsd_t = {
  {0.0055, 32, 1024, 1.0, 1.0, GenPhilox, 1234ULL},
  {0.011, 8, 1024, 1.0, 1.0, GenPhilox, 1234ULL},

  {0.0055, 32, 1024, 1.0, 1.0, GenPC, 1234ULL},
  {0.011, 8, 1024, 1.0, 1.0, GenPC, 1234ULL}};
TEST_P(RngNormalTableTestD, Result)
{
  double meanvar[2];
  getExpectedMeanVar(meanvar);
  ASSERT_TRUE(match(meanvar[0], h_stats[0], CompareApprox<double>(num_sigma * params.tolerance)));
  ASSERT_TRUE(match(meanvar[1], h_stats[1], CompareApprox<double>(num_sigma * params.tolerance)));
}
INSTANTIATE_TEST_SUITE_P(RngNormalTableTests, RngNormalTableTestD, ::testing::ValuesIn(inputsd_t));

struct RngAffineInputs {
  int n;
  unsigned long long seed;
};

class RngAffineTest : public ::testing::TestWithParam<RngAffineInputs> {
 protected:
  void SetUp() override
  {
    params = ::testing::TestWithParam<RngAffineInputs>::GetParam();
    Rng r(params.seed);
    r.affine_transform_params(params.n, a, b);
  }

  void check()
  {
    ASSERT_TRUE(gcd(a, params.n) == 1);
    ASSERT_TRUE(0 <= b && b < params.n);
  }

 private:
  RngAffineInputs params;
  int a, b;
};  // RngAffineTest

const std::vector<RngAffineInputs> inputs_affine = {
  {100, 123456ULL},
  {100, 1234567890ULL},
  {101, 123456ULL},
  {101, 1234567890ULL},
  {7, 123456ULL},
  {7, 1234567890ULL},
  {2568, 123456ULL},
  {2568, 1234567890ULL},
};
TEST_P(RngAffineTest, Result) { check(); }
INSTANTIATE_TEST_SUITE_P(RngAffineTests, RngAffineTest, ::testing::ValuesIn(inputs_affine));

}  // namespace random
}  // namespace raft
