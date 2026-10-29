#include "CSVReader.hpp"
#include "CSVWriter.hpp"
#include "rng.h"
#include "timer.h"
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>
#include <filesystem>

#include "util.cpp"
#include "naive.cpp"


// Ik zag dat is gebruikt worden deze structuur en wat dat eens proberen
// filesystem is blijkbaar pas geïntroduceerd vanaf cpp17 dus dat pas ik even
// aan
namespace fs = std::filesystem;

void usage() {
  std::cerr << R"XYZ(
Usage:

  kmeans --input inputfile.csv --output outputfile.csv --k numclusters --repetitions numrepetitions --seed seed [--blocks numblocks] [--threads numthreads] [--trace clusteridxdebug.csv] [--centroidtrace centroiddebug.csv]

Arguments:

 --input:
 
   Specifies input CSV file, number of rows represents number of points, the
   number of columns is the dimension of each point.

 --output:

   Output CSV file, just a single row, with as many entries as the number of
   points in the input file. Each entry is the index of the cluster to which
   the point belongs. The script 'visualize_clusters.py' can show this final
   clustering.

 --k:

   The number of clusters that should be identified.

 --repetitions:

   The number of times the k-means algorithm is repeated; the best clustering
   is kept.

 --blocks:

   Only relevant in CUDA version, specifies the number of blocks that can be
   used.

 --threads:

   Not relevant for the serial version. For the OpenMP version, this number 
   of threads should be used. For the CUDA version, this is the number of 
   threads per block. For the MPI executable, this should be ignored, but
   the wrapper script 'mpiwrapper.sh' can inspect this to run 'mpirun' with
   the correct number of processes.

 --seed:

   Specifies a seed for the random number generator, to be able to get 
   reproducible results.

 --trace:

   Debug option - do NOT use this when timing your program!

   For each repetition, the k-means algorithm goes through a sequence of 
   increasingly better cluster assignments. If this option is specified, this
   sequence of cluster assignments should be written to a CSV file, similar
   to the '--output' option. Instead of only having one line, there will be
   as many lines as steps in this sequence. If multiple repetitions are
   specified, only the results of the first repetition should be logged
   for clarity. The 'visualize_clusters.py' program can help to visualize
   the data logged in this file.

 --centroidtrace:

   Debug option - do NOT use this when timing your program!

   Should also only log data during the first repetition. The resulting CSV 
   file first logs the randomly chosen centroids from the input data, and for
   each step in the sequence, the updated centroids are logged. The program 
   'visualize_centroids.py' can be used to visualize how the centroids change.
   
)XYZ";
  exit(-1);
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

FileCSVWriter openDebugFile(const std::string &n) {
  FileCSVWriter f;

  if (n.length() != 0) {
    f.open(n);
    if (!f.is_open())
      std::cerr << "WARNING: Unable to open debug file " << n << std::endl;
  }
  return f;
}

void initCentroids(Rng &rng, std::vector<double> &centroids,
                   std::vector<double> &allData, DataSize &dsize) {
  size_t ccount = centroids.size() / dsize.cols;
  std::vector<size_t> centroid_indices(ccount);
  std::cout << "size: " << dsize.rows << ", " << dsize.cols << std::endl;
  std::cout << "cluster count: " << ccount << std::endl;
  rng.pickRandomIndices(dsize.rows, centroid_indices);
  for (int i = 0; i < ccount; i++) {
    size_t row = centroid_indices[i];
    for (int e = 0; e < dsize.cols; e++) {
      centroids[i * dsize.cols + e] = allData[row * dsize.cols + e];
    }
  }
}

void debugCentroids(std::vector<double> &centroids, DataSize &size) {
  std::cout << "debug centroid: " << std::endl;
  for (int r = 0; r < centroids.size() / size.cols; r++) {
    for (int c = 0; c < size.cols; c++) {
      std::cout << centroids[r * size.cols + c] << ", ";
    }
    std::cout << std::endl;
  }
}

void debugCentroidPoints(std::vector<int> &pCentroid) {
  std::cout << "Debug centroid points" << std::endl;
  for (int r = 0; r < pCentroid.size(); r++) {
    std::cout << pCentroid[r] << ",";
  }
  std::cout << std::endl;
}


int kmeans(Rng &rng, const std::string &inputFile,
           const std::string &outputFileName, int numClusters, int repetitions,
           int numBlocks, int numThreads,
           const std::string &centroidDebugFileName,
           const std::string &clusterDebugFileName) {

  // If debug filenames are specified, this opens them. The is_open method
  // can be used to check if they are actually open and should be written to.
  FileCSVWriter centroidDebugFile = openDebugFile(centroidDebugFileName);
  FileCSVWriter clustersDebugFile = openDebugFile(clusterDebugFileName);

  // Ik had een probleem eerst dat als de output/ dir nog niet bestaat het
  // programma niet wilt werken. Dus we zullen eerst checken of de map er is en
  // deze aanmaken indien nodig

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
    // throw e;
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
  DataSize size = readData(datasetFile, allData);

  // This is a basic timer from std::chrono ; feel free to use the appropriate
  // timer for each of the technologies, e.g. OpenMP has omp_get_wtime()
  Timer timer;

  double bestDistSquaredSum =
      std::numeric_limits<double>::max(); // can only get better
  std::vector<int> bestCluster(size.rows);
  std::vector<size_t> stepsPerRepetition(
      repetitions); // to save the number of steps each rep needed

  // We calculate the min and max bounds so we can more efficiëntly set up the
  // random centroids
  std::vector<double> centroids(numClusters * size.cols);
  std::vector<double> oldCentroids(numClusters * size.cols);

  // Also a list to keep track of which points where assigned to what centroid
  std::vector<int> pointsCentroid(size.rows);
  pointsCentroid.assign(allData.size() / size.cols, -1);
  // Do the k-means routine a number of times, each time starting from
  // different random centroids (use Rng::pickRandomIndices), and keep
  // the best result of these repetitions.
  for (int r = 0; r < repetitions; r++) {
    size_t numSteps = 0;

    // debugCentroids(centroids, size);
    // They already seem to get randomly initialized
    initCentroids(rng, centroids, allData, size);
    // debugCentroids(centroids, size);
    centroidDebugFile.write(centroids, size.cols);

    AutoAverageTimer timer("time naïve clustering");
    timer.start();
    bool changed = true;

    double avgDist = 0;
    while (changed) {
      avgDist = 0;
      // debugCentroidPoints(pointsCentroid);

      // oldCentroids = centroids;

      // std::cout << "Before" << std::endl;
      // debugCentroids(centroids, size);
      naiveClustering(centroids, allData, pointsCentroid, avgDist, size,
                      changed);

      // std::cout << "After" << std::endl;
      // debugCentroids(centroids, size);

      // std::cout << "Old" << std::endl;
      // debugCentroids(oldCentroids, size);

      // Write all centroids to file:
      if (changed) {

        centroidDebugFile.write(centroids, size.cols);
      }
			// Om een of andere reden moet dit er wel uit blijven en nog een keer geschreven worden
        clustersDebugFile.write(pointsCentroid, size.rows);

      numSteps++;
    }
    // std::cout << "Best dist: " << bestDistSquaredSum
    //           << " | avgDist: " << avgDist << std::endl;
    // Deze stond eerst in de  binnenste loop waardoor ook nog eens werd gekeken
    // naar aparte iteraties in de iteraties en het eindresultaat dus niet
    // overeenkwam.
    if (avgDist < bestDistSquaredSum) {
      // std::cout << "Chose repetition: " << r << std::endl;

      bestDistSquaredSum = avgDist;
      bestCluster = pointsCentroid;
    }

    timer.stop();
    stepsPerRepetition[r] = numSteps;

    // bool changed = true;
    // while (changed) {
    //
    //
    //
    // }

    // Make sure debug logging is only done on first iteration ; subsequent
    // checks with is_open will indicate that no logging needs to be done
    // anymore.
    centroidDebugFile.close();
    clustersDebugFile.close();
  }

  timer.stop();

  // Some example output, of course you can log your timing data anyway you
  // like.
  std::cerr << "# "
               "Type,blocks,threads,file,seed,clusters,repetitions,"
               "bestdistsquared,timeinseconds"
            << std::endl;
  std::cout << "sequential," << numBlocks << "," << numThreads << ","
            << inputFile << "," << rng.getUsedSeed() << "," << numClusters
            << "," << repetitions << "," << bestDistSquaredSum << ","
            << timer.durationNanoSeconds() / 1e9 << std::endl;

  // Write the number of steps per repetition, kind of a signature of the work
  // involved
  csvOutputFile.write(stepsPerRepetition, "# Steps: ");
  // Write best clusters to csvOutputFile, something like
  csvOutputFile.write(bestCluster);

  return 0;
}

int mainCxx(const std::vector<std::string> &args) {
  if (args.size() % 2 != 0)
    usage();

  std::string inputFileName, outputFileName, centroidTraceFileName,
      clusterTraceFileName;
  unsigned long seed = 54030599202;

  int numClusters = -1, repetitions = -1;
  int numBlocks = 1, numThreads = 1;
  for (int i = 0; i < args.size(); i += 2) {
    if (args[i] == "--input")
      inputFileName = args[i + 1];
    else if (args[i] == "--output")
      outputFileName = args[i + 1];
    else if (args[i] == "--centroidtrace")
      centroidTraceFileName = args[i + 1];
    else if (args[i] == "--trace")
      clusterTraceFileName = args[i + 1];
    else if (args[i] == "--k")
      numClusters = stoi(args[i + 1]);
    else if (args[i] == "--repetitions")
      repetitions = stoi(args[i + 1]);
    else if (args[i] == "--seed")
      seed = stoul(args[i + 1]);
    else if (args[i] == "--blocks")
      numBlocks = stoi(args[i + 1]);
    else if (args[i] == "--threads")
      numThreads = stoi(args[i + 1]);
    else {
      std::cerr << "Unknown argument '" << args[i] << "'" << std::endl;
      return -1;
    }
  }

  if (inputFileName.length() == 0 || outputFileName.length() == 0 ||
      numClusters < 1 || repetitions < 1 || seed == 0)
    usage();

  Rng rng(seed);

  return kmeans(rng, inputFileName, outputFileName, numClusters, repetitions,
                numBlocks, numThreads, centroidTraceFileName,
                clusterTraceFileName);
}

int main(int argc, char *argv[]) {
  std::vector<std::string> args;
  for (int i = 1; i < argc; i++)
    args.push_back(argv[i]);

  return mainCxx(args);
}
