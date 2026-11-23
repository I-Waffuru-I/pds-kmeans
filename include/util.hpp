#pragma once
#include <cstddef>

struct DataSize {
  size_t cols;
  size_t rows;
  DataSize(size_t r, size_t c) : cols(c), rows(r) {}
};
