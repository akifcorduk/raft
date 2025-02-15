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
#include "add.cuh"
#include <gtest/gtest.h>
#include <raft/cudart_utils.h>
#include <raft/linalg/add.hpp>
#include <raft/random/rng.hpp>

namespace raft {
namespace linalg {

template <typename InT, typename OutT = InT>
class AddTest : public ::testing::TestWithParam<AddInputs<InT, OutT>> {
 public:
  AddTest()
    : params(::testing::TestWithParam<AddInputs<InT, OutT>>::GetParam()),
      stream(handle.get_stream()),
      in1(params.len, stream),
      in2(params.len, stream),
      out_ref(params.len, stream),
      out(params.len, stream)
  {
  }

 protected:
  void SetUp() override
  {
    params = ::testing::TestWithParam<AddInputs<InT, OutT>>::GetParam();
    raft::random::Rng r(params.seed);
    int len = params.len;
    r.uniform(in1.data(), len, InT(-1.0), InT(1.0), stream);
    r.uniform(in2.data(), len, InT(-1.0), InT(1.0), stream);
    naiveAddElem<InT, OutT>(out_ref.data(), in1.data(), in2.data(), len, stream);
    add<InT, OutT>(out.data(), in1.data(), in2.data(), len, stream);
    handle.sync_stream(stream);
  }

  void compare()
  {
    ASSERT_TRUE(raft::devArrMatch(
      out_ref.data(), out.data(), params.len, raft::CompareApprox<OutT>(params.tolerance), stream));
  }

 protected:
  raft::handle_t handle;
  cudaStream_t stream;

  AddInputs<InT, OutT> params;
  rmm::device_uvector<InT> in1;
  rmm::device_uvector<InT> in2;
  rmm::device_uvector<OutT> out_ref;
  rmm::device_uvector<OutT> out;
};

const std::vector<AddInputs<float>> inputsf = {
  {0.000001f, 1024 * 1024, 1234ULL},
  {0.000001f, 1024 * 1024 + 2, 1234ULL},
  {0.000001f, 1024 * 1024 + 1, 1234ULL},
};
typedef AddTest<float> AddTestF;
TEST_P(AddTestF, Result) { compare(); }
INSTANTIATE_TEST_SUITE_P(AddTests, AddTestF, ::testing::ValuesIn(inputsf));

const std::vector<AddInputs<double>> inputsd = {
  {0.00000001, 1024 * 1024, 1234ULL},
  {0.00000001, 1024 * 1024 + 2, 1234ULL},
  {0.00000001, 1024 * 1024 + 1, 1234ULL},
};
typedef AddTest<double> AddTestD;
TEST_P(AddTestD, Result) { compare(); }
INSTANTIATE_TEST_SUITE_P(AddTests, AddTestD, ::testing::ValuesIn(inputsd));

const std::vector<AddInputs<float, double>> inputsfd = {
  {0.00000001, 1024 * 1024, 1234ULL},
  {0.00000001, 1024 * 1024 + 2, 1234ULL},
  {0.00000001, 1024 * 1024 + 1, 1234ULL},
};
typedef AddTest<float, double> AddTestFD;
TEST_P(AddTestFD, Result) { compare(); }
INSTANTIATE_TEST_SUITE_P(AddTests, AddTestFD, ::testing::ValuesIn(inputsfd));

}  // end namespace linalg
}  // end namespace raft
