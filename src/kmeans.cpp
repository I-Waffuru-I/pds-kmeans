#include "kmeans.hpp"
#include "CSVWriter.hpp"
#include "centroids.hpp"
#include "helpers.hpp"
#include "naive.hpp"
#include "timer.h"
#include <filesystem>
#include <iostream>
#include <limits>
#ifdef HAVE_OMP
#include <omp.h>
#endif

namespace fs = std::filesystem;

int kmeansSerial(Rng &rng, const std::string &inputFile,
                 const std::string &outputFileName, int numClusters,
                 int repetitions, int numBlocks, int numThreads,
                 const std::string &centroidDebugFileName,
                 const std::string &clusterDebugFileName,
                 const std::string &mode)
{

	// If debug filenames are specified, this opens them. The is_open method
	// can be used to check if they are actually open and should be written to.
	FileCSVWriter centroidDebugFile = openDebugFile(centroidDebugFileName);
	FileCSVWriter clustersDebugFile = openDebugFile(clusterDebugFileName);

	// Ik had een probleem eerst dat als de output/ dir nog niet bestaat het
	// programma niet wilt werken. Dus we zullen eerst checken of de map er is en
	// deze aanmaken indien nodig

	fs::path dirPath;

	try
	{
		dirPath = fs::path(outputFileName).parent_path();
		if (fs::create_directories(dirPath))
		{
			std::cout << "Created new directory" << std::endl;
		}
		else
		{
			std::cout << "Directory already exists" << std::endl;
		}
	}
	catch (std::exception e)
	{

		std::cout << e.what() << std::endl;
		// throw e;
	}

	FileCSVWriter csvOutputFile(outputFileName);
	if (!csvOutputFile.is_open())
	{
		std::cerr << "Unable to open output file " << outputFileName << std::endl;
		return -1;
	}

	std::ifstream datasetFile;
	datasetFile.open(inputFile);
	if (!datasetFile.is_open())
	{
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

	timer.start();

	for (int r = 0; r < repetitions; r++)
	{
		size_t numSteps = 0;

		// debugCentroids(centroids, size);
		// They already seem to get randomly initialized
		initCentroids(rng, centroids, allData, size);
		// debugCentroids(centroids, size);
		centroidDebugFile.write(centroids, size.cols);

		// AutoAverageTimer timer2("time naïve clustering");
		// timer2.start();
		bool changed = true;

		double avgDist = 0;
		while (changed)
		{
			avgDist = 0;
			// debugCentroidPoints(pointsCentroid);

			// oldCentroids = centroids;

			// std::cout << "Before" << std::endl;
			// debugCentroids(centroids, size);
			// Not a lot of different onces for now, maybe eventually give the mode to the clustering as well and change behavior from there
			if (mode == "serial")
			{
				naiveClustering(centroids, allData, pointsCentroid, avgDist, size,
				                changed);
			}
			else
			{
				naiveClustering(centroids, allData, pointsCentroid, avgDist, size,
				                changed);
			}

			// std::cout << "Done  rep" << std::endl;

			// std::cout << "After" << std::endl;
			// debugCentroids(centroids, size);

			// std::cout << "Old" << std::endl;
			// debugCentroids(oldCentroids, size);

			// Write all centroids to file:
			if (changed)
			{

				centroidDebugFile.write(centroids, size.cols);
			}
			// Om een of andere reden moet dit er wel uit blijven en nog een keer
			// geschreven worden
			clustersDebugFile.write(pointsCentroid, size.rows);

			numSteps++;
		}
		// std::cout << "Best dist: " << bestDistSquaredSum
		//           << " | avgDist: " << avgDist << std::endl;
		// Deze stond eerst in de  binnenste loop waardoor ook nog eens werd
		// gekeken naar aparte iteraties in de iteraties en het eindresultaat dus
		// niet overeenkwam.
		if (avgDist < bestDistSquaredSum)
		{
			// std::cout << "Chose repetition: " << r << std::endl;

			bestDistSquaredSum = avgDist;

			bestCluster = pointsCentroid;
		}

		// timer.stop();

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

		// timer2.stop();
	}
	timer.stop();

	// Some example output, of course you can log your timing data anyway you
	// like.
	std::cerr << "# "
	             "Type,Submode,blocks,threads,file,seed,clusters,repetitions,"
	             "bestdistsquared,timeinseconds"
	          << std::endl;
	std::cout << "sequential," << mode << "," << numBlocks << "," << numThreads << ","
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

int kmeansOMP(Rng &rng, const std::string &inputFile,
              const std::string &outputFileName, int numClusters,
              int repetitions, int numBlocks, int numThreads,
              const std::string &centroidDebugFileName,
              const std::string &clusterDebugFileName,
              const std::string &mode)
{

	// If debug filenames are specified, this opens them. The is_open method
	// can be used to check if they are actually open and should be written to.
	FileCSVWriter centroidDebugFile = openDebugFile(centroidDebugFileName);
	FileCSVWriter clustersDebugFile = openDebugFile(clusterDebugFileName);

	// Ik had een probleem eerst dat als de output/ dir nog niet bestaat het
	// programma niet wilt werken. Dus we zullen eerst checken of de map er is en
	// deze aanmaken indien nodig

	fs::path dirPath;

	try
	{
		dirPath = fs::path(outputFileName).parent_path();
		if (fs::create_directories(dirPath))
		{
			std::cout << "Created new directory" << std::endl;
		}
		else
		{
			std::cout << "Directory already exists" << std::endl;
		}
	}
	catch (std::exception e)
	{

		std::cout << e.what() << std::endl;
		// throw e;
	}

	FileCSVWriter csvOutputFile(outputFileName);
	if (!csvOutputFile.is_open())
	{
		std::cerr << "Unable to open output file " << outputFileName << std::endl;
		return -1;
	}

	std::ifstream datasetFile;
	datasetFile.open(inputFile);
	if (!datasetFile.is_open())
	{
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
	std::vector<std::vector<double>> centroids(
	    repetitions, std::vector<double>(numClusters * size.cols));
	std::vector<double> oldCentroids(numClusters * size.cols);

	std::vector<std::vector<std::vector<double>>> centroidsDebug(repetitions);
	std::vector<std::vector<std::vector<int>>> clustersDebug(repetitions);

	// Also a list to keep track of which points where assigned to what centroid
	std::vector<std::vector<int>> pointsCentroid(repetitions,
	                                             std::vector<int>(size.rows));

	// Do the k-means routine a number of times, each time starting from
	// different random centroids (use Rng::pickRandomIndices), and keep
	// the best result of these repetitions.

	timer.start();

	// int outerThreads = numThreads;
	//  if (numThreads != 0)
	// 	outerThreads = std::min(numThreads, repetitions);
	//
	//  int innerLoopThreads = (numThreads - repetitions) / repetitions + 1;

#ifdef HAVE_OMP
	omp_set_num_threads(numThreads);
	// omp_set_max_active_levels(2);
#endif
	// omp_set_max_active_levels(2);

	// Hier definiëren want in de loop zorgt dit voor heel random waarden (niet
	// echt meetbaar)
	for (int i = 0; i < repetitions; i++)
	{
		pointsCentroid[i].assign(allData.size() / size.cols, -1);

		// debugCentroids(centroids, size);
		// They already seem to get randomly initialized
		initCentroids(rng, centroids[i], allData, size);
	}

	// int outer = 0;
	// int centroidNumber = centroids.size() / size.cols;
	int centroidNumber = numClusters;

	size_t stride = size.cols + 1;
	// This is the shared mapa
	std::vector<double> centroidMap(
	    stride * centroidNumber);

	for (int r = 0; r < repetitions; r++)
	{
		size_t numSteps = 0;

		// debugCentroids(centroids, size);
		// centroidDebugFile.write(centroids[r], size.cols);
		if (centroidDebugFile.is_open())
			centroidsDebug[r].push_back(centroids[r]);

		// AutoAverageTimer timer2("time naïve clustering");
		// timer2.start();

		bool changed = true;
		double avgDist = 0;
		do
		{
			std::fill(centroidMap.begin(), centroidMap.end(), 0.0);

			avgDist = 0;
			// debugCentroidPoints(pointsCentroid);

			// oldCentroids = centroids;

			// std::cout << "Before" << std::endl;
			// debugCentroids(centroids, size);
			// Default OMP mode: "omp" or "omp-naive"
			naiveOMPClustering(centroids[r], allData, pointsCentroid[r], centroidMap, avgDist,
			                   size, changed, centroidNumber);

			// Write all centroids to file:
			// Even disablen want dit zou raceconditions veroorzaken
			if (changed)
			{

				if (centroidDebugFile.is_open())
					centroidsDebug[r].push_back(centroids[r]);
				// centroidDebugFile.write(centroids[r], size.cols);
			}
			// Om een of andere reden moet dit er wel uit blijven en nog een keer
			// geschreven worden
			// Even disablen want dit zou racecondigtions veroorzaken.
			// TODO: Vervangen door een array met wat te schrijven?
			// clustersDebugFile.write(pointsCentroid[r], size.rows);
			if (clustersDebugFile.is_open())
				clustersDebug[r].push_back(pointsCentroid[r]);

			numSteps++;
		} while (changed);

		// std::cout << "Loop completed" << std::endl;
		// std::cout << "Best dist: " << bestDistSquaredSum
		//           << " | avgDist: " << avgDist << std::endl;
		// Deze stond eerst in de  binnenste loop waardoor ook nog eens werd
		// gekeken naar aparte iteraties in de iteraties en het eindresultaat dus
		// niet overeenkwam.

		if (avgDist < bestDistSquaredSum)
		{
			// std::cout << "Chose repetition: " << r << std::endl;

			bestDistSquaredSum = avgDist;

			bestCluster = pointsCentroid[r];
		}

		// timer.stop();

		// This shouldn't create race conditions as it accesses a different spot of
		// the vector for a repetition
		stepsPerRepetition[r] = numSteps;

		// bool changed = true;
		// while (changed) {
		//
		//
		//
		// }

		// timer2.stop();
	}

	timer.stop();

	// Hier moeten we ook nog even alles uit de nieuwe vectors halen en schrijven
	// naar de files
	for (int r = 0; r < 1; r++)
	{
		// Eerst de centroidsDebug
		for (size_t i = 0; i < centroidsDebug[r].size(); i++)
		{
			centroidDebugFile.write(centroidsDebug[r][i], size.cols);
		}

		for (size_t i = 0; i < clustersDebug[r].size(); i++)
		{
			clustersDebugFile.write(clustersDebug[r][i], size.rows);
		}
	}
	// Make sure debug logging is only done on first iteration ; subsequent
	// checks with is_open will indicate that no logging needs to be done
	// anymore.
	centroidDebugFile.close();
	clustersDebugFile.close();

	// Some example output, of course you can log your timing data anyway you
	// like.
	std::cerr << "# "
	             "Type,Submode,blocks,threads,file,seed,clusters,repetitions,"
	             "bestdistsquared,timeinseconds"
	          << std::endl;
	std::cout << "parallel," << mode << "," << numBlocks << "," << numThreads << ","
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

int kmeansOMP2(Rng &rng, const std::string &inputFile,
               const std::string &outputFileName, int numClusters,
               int repetitions, int numBlocks, int numThreads,
               const std::string &centroidDebugFileName,
               const std::string &clusterDebugFileName,
               const std::string &mode)
{

	// If debug filenames are specified, this opens them. The is_open method
	// can be used to check if they are actually open and should be written to.
	FileCSVWriter centroidDebugFile = openDebugFile(centroidDebugFileName);
	FileCSVWriter clustersDebugFile = openDebugFile(clusterDebugFileName);

	// Ik had een probleem eerst dat als de output/ dir nog niet bestaat het
	// programma niet wilt werken. Dus we zullen eerst checken of de map er is en
	// deze aanmaken indien nodig

	fs::path dirPath;

	try
	{
		dirPath = fs::path(outputFileName).parent_path();
		if (fs::create_directories(dirPath))
		{
			std::cout << "Created new directory" << std::endl;
		}
		else
		{
			std::cout << "Directory already exists" << std::endl;
		}
	}
	catch (std::exception e)
	{

		std::cout << e.what() << std::endl;
		// throw e;
	}

	FileCSVWriter csvOutputFile(outputFileName);
	if (!csvOutputFile.is_open())
	{
		std::cerr << "Unable to open output file " << outputFileName << std::endl;
		return -1;
	}

	std::ifstream datasetFile;
	datasetFile.open(inputFile);
	if (!datasetFile.is_open())
	{
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
	std::vector<std::vector<double>> centroids(
	    repetitions, std::vector<double>(numClusters * size.cols));
	std::vector<double> oldCentroids(numClusters * size.cols);

	std::vector<std::vector<std::vector<double>>> centroidsDebug(repetitions);
	std::vector<std::vector<std::vector<int>>> clustersDebug(repetitions);

	// Also a list to keep track of which points where assigned to what centroid
	std::vector<std::vector<int>> pointsCentroid(repetitions,
	                                             std::vector<int>(size.rows));

	// Do the k-means routine a number of times, each time starting from
	// different random centroids (use Rng::pickRandomIndices), and keep
	// the best result of these repetitions.

	timer.start();

	// int outerThreads = numThreads;
	//  if (numThreads != 0)
	// 	outerThreads = std::min(numThreads, repetitions);
	//
	//  int innerLoopThreads = (numThreads - repetitions) / repetitions + 1;

#ifdef HAVE_OMP
	omp_set_num_threads(numThreads);
	// omp_set_max_active_levels(2);
#endif
	// omp_set_max_active_levels(2);

	// Hier definiëren want in de loop zorgt dit voor heel random waarden (niet
	// echt meetbaar)
	for (int i = 0; i < repetitions; i++)
	{
		pointsCentroid[i].assign(allData.size() / size.cols, -1);

		// debugCentroids(centroids, size);
		// They already seem to get randomly initialized
		initCentroids(rng, centroids[i], allData, size);
	}

	// int outer = 0;
	// int centroidNumber = centroids.size() / size.cols;
	int centroidNumber = numClusters;

	size_t stride = size.cols + 1;
	// This is the shared mapa
	std::vector<double> centroidMap(
	    stride * centroidNumber);

	for (int r = 0; r < repetitions; r++)
	{
		size_t numSteps = 0;

		// debugCentroids(centroids, size);
		// centroidDebugFile.write(centroids[r], size.cols);
		if (centroidDebugFile.is_open())
			centroidsDebug[r].push_back(centroids[r]);

		// AutoAverageTimer timer2("time naïve clustering");
		// timer2.start();

		bool changed = true;
		double avgDist = 0;
		do
		{
			std::fill(centroidMap.begin(), centroidMap.end(), 0.0);

			avgDist = 0;
			// debugCentroidPoints(pointsCentroid);

			// oldCentroids = centroids;

			// std::cout << "Before" << std::endl;
			// debugCentroids(centroids, size);
			// Default OMP mode: "omp" or "omp-naive"
			// naiveOMPClustering(centroids[r], allData, pointsCentroid[r], centroidMap, avgDist,
			//                    size, changed, centroidNumber);
			// centroids -> centroids, allData -> allData, cPoints -> pointsCentroid[r], centroidMap -> centroidMap, avgDist -> avgDist, size -> size, changed -> changed, centroidNumber -> centroidNumber
			// We slaan hier de begin index van elk punt op en kunnen dit aan de hand van
			// de dimentie eruit halen
			// std::pmr::unordered_map<int, std::vector<double>> centroidMap;

			size_t stride = size.cols + 1;

			// We zetten ook eerst changed op false
			changed = false;
			// We gaan per dimentie hoveelheid de punten af

			// std::cout << "stride: " << stride * centroidNumber << std::endl;

			// We gebruiken eerst een gewone parallel zodat we voor een thread eerst een
			// localCentroidMap kunnen definieren We gebruiken ook een reduce variabele
			// voor de avgDist en de changed bool zodat we critical en atomic kunnen
			// vermijden
			// RESULTAAT: 4.5 sec => 0.11
#pragma omp parallel reduction(+ : avgDist) reduction(|| : changed)
			{
				// TODO: Dit moet er eigenlijk ook nog uitgezet worden zodat we niet elke iteratie een nieuwe creeren, niet efficient momenteel.
				std::vector<double> localCentroidMap(
				    stride * centroidNumber);
				// std::fill(localCentroidMap.begin(), localCentroidMap.end(), 0.0);

// THREADS moeten niet wachten voordat ze mergen dus dat kan al worden meegegegeven
#pragma omp for nowait
				for (size_t ii = 0; ii < size.rows; ++ii)
				{
					double minDist =
					    std::numeric_limits<double>::max(); // can only get better
					// int cIndex = size.cols + 1;
					int cIndex = -1;

					double partTime;
					// We moeten ook de cI traverseren per cols

					// std::cout << "Before s" << std::endl;
					for (int cI = 0; cI < centroidNumber; ++cI)
					{
						double dist = 0;
						// Alle punten afgaan van alle dimenties
						// std::cout << "Point: ";

						for (size_t c = 0; c < size.cols; c++)
						{
							double diff = allData[ii * size.cols + c] - centroids[r][cI * size.cols + c];

							dist += diff * diff;
							// NO FUCKING WAY, DIT WAS DE BOOSDOENER zorgt voor een versnelling van ongeveer 15 sec => 1.5 als ik het weghaal. Godverdomme
							// dist += std::pow(diff, 2);
						}

						// std::cout << "Dist to centroid: " << cI / size.cols << " Dist: " <<
						// dist << std::endl;

						// Check if is smaller than smallest distance
						if (dist < minDist)
						{
							minDist = dist;
							// We delen hier door het aantal dimenties om eruit te halen op welke
							// index we zitten
							cIndex = cI;
						}
					}

					// #ifdef HAVE_OMP
					// partTime = omp_get_wtime();
					// #endif
					// Som van squareddist
					avgDist += minDist;

					// Voeg hier het punt aan de juiste cluster toe via de map
					// Kan ik hier eigenlijk niet al de waardes van punten optellen bij andere
					// op basis van hun dimentie En dan achteraf delen door het aantal punten
					// dat hier eigenlijk in zat? We moeten de vector dan wel een vaste
					// grootte geven van cols + 1 => de +1 voor het aantal punten mee te geven
					// centroidMap[cIndex].push_back(i);

					int pointIndex = ii;
					if (pointsCentroid[r][pointIndex] != cIndex)
					{
						changed = true;

						pointsCentroid[r][pointIndex] = cIndex;
						// std::cout << "Changed point" << std::endl;
					}

					// centroidMap[cIndex].reserve(size.cols);
					for (size_t c = 0; c < size.cols; c++)
					{
						// std::cout << allData[c+i] << " , ";
						// std::cout << "Map length: " << localCentroidMap.size() << " Current index: " << cIndex * stride + c << std::endl;
						localCentroidMap[cIndex * stride + c] += allData[ii * size.cols + c];

						// std::cout << "After s" << std::endl;
					}
					localCentroidMap[cIndex * stride + size.cols] += 1;

					// #ifdef HAVE_OMP
					// 			partTime = omp_get_wtime() - partTime;
					// #else
					// (void)partTime;
					// #endif

					// #pragma omp atomic
					// totalTime += partTime;

					// std::cout << "CIndex: " << cIndex << " Distance: " << minDist <<
					// std::endl;
				}

// Nu moeten we gewoon de locale maps reducen naar de shared centroid map met
// deze keer maar 1 critical
#pragma omp critical
				{
					for (int r = 0; r < centroidNumber; r++)
					{
						for (size_t c = 0; c < size.cols + 1; c++)
						{
							centroidMap[r * stride + c] += localCentroidMap[r * stride + c];
						}
					}
				}
			}

			avgDist = avgDist / size.rows;

			// std::cout << "Total time on thread: " << omp_get_thread_num() << " for
			// observerd opp: " << totalTime << std::endl;

			// AutoAverageTimer timer("centroid sum");
			// timer.start();
			for (int i = 0; i < centroidNumber; i++)
			{
				// std::cout << "Centroid " << i << ":";
				// std::cout << "Amount of points: " << centroidMap[i][size.cols] <<
				// std::endl;

				double count = centroidMap[i * stride + size.cols];
				if (count > 0)
				{
					for (size_t p = 0; p < size.cols; p++)
					{
						// Total sum divided by total amount of points
						// If  there are  no points  assigned to a  centroid we avoid dividing by
						// zero
						// #pragma omp critical
						//       {
						centroids[r][i * size.cols + p] =
						    centroidMap[i * stride + p] / count;
						// }
					}
				}

				// timer.stop();
			}
			// timer.stop();

			// Write all centroids to file:
			// Even disablen want dit zou raceconditions veroorzaken
			if (changed)
			{

				if (centroidDebugFile.is_open())
					centroidsDebug[r].push_back(centroids[r]);
				// centroidDebugFile.write(centroids[r], size.cols);
			}
			// Om een of andere reden moet dit er wel uit blijven en nog een keer
			// geschreven worden
			// Even disablen want dit zou racecondigtions veroorzaken.
			// TODO: Vervangen door een array met wat te schrijven?
			// clustersDebugFile.write(pointsCentroid[r], size.rows);
			if (clustersDebugFile.is_open())
				clustersDebug[r].push_back(pointsCentroid[r]);

			numSteps++;
		} while (changed);

		// std::cout << "Loop completed" << std::endl;
		// std::cout << "Best dist: " << bestDistSquaredSum
		//           << " | avgDist: " << avgDist << std::endl;
		// Deze stond eerst in de  binnenste loop waardoor ook nog eens werd
		// gekeken naar aparte iteraties in de iteraties en het eindresultaat dus
		// niet overeenkwam.

		if (avgDist < bestDistSquaredSum)
		{
			// std::cout << "Chose repetition: " << r << std::endl;

			bestDistSquaredSum = avgDist;

			bestCluster = pointsCentroid[r];
		}

		// timer.stop();

		// This shouldn't create race conditions as it accesses a different spot of
		// the vector for a repetition
		stepsPerRepetition[r] = numSteps;

		// bool changed = true;
		// while (changed) {
		//
		//
		//
		// }

		// timer2.stop();
	}

	timer.stop();

	// Hier moeten we ook nog even alles uit de nieuwe vectors halen en schrijven
	// naar de files
	for (int r = 0; r < 1; r++)
	{
		// Eerst de centroidsDebug
		for (size_t i = 0; i < centroidsDebug[r].size(); i++)
		{
			centroidDebugFile.write(centroidsDebug[r][i], size.cols);
		}

		for (size_t i = 0; i < clustersDebug[r].size(); i++)
		{
			clustersDebugFile.write(clustersDebug[r][i], size.rows);
		}
	}
	// Make sure debug logging is only done on first iteration ; subsequent
	// checks with is_open will indicate that no logging needs to be done
	// anymore.
	centroidDebugFile.close();
	clustersDebugFile.close();

	// Some example output, of course you can log your timing data anyway you
	// like.
	std::cerr << "# "
	             "Type,Submode,blocks,threads,file,seed,clusters,repetitions,"
	             "bestdistsquared,timeinseconds"
	          << std::endl;
	std::cout << "parallel," << mode << "," << numBlocks << "," << numThreads << ","
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
