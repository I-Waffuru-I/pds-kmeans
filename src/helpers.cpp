#include "helpers.hpp"
#include "CSVReader.hpp"
#include "util.hpp"
#include <iostream>
FileCSVWriter openDebugFile(const std::string &n) {
  FileCSVWriter f;

  if (n.length() != 0) {
    f.open(n);
    if (!f.is_open())
      std::cerr << "WARNING: Unable to open debug file " << n << std::endl;
  }
  return f;
}

// Helper function to read input file into allData, setting number of detected
// rows and columns. Feel free to use, adapt or ignore
DataSize readData(std::ifstream &input, std::vector<double> &allData) {
  if (!input.is_open())
    throw std::runtime_error("Input file is not open");

  allData.resize(0);

  CSVReader inReader(input);
  int numColsExpected = -1;
  int line = 1;
  std::vector<double> row;

  while (inReader.read(row)) {
    if (numColsExpected == -1) {
      numColsExpected = row.size();
      if (numColsExpected <= 0)
        throw std::runtime_error("Unexpected error: 0 columns");
    } else if (numColsExpected != (int)row.size())
      throw std::runtime_error("Incompatible number of colums read in line " +
                               std::to_string(line) + ": expecting " +
                               std::to_string(numColsExpected) + " but got " +
                               std::to_string(row.size()));

    for (auto x : row)
      allData.push_back(x);

    line++;
  }

  return DataSize((size_t)allData.size() / numColsExpected,
                  (size_t)numColsExpected);
}
