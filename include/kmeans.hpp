#pragma once
#include "rng.h"
#include <string>

int kmeansSerial(Rng &rng, const std::string &inputFile,
                 const std::string &outputFileName, int numClusters,
                 int repetitions, int numBlocks, int numThreads,
                 const std::string &centroidDebugFileName,
                 const std::string &clusterDebugFileName,
                 const std::string &mode = "serial");

int kmeansOMP(Rng &rng, const std::string &inputFile,
              const std::string &outputFileName, int numClusters,
              int repetitions, int numBlocks, int numThreads,
              const std::string &centroidDebugFileName,
              const std::string &clusterDebugFileName,
              const std::string &mode = "omp-naive");

int kmeansCUDA(Rng &rng, const std::string &inputFile,
               const std::string &outputFileName, int numClusters,
               int repetitions, int numBlocks, int numThreads,
               const std::string &centroidDebugFileName,
               const std::string &clusterDebugFileName);
