#include "CSVWriter.hpp"
#include "centroids.hpp"
#include "helpers.hpp"
#include "rng.h"
#include <cfloat>
#include <filesystem>
#include <iostream>
#include <vector>

namespace fs = std::filesystem;

// void naiveClustering(std::vector<double> &centroids,
//                      std::vector<double> &allData, std::vector<int> &cPoints,
//                      double &avgDist, DataSize &size, bool &changed)
__global__ void assignPtsToCentroids(const double *data, double *centroids,
                                     double *pointInCentroid, size_t rows,
                                     size_t cols, size_t k, bool *changed) {
  size_t idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (idx >= rows)
    return;

  // make kernel dim (512 or sum, numcols zo elke col thread een item doet ipv
  // for loop )

  // being pixel p
  // find closest cluster
  // check if this can be sped up through coalescent MA
  size_t bestK = 0;
  double minDist = DBL_MAX;
  for (size_t j = 0; j < k; j++) {
    double d = 0;
    // TODO idx & idy gebruiken ipv forloop
    for (size_t c = 0; c < cols; c++) {
      double diff = data[idx * cols + c] - centroids[j * cols + c];
      d += diff * diff;
    }
    if (d < minDist) {
      minDist = d;
      bestK = j;
    }
  };

  if (pointInCentroid[idx] != bestK) {
    pointInCentroid[idx] = bestK;
    // data race boeit nie want t'is toch ma T/F
    *changed = true;
  }
}

// tmp werken met serial stuk om te checken of de eerste kernel werkt
void updateCentroids(const double *data, double *centroids,
                     const double *pointInCentroid, size_t rows, size_t cols,
                     size_t k) {
  std::vector<double> cpoints(k * cols, 0.0);
  std::vector<size_t> cpointCount(k, 0);
  for (size_t p = 0; p < rows; p++) {
    double cId = pointInCentroid[p];
    cpointCount[cId]++;
    // sum up
    for (size_t c = 0; c < cols; c++) { // omg c++ namedropped
      cpoints[cId * cols + c] += data[p * cols + c];
    }
  }

  // calc averages and update
  for (size_t j = 0; j < k; j++) {
    if (cpointCount[j] == 0)
      continue; // keep centroid as is

    // t
    for (size_t c = 0; c < cols; c++) { // omggg again!
      centroids[j * cols + c] = cpoints[j * cols + c] / cpointCount[j];
    }
  }
}

int kmeansCUDA(Rng &rng, const std::string &inputFile,
               const std::string &outputFileName, int numClusters,
               int repetitions, int numBlocks, int numThreads,
               const std::string &centroidDebugFileName,
               const std::string &clusterDebugFileName) {

  {
    int dev;
    cudaGetDeviceCount(&dev);
    if (dev < 1) {
      std::cout << "No CUDA device found!" << std::endl;
      exit(1);
    }
  }
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
  std::vector<double> bestCluster(datafmt.rows);
  // to save the number of steps each rep needed
  std::vector<size_t> stepsPerRepetition(repetitions);
  std::vector<double> centroids(numClusters * datafmt.cols);
  // duuw alle point dists hier in en tel ze op
  std::vector<double> dists(datafmt.cols);
  // list of what point belongs to what centroid
  std::vector<double> pointsCentroid(datafmt.rows);

  cudaError_t err;
  double *pcentroids, *pdata, *pPointToCentroid;
  bool *pchanged;

  // malloc space for output centroid IDs
  cudaMalloc(&pPointToCentroid, datafmt.rows * sizeof(double));
  // list of centroids
  cudaMalloc(&pcentroids, numClusters * datafmt.cols * sizeof(double));
  cudaMalloc(&pdata, datafmt.rows * datafmt.cols * sizeof(double));
  cudaMalloc(&pchanged, sizeof(bool));

  // pointToCentroid init met 0, dus no need
  cudaMemcpy(pdata, allData.data(),
             datafmt.rows * datafmt.cols * sizeof(double),
             cudaMemcpyHostToDevice);

  err = cudaGetLastError();
  if (err != cudaSuccess) {
    std::cout << "CUDA malloc error " << err << std::endl;
    exit(1);
  }

  // const size_t BLOCKSIZE = 4;
  // size_t numXBlocks =
  //     (datafmt.rows / BLOCKSIZE) + (((datafmt.rows % BLOCKSIZE) != 0) ? 1 :
  //     0);
  // size_t numYBlocks =
  //     (datafmt.cols / BLOCKSIZE) + (((datafmt.cols % BLOCKSIZE) != 0) ? 1 :
  //     0);

  int threads = 256;
  int blocks = (datafmt.rows + threads - 1) / threads;

  // dient als timer
  cudaEvent_t startAllEvt, stopAllEvt;
  cudaEventCreate(&startAllEvt);
  cudaEventCreate(&stopAllEvt);

  cudaEventRecord(startAllEvt);

  // for (int r = 0; r < repetitions; r++) {
  // start anew & push to gpu for each rep
  initCentroids(rng, centroids, allData, datafmt);
  centroidDebugFile.write(centroids, datafmt.cols);
  cudaMemcpy(pcentroids, centroids.data(),
             datafmt.cols * numClusters * sizeof(double),
             cudaMemcpyHostToDevice);

  bool changed = false;
  double avgDist = 0;
  size_t numSteps = 0;
  do {
    changed = false;
    avgDist = 0;

    if (numSteps == 0) {
      std::cout << "Before" << std::endl;
      debugCentroids(centroids, datafmt);
    }
    {
      cudaMemset(pchanged, 0, sizeof(bool));
      // run kernel
      assignPtsToCentroids<<<blocks, threads>>>(
          pdata, pcentroids, pPointToCentroid, datafmt.rows, datafmt.cols,
          numClusters, pchanged);
      err = cudaDeviceSynchronize();
      if (err != cudaSuccess) {
        std::cout << "Runtime error: " << err << std::endl;
        exit(1);
      }

      cudaMemcpy(centroids.data(), pcentroids,
                 datafmt.cols * numClusters * sizeof(double),
                 cudaMemcpyDeviceToHost);
      cudaMemcpy(pointsCentroid.data(), pPointToCentroid,
                 datafmt.rows * sizeof(double), cudaMemcpyDeviceToHost);

      cudaMemcpy(&changed, pchanged, sizeof(bool), cudaMemcpyDeviceToHost);
      if (!changed)
        break;

      updateCentroids(allData.data(), centroids.data(), pointsCentroid.data(),
                      datafmt.rows, datafmt.cols, numClusters);
      cudaMemcpy(pcentroids, centroids.data(),
                 numClusters * datafmt.cols * sizeof(double),
                 cudaMemcpyHostToDevice);
    }

    if (numSteps == 0) {
      std::cout << "After" << std::endl;
      debugCentroids(centroids, datafmt);
    }
    centroidDebugFile.write(centroids, datafmt.cols);
    clustersDebugFile.write(pointsCentroid, datafmt.rows);

    numSteps++;

  } while (changed); // end while changed

  if (avgDist < bestDistSquaredSum) {
    bestDistSquaredSum = avgDist;
    bestCluster = pointsCentroid;
  }
  std::cout << "steps this rep: " << numSteps << std::endl;

  // stepsPerRepetition[r] = numSteps;

  // Make sure debug logging is only done on first iteration ; subsequent
  // checks with is_open will indicate that no logging needs to be done
  // anymore.
  centroidDebugFile.close();
  clustersDebugFile.close();

  // } // end reps
  cudaEventRecord(stopAllEvt);
  cudaEventSynchronize(stopAllEvt);

  float elapsed;
  cudaEventElapsedTime(&elapsed, startAllEvt, stopAllEvt);
  std::cerr << "# "
               "Type,blocks,threads,file,seed,clusters,repetitions,"
               "bestdistsquared,timeinseconds"
            << std::endl;
  std::cout << "cuda" << "," << numBlocks << "," << numThreads << ","
            << inputFile << "," << rng.getUsedSeed() << "," << numClusters
            << "," << repetitions << "," << bestDistSquaredSum << ","
            << elapsed / 1000 << std::endl;

  // Write the number of steps per repetition, kind of a signature of the work
  // involved
  csvOutputFile.write(stepsPerRepetition, "# Steps: ");
  // Write best clusters to csvOutputFile, something like
  csvOutputFile.write(bestCluster);

  cudaFree(pPointToCentroid);
  cudaFree(pcentroids);
  cudaFree(pdata);
  cudaFree(pchanged);
  cudaEventDestroy(startAllEvt);
  cudaEventDestroy(stopAllEvt);

  return 0;
}
