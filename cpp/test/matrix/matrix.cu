/*
 * Copyright (c) 2018-2020, NVIDIA CORPORATION.
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
#include <gtest/gtest.h>
#include <raft/cudart_utils.h>
#include <raft/matrix/matrix.hpp>
#include <raft/random/rng.hpp>
#include <rmm/device_uvector.hpp>

namespace raft {
namespace matrix {

template <typename T>
struct MatrixInputs {
  T tolerance;
  int n_row;
  int n_col;
  unsigned long long int seed;
};

template <typename T>
::std::ostream& operator<<(::std::ostream& os, const MatrixInputs<T>& dims)
{
  return os;
}

template <typename T>
class MatrixTest : public ::testing::TestWithParam<MatrixInputs<T>> {
 public:
  MatrixTest()
    : params(::testing::TestWithParam<MatrixInputs<T>>::GetParam()),
      stream(handle.get_stream()),
      in1(params.n_row * params.n_col, stream),
      in2(params.n_row * params.n_col, stream),
      in1_revr(params.n_row * params.n_col, stream)
  {
  }

 protected:
  void SetUp() override
  {
    raft::random::Rng r(params.seed);
    int len = params.n_row * params.n_col;
    r.uniform(in1.data(), len, T(-1.0), T(1.0), stream);

    copy(in1.data(), in2.data(), params.n_row, params.n_col, stream);
    // copy(in1, in1_revr, params.n_row, params.n_col);
    // colReverse(in1_revr, params.n_row, params.n_col);

    rmm::device_uvector<T> outTrunc(6, stream);
    truncZeroOrigin(in1.data(), params.n_row, outTrunc.data(), 3, 2, stream);
    handle.sync_stream(stream);
  }

 protected:
  raft::handle_t handle;
  cudaStream_t stream;

  MatrixInputs<T> params;
  rmm::device_uvector<T> in1, in2, in1_revr;
};

const std::vector<MatrixInputs<float>> inputsf2 = {{0.000001f, 4, 4, 1234ULL}};

const std::vector<MatrixInputs<double>> inputsd2 = {{0.00000001, 4, 4, 1234ULL}};

typedef MatrixTest<float> MatrixTestF;
TEST_P(MatrixTestF, Result)
{
  ASSERT_TRUE(raft::devArrMatch(in1.data(),
                                in2.data(),
                                params.n_row * params.n_col,
                                raft::CompareApprox<float>(params.tolerance),
                                stream));
}

typedef MatrixTest<double> MatrixTestD;
TEST_P(MatrixTestD, Result)
{
  ASSERT_TRUE(raft::devArrMatch(in1.data(),
                                in2.data(),
                                params.n_row * params.n_col,
                                raft::CompareApprox<double>(params.tolerance),
                                stream));
}

INSTANTIATE_TEST_SUITE_P(MatrixTests, MatrixTestF, ::testing::ValuesIn(inputsf2));

INSTANTIATE_TEST_SUITE_P(MatrixTests, MatrixTestD, ::testing::ValuesIn(inputsd2));

template <typename T>
class MatrixCopyRowsTest : public ::testing::Test {
  using math_t      = typename std::tuple_element<0, T>::type;
  using idx_t       = typename std::tuple_element<1, T>::type;
  using idx_array_t = typename std::tuple_element<2, T>::type;

 protected:
  MatrixCopyRowsTest()
    : stream(handle.get_stream()),
      input(n_cols * n_rows, handle.get_stream()),
      indices(n_selected, handle.get_stream()),
      output(n_cols * n_selected, handle.get_stream())
  {
    raft::update_device(indices.data(), indices_host, n_selected, stream);
    // Init input array
    thrust::counting_iterator<idx_t> first(0);
    thrust::device_ptr<math_t> ptr(input.data());
    thrust::copy(handle.get_thrust_policy(), first, first + n_cols * n_rows, ptr);
  }

  void testCopyRows()
  {
    copyRows(input.data(),
             n_rows,
             n_cols,
             output.data(),
             indices.data(),
             n_selected,
             handle.get_stream(),
             false);
    EXPECT_TRUE(raft::devArrMatchHost(
      output_exp_colmajor, output.data(), n_selected * n_cols, raft::Compare<math_t>(), stream));
    copyRows(input.data(),
             n_rows,
             n_cols,
             output.data(),
             indices.data(),
             n_selected,
             handle.get_stream(),
             true);
    EXPECT_TRUE(raft::devArrMatchHost(
      output_exp_rowmajor, output.data(), n_selected * n_cols, raft::Compare<math_t>(), stream));
  }

 protected:
  raft::handle_t handle;
  cudaStream_t stream;

  int n_rows     = 10;
  int n_cols     = 3;
  int n_selected = 5;

  idx_array_t indices_host[5]    = {0, 3, 4, 7, 9};
  math_t output_exp_colmajor[15] = {0, 3, 4, 7, 9, 10, 13, 14, 17, 19, 20, 23, 24, 27, 29};
  math_t output_exp_rowmajor[15] = {0, 1, 2, 9, 10, 11, 12, 13, 14, 21, 22, 23, 27, 28, 29};
  rmm::device_uvector<math_t> input;
  rmm::device_uvector<math_t> output;
  rmm::device_uvector<idx_array_t> indices;
};

using TypeTuple = ::testing::Types<std::tuple<float, int, int>,
                                   std::tuple<float, int64_t, int>,
                                   std::tuple<double, int, int>,
                                   std::tuple<double, int64_t, int>>;

TYPED_TEST_CASE(MatrixCopyRowsTest, TypeTuple);
TYPED_TEST(MatrixCopyRowsTest, CopyRows) { this->testCopyRows(); }
}  // namespace matrix
}  // namespace raft
