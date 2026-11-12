#include "CSVWriter.hpp"
#include "centroids.hpp"
#include "helpers.hpp"
#include "rng.h"
#include <filesystem>
#include <iostream>

namespace fs = std::filesystem;

__global__ void kmeansKernel(double *centroids, double* pointInCentroid) {

}

int kmeansCUDA(Rng &rng, const std::string &inputFile,
               const std::string &outputFileName, int numClusters,
               int repetitions, int numBlocks, int numThreads,
               const std::string &centroidDebugFileName,
               const std::string &clusterDebugFileName) {

  // If debug filenames are specified, this opens them. The is_open method
  // can be used to check if they are actually open and should be written to.
  FileCSVWriter centroidDebugFile = openDebugFile(centroidDebugFileName);
  FileCSVWriter clustersDebugFile = openDebugFile(clusterDebugFileName);

  fs::path dirPath;
  try {
    dirPath = fs::path(outputFileName).parent_path();
    if (fs::create_directories(dirPath)) {
      std::cout << "Created new directory" << std::endl;
    } else {
      std::cout << "Directory already exists" << std::endl;
    }
  } catch (std::exception e) {
    std::cout << e.what() << std::endl;
  }

  FileCSVWriter csvOutputFile(outputFileName);
  if (!csvOutputFile.is_open()) {
    std::cerr << "Unable to open output file " << outputFileName << std::endl;
    return -1;
  }

  std::ifstream datasetFile;
  datasetFile.open(inputFile);
  if (!datasetFile.is_open()) {
    std::cerr << "Unable to open input file " << inputFile << std::endl;
    return -1;
  }

  std::vector<double> allData;
  DataSize datafmt = readData(datasetFile, allData);

  double bestDistSquaredSum =
      std::numeric_limits<double>::max(); // can only get better
  std::vector<int> bestCluster(datafmt.rows);
  // to save the number of steps each rep needed
  std::vector<size_t> stepsPerRepetition(repetitions);

  std::vector<double> centroids(numClusters * datafmt.cols);

  // list of what point belongs to what centroid
  bool outputToA = false;
  std::vector<int> pointsCentroid(datafmt.rows);
  pointsCentroid.assign(allData.size() / datafmt.cols, -1);

  // dient als timer
  cudaEvent_t startAllEvt, stopAllEvt;
  cudaEventCreate(&startAllEvt);
  cudaEventCreate(&stopAllEvt);

  cudaEventRecord(startAllEvt);

  // malloc space for output centroid IDs
  cudaError_t err;
  double *pPointToCentroid;
  cudaError_t mallerr = cudaMalloc(&pPointToCentroid, datafmt.rows * sizeof(double));
  if (mallerr != cudaSuccess) {
    std::cout << "CUDA malloc error " << mallerr << std::endl;
    exit(1);
  }

  const size_t BLOCKSIZE = 4;
  size_t numXBlocks = (datafmt.rows / BLOCKSIZE) + (((datafmt.rows % BLOCKSIZE) != 0) ? 1 : 0);
  size_t numYBlocks = (datafmt.cols / BLOCKSIZE) + (((datafmt.cols % BLOCKSIZE) != 0) ? 1 : 0);
  dim3 blocks ;

  for (int r = 0; r < repetitions; r++) {
    initCentroids(rng, centroids, allData, datafmt);
    centroidDebugFile.write(centroids, datafmt.cols);

    bool changed = true;
    double avgDist = 0;
    size_t numSteps = 0;
    while (changed) {
      avgDist = 0;

      std::cout << "After" << std::endl;
      debugCentroids(centroids, datafmt);

      // run kernel
      kmeansKernel<<<datafmt.rows, 1>>>(centroids, pPointToCentroid);

      std::cout << "Old" << std::endl;
      debugCentroids(centroids, datafmt);

      centroidDebugFile.write(centroids, datafmt.cols);
      clustersDebugFile.write(pointsCentroid, datafmt.rows);

      numSteps++;
      outputToA = !outputToA;
      
    } // end while changed

    if (avgDist < bestDistSquaredSum) {
      bestDistSquaredSum = avgDist;
      bestCluster = pointsCentroid;
    }

    stepsPerRepetition[r] = numSteps;

    // Make sure debug logging is only done on first iteration ; subsequent
    // checks with is_open will indicate that no logging needs to be done
    // anymore.
    centroidDebugFile.close();
    clustersDebugFile.close();

  } // end reps
  cudaEventRecord(stopAllEvt);
  cudaEventSynchronize(stopAllEvt);

  float elapsed;
  cudaEventElapsedTime(&elapsed, startAllEvt, stopAllEvt);
  std::cerr << "# "
               "Type,blocks,threads,file,seed,clusters,repetitions,"
               "bestdistsquared,timeinseconds"
            << std::endl;
  std::cout << "cuda_sequential," << "," << numBlocks << "," << numThreads
            << "," << inputFile << "," << rng.getUsedSeed() << ","
            << numClusters << "," << repetitions << "," << bestDistSquaredSum
            << "," << elapsed / 1000 << std::endl;

  // Write the number of steps per repetition, kind of a signature of the work
  // involved
  csvOutputFile.write(stepsPerRepetition, "# Steps: ");
  // Write best clusters to csvOutputFile, something like
  csvOutputFile.write(bestCluster);

  cudaFree(pPointToCentroid);
  cudaEventDestroy(startAllEvt);
  cudaEventDestroy(stopAllEvt);

  return 0;
}
