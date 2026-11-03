#pragma once
#include "rng.h"
#include "util.hpp"
#include <vector>

void initCentroids(Rng &rng, std::vector<double> &centroids,
                   std::vector<double> &allData, DataSize &dsize);

void debugCentroids(std::vector<double> &centroids, DataSize &size);

void debugCentroidPoints(std::vector<int> &pCentroid);
