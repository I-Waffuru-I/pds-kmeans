#include "CSVWriter.hpp"
#include "centroids.hpp"
#include "helpers.hpp"
#include "rng.h"
#include <cfloat>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <numeric>
#include <vector>

namespace fs = std::filesystem;

// insane macro online gevonden
#define CUDA_CHECK(call)                                                       \
  do {                                                                         \
    cudaError_t e_ = (call);                                                   \
    if (e_ != cudaSuccess) {                                                   \
      std::cerr << "CUDA error: " << cudaGetErrorString(e_) << " at "          \
                << __FILE__ << ":" << __LINE__ << std::endl;                   \
      exit(1);                                                                 \
    }                                                                          \
  } while (0)

// void naiveClustering(std::vector<double> &centroids,
//                      std::vector<double> &allData, std::vector<int> &cPoints,
//                      double &avgDist, DataSize &size, bool &changed)

__global__ void assignPtsToCentroids(const double *data,
                                     const double *centroids,
                                     int *pointInCentroid, double *sums,
                                     int *counts, double *sqDist, size_t rows,
                                     size_t cols, size_t k, bool *changed) {

  extern __shared__ double smem[];
  double *sCentroids = smem;             // k*cols
  double *sSums = sCentroids + k * cols; // k*cols
  double *sTotal = sSums + k * cols;     // 1
  int *sCounts = (int *)(sTotal + 1);    // k   (ints last: alignment)

  // init
  for (size_t i = threadIdx.x; i < k * cols; i += blockDim.x) {
    sCentroids[i] = centroids[i];
    sSums[i] = 0.0;
  }
  for (size_t i = threadIdx.x; i < k; i += blockDim.x)
    sCounts[i] = 0;
  if (threadIdx.x == 0)
    *sTotal = 0.0;

  __syncthreads();

  // make kernel dim (512 or sum, numcols zo elke col thread een item doet ipv
  // for loop )

  // being pixel p
  // find closest cluster
  // check if this can be sped up through coalescent MA
  size_t idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (idx < rows) { // moet tot syncthreads hieronder geraken
    int bestK = 0;
    double minDist = DBL_MAX;
    for (size_t j = 0; j < k; j++) {
      double d = 0;
      // TODO idx & idy gebruiken ipv forloop
      for (size_t c = 0; c < cols; c++) {
        double diff = data[idx * cols + c] - sCentroids[j * cols + c];
        d += diff * diff;
      }
      if (d < minDist) {
        minDist = d;
        bestK = (int)j;
      }
    }

    if (pointInCentroid[idx] != bestK) {
      pointInCentroid[idx] = bestK;
      // data race boeit nie want t'is toch ma T/F
      *changed = true;
    }

    // maakt volgorde hier uit? idk chief
    for (size_t c = 0; c < cols; c++) {
      atomicAdd(&sSums[(size_t)bestK * cols + c], data[idx * cols + c]);
    }
    atomicAdd(&sCounts[bestK], 1);
    atomicAdd(sTotal, minDist);
  } // einde calc


  __syncthreads();

  // mergen van results

  for (size_t i = threadIdx.x; i < k*cols; i += blockDim.x)
    atomicAdd(&sums[i], sSums[i]);
  for (size_t i = threadIdx.x; i < k; i += blockDim.x)
    atomicAdd(&counts[i], sCounts[i]);

  if (threadIdx.x == 0)
    atomicAdd(sqDist, *sTotal);
}

// __global__ void updateCentroids(double *centroids, double *sums, int *counts,
//                                 double *moved, size_t cols, size_t k) {
__global__ void updateCentroids(double *centroids, double *sums, int *counts,
                                size_t cols, size_t k) {
  // elke thread is een k hier
  size_t idx = threadIdx.x;
  if (idx >= k)
    return;

  double sq = 0;
  if (counts[idx] > 0) {
    for (size_t c = 0; c < cols; c++) {
      double newVal = sums[idx * cols + c] / counts[idx];
      double diff = newVal - centroids[idx * cols + c];
      sq += diff * diff;
      centroids[idx * cols + c] = newVal;
    }
  }
  // CLEAN
  // moved[idx] = sqrt(sq);

  // reset voor volgende step
  for (size_t c = 0; c < cols; c++) {
    sums[idx * cols + c] = 0;
  }
  counts[idx] = 0;
}

// tmp werken met serial stuk om te checken of de eerste kernel werkt
void tmpUpdateCentroids(const double *data, double *centroids,
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
    int dev = 0;
    cudaError_t e = cudaGetDeviceCount(&dev);
    if (e != cudaSuccess || dev < 1) {
      std::cerr << "No CUDA device found!" << std::endl;
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
  std::vector<int> bestCluster(datafmt.rows);
  // to save the number of steps each rep needed
  std::vector<size_t> stepsPerRepetition(repetitions);
  std::vector<double> centroids(numClusters * datafmt.cols);
  // duuw alle point dists hier in en tel ze op
  // std::vector<double> dists(datafmt.cols);
  // list of what point belongs to what centroid
  std::vector<int> pointsCentroid(datafmt.rows);
  // distance each centroid moved in the last iteration
  std::vector<double> moved(numClusters);

  double *pcentroids, *pdata, *psums, *psqDist, *pmoved;
  int *pPointToCentroid, *pcounts;
  bool *pchanged;

  CUDA_CHECK(cudaMalloc(&pPointToCentroid, datafmt.rows * sizeof(int)));
  CUDA_CHECK(
      cudaMalloc(&pcentroids, numClusters * datafmt.cols * sizeof(double)));
  CUDA_CHECK(cudaMalloc(&pdata, datafmt.rows * datafmt.cols * sizeof(double)));
  CUDA_CHECK(cudaMalloc(&psums, numClusters * datafmt.cols * sizeof(double)));
  CUDA_CHECK(cudaMalloc(&pcounts, numClusters * sizeof(int)));
  CUDA_CHECK(cudaMalloc(&pmoved, numClusters * sizeof(double)));
  CUDA_CHECK(cudaMalloc(&pchanged, sizeof(bool)));
  CUDA_CHECK(cudaMalloc(&psqDist, sizeof(double)));

  CUDA_CHECK(cudaMemcpy(pdata, allData.data(),
                        datafmt.rows * datafmt.cols * sizeof(double),
                        cudaMemcpyHostToDevice));

  int threads = 256;
  int blocks = (datafmt.rows + threads - 1) / threads;

  // dient als timer
  cudaEvent_t startAllEvt, stopAllEvt;
  CUDA_CHECK(cudaEventCreate(&startAllEvt));
  CUDA_CHECK(cudaEventCreate(&stopAllEvt));

  CUDA_CHECK(cudaEventRecord(startAllEvt));

  size_t sharedMem = (2 * numClusters * datafmt.cols + 1) * sizeof(double) + numClusters *sizeof(int);

  for (int r = 0; r < repetitions; r++) {
    // start anew & push to gpu for each rep
    initCentroids(rng, centroids, allData, datafmt);
    centroidDebugFile.write(centroids, datafmt.cols);
    CUDA_CHECK(cudaMemcpy(pcentroids, centroids.data(),
                          numClusters * datafmt.cols * sizeof(double),
                          cudaMemcpyHostToDevice));
    // default naar -1 in hex
    CUDA_CHECK(cudaMemset(pPointToCentroid, 0xFF, datafmt.rows * sizeof(int)));
    CUDA_CHECK(
        cudaMemset(psums, 0, numClusters * datafmt.cols * sizeof(double)));
    CUDA_CHECK(cudaMemset(pcounts, 0, numClusters * sizeof(int)));

    bool changed = false;
    size_t numSteps = 0;
    do {
      CUDA_CHECK(cudaMemset(pchanged, 0, sizeof(bool)));
      CUDA_CHECK(cudaMemset(psqDist, 0, sizeof(double)));

      // if (numSteps == 0) {
      //   std::cout << "Before" << std::endl;
      //   debugCentroids(centroids, datafmt);
      // }
      assignPtsToCentroids<<<blocks, threads, sharedMem>>>(
          pdata, pcentroids, pPointToCentroid, psums, pcounts, psqDist,
          datafmt.rows, datafmt.cols, numClusters, pchanged);
      updateCentroids<<<1, numClusters>>>(pcentroids, psums, pcounts,
                                          datafmt.cols, numClusters);
      // updateCentroids(allData.data(), centroids.data(),
      //                 pointsCentroid.data(), datafmt.rows, datafmt.cols,
      //                 numClusters);
      CUDA_CHECK(cudaGetLastError());

      // blocking copies: these also wait for both kernels to finish
      CUDA_CHECK(
          cudaMemcpy(&changed, pchanged, sizeof(bool), cudaMemcpyDeviceToHost));
      // CUDA_CHECK(cudaMemcpy(moved.data(), pmoved, numClusters *
      // sizeof(double),
      //                       cudaMemcpyDeviceToHost));
      numSteps++;

      // data only comes back to the host when a debug file needs it
      if (centroidDebugFile.is_open()) {
        CUDA_CHECK(cudaMemcpy(centroids.data(), pcentroids,
                              numClusters * datafmt.cols * sizeof(double),
                              cudaMemcpyDeviceToHost));
        centroidDebugFile.write(centroids, datafmt.cols);
      }
      if (clustersDebugFile.is_open()) {
        CUDA_CHECK(cudaMemcpy(pointsCentroid.data(), pPointToCentroid,
                              datafmt.rows * sizeof(int),
                              cudaMemcpyDeviceToHost));
        clustersDebugFile.write(pointsCentroid, datafmt.rows);
      }

    } while (changed); // end while changed

    // sqDist still holds the last pass: no assignment changed, so the
    // centroids it measured against were already the means -> final SSE
    double distSum = 0;
    CUDA_CHECK(
        cudaMemcpy(&distSum, psqDist, sizeof(double), cudaMemcpyDeviceToHost));
    CUDA_CHECK(cudaMemcpy(pointsCentroid.data(), pPointToCentroid,
                          datafmt.rows * sizeof(int), cudaMemcpyDeviceToHost));

    if (distSum < bestDistSquaredSum) {
      bestDistSquaredSum = distSum;
      bestCluster = pointsCentroid;
    }

    std::cerr << "steps this rep: " << numSteps << std::endl;
    stepsPerRepetition[r] = numSteps;

    centroidDebugFile.close();
    clustersDebugFile.close();

  } // end reps

  CUDA_CHECK(cudaEventRecord(stopAllEvt));
  CUDA_CHECK(cudaEventSynchronize(stopAllEvt));

  float elapsed;
  CUDA_CHECK(cudaEventElapsedTime(&elapsed, startAllEvt, stopAllEvt));
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
  cudaFree(psums);
  cudaFree(pcounts);
  cudaFree(pmoved);
  cudaFree(pchanged);
  cudaFree(psqDist);
  cudaEventDestroy(startAllEvt);
  cudaEventDestroy(stopAllEvt);

  return 0;
}
