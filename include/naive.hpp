#pragma once
#include "util.hpp"
#include <vector>

// Naïve serial clustering algorithm
void naiveClustering(std::vector<double> &centroids,
                     std::vector<double> &allData, std::vector<int> &cPoints,
                     double &avgDist, DataSize &size, bool &changed);

// Omp algorithm version of kmeans
void naiveOMPClustering(std::vector<double> &centroids,
                        std::vector<double> &allData, std::vector<int> &cPoints,
                        double &avgDist, DataSize &size, bool &changed, int numThreads);
