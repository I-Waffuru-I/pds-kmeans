#pragma once
#include "CSVWriter.hpp"
#include "util.hpp"
#include <fstream>
#include <string>
#include <vector>

FileCSVWriter openDebugFile(const std::string &n);

// Helper function to read input file into allData, setting number of detected
// rows and columns. Feel free to use, adapt or ignore
DataSize readData(std::ifstream &input, std::vector<double> &allData);
