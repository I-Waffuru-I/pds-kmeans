#pragma once
#include "rng.h"
#include <string>

int kmeansSerial(Rng &rng, const std::string &inputFile,
           const std::string &outputFileName, int numClusters, int repetitions,
           int numBlocks, int numThreads,
           const std::string &centroidDebugFileName,
           const std::string &clusterDebugFileName);

int kmeansOMP(Rng &rng, const std::string &inputFile,
           const std::string &outputFileName, int numClusters, int repetitions,
           int numBlocks, int numThreads,
           const std::string &centroidDebugFileName,
           const std::string &clusterDebugFileName);


