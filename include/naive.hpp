#pragma once
#include "timer.h"
#include "util.hpp"
#include <cmath>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <limits>
#ifdef HAVE_OMP
#include <omp.h>
#endif
#include <unordered_map>
#include <vector>

void naiveClustering(std::vector<double> &centroids,
                     std::vector<double> &allData, std::vector<int> &cPoints,
                     double &avgDist, DataSize &size, bool &changed);

// Voor OMP
void naiveOMPClustering(std::vector<double> &centroids,
                        std::vector<double> &allData, std::vector<int> &cPoints, std::vector<double> &centroidMap,
                        double &avgDist, DataSize &size, bool &changed, int centroidNumber);

void naiveBaseOMPClustering(std::vector<double> &centroids,
                            std::vector<double> &allData, std::vector<int> &cPoints,
                            double &avgDist, DataSize &size, bool &changed, int numThreads);
