#include "naive.hpp"
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
                     double &avgDist, DataSize &size, bool &changed)
{
	int centroidNumber = centroids.size() / size.cols;
	// We slaan hier de begin index van elk punt op en kunnen dit aan de hand van
	// de dimentie eruit halen
	// std::pmr::unordered_map<int, std::vector<double>> centroidMap;
	std::vector<std::vector<double>> centroidMap(
	    centroids.size() / size.cols, std::vector<double>(size.cols + 1));

	// We zetten ook eerst changed op false
	changed = false;
	// We gaan per dimentie hoveelheid de punten af

	// AutoAverageTimer timer("main inner loop");

	// AutoAverageTimer timerPoints("assign points to centroid");
	//
	// AutoAverageTimer distTimer("Calculate dist to centroid");
	// timer.start();
	for (size_t i = 0; i < size.rows; ++i)
	{
		double minDist = std::numeric_limits<double>::max(); // can only get better
		int cIndex = size.cols + 1;
		// We moeten ook de cI traverseren per cols

		// timerPoints.start();
		for (size_t cI = 0; cI < centroidNumber; ++cI)
		{
			double dist = 0;
			// Alle punten afgaan van alle dimenties
			// std::cout << "Point: ";

			// distTimer.start();
			for (size_t c = 0; c < size.cols; c++)
			{
				// std::cout << allData[c+i] << " , ";
				double diff = allData[i * size.cols + c] - centroids[cI * size.cols + c];

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
		// Som van squareddist
		// We veranderen de deling  aangezien deze vrij traag is door een optelling en zullen later pas delen door size.rows
		// avgDist += minDist / size.rows;
		avgDist += minDist;

		// Voeg hier het punt aan de juiste cluster toe via de map
		// Kan ik hier eigenlijk niet al de waardes van punten optellen bij andere
		// op basis van hun dimentie En dan achteraf delen door het aantal punten
		// dat hier eigenlijk in zat? We moeten de vector dan wel een vaste grootte
		// geven van cols + 1 => de +1 voor het aantal punten mee te geven
		// centroidMap[cIndex].push_back(i);

		int pointIndex = i;
		if (cPoints[pointIndex] != cIndex)
		{
			changed = true;
			cPoints[pointIndex] = cIndex;
			// std::cout << "Changed point" << std::endl;
		}

		// centroidMap[cIndex].resize(size.cols + 1);
		for (size_t c = 0; c < size.cols; c++)
		{
			// std::cout << allData[c+i] << " , ";
			centroidMap[cIndex][c] += allData[i * size.cols + c];
		}
		centroidMap[cIndex][size.cols] += 1;
		// std::cout << "CIndex: " << cIndex << " Distance: " << minDist <<
		// std::endl;
	}

	avgDist = avgDist / size.rows;

	// distTimer.stop();
	// timerPoints.stop();
	// timer.stop();

	// AutoAverageTimer timer2("centroid sum");
	// timer2.start();
	for (size_t i = 0; i < centroidNumber; i++)
	{
		// std::cout << "Centroid " << i << ":";
		// std::cout << "Amount of points: " << centroidMap[i][size.cols] <<
		// std::endl;
		for (size_t p = 0; p < size.cols; p++)
		{
			// Total sum divided by total amount of points
			if (centroidMap[i][size.cols] != 0)
			{
				centroids[i * size.cols + p] =
				    centroidMap[i][p] / centroidMap[i][size.cols];
			}
		}

		// timer.stop();
	}
	// timer2.stop();
}

// Voor OMP
void naiveOMPClustering(std::vector<double> &centroids,
                        std::vector<double> &allData, std::vector<int> &cPoints, std::vector<double> &localCentroidMap,
                        double &avgDist, DataSize &size, bool &changed)
{

	int centroidNumber = centroids.size() / size.cols;
// THREADS moeten niet wachten voordat ze mergen dus dat kan al worden meegegegeven
#pragma omp for nowait reduction(+ : avgDist) reduction(|| : changed)
	for (size_t ii = 0; ii < size.rows; ++ii)
	{
		double minDist =
		    std::numeric_limits<double>::max(); // can only get better
		int cIndex = size.cols + 1;

		double partTime;
		// We moeten ook de cI traverseren per cols

		for (int cI = 0; cI < centroidNumber; ++cI)
		{
			double dist = 0;
			// Alle punten afgaan van alle dimenties
			// std::cout << "Point: ";

			for (size_t c = 0; c < size.cols; c++)
			{
				double diff = allData[ii * size.cols + c] - centroids[cI * size.cols + c];

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
		if (cPoints[pointIndex] != cIndex)
		{
			changed = true;

			cPoints[pointIndex] = cIndex;
			// std::cout << "Changed point" << std::endl;
		}

		// centroidMap[cIndex].reserve(size.cols);
		for (size_t c = 0; c < size.cols; c++)
		{
			// std::cout << allData[c+i] << " , ";
			localCentroidMap[cIndex * size.cols + c] += allData[ii * size.cols + c];
		}
		localCentroidMap[cIndex * size.cols + size.cols] += 1;

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
}

void naiveBaseOMPClustering(std::vector<double> &centroids,
                            std::vector<double> &allData, std::vector<int> &cPoints,
                            double &avgDist, DataSize &size, bool &changed, int numThreads)
{
	int centroidNumber = centroids.size() / size.cols;
	// We slaan hier de begin index van elk punt op en kunnen dit aan de hand van
	// de dimentie eruit halen
	// std::pmr::unordered_map<int, std::vector<double>> centroidMap;
	std::vector<std::vector<double>> centroidMap(
	    centroids.size() / size.cols, std::vector<double>(size.cols + 1));

	// We zetten ook eerst changed op false
	changed = false;
	// We gaan per dimentie hoveelheid de punten af

	// AutoAverageTimer timer("main inner loop");

	// AutoAverageTimer timerPoints("assign points to centroid");
	//
	// AutoAverageTimer distTimer("Calculate dist to centroid");
	// timer.start();
#pragma omp parallel for schedule(guided) reduction(+ : avgDist) reduction(|| : changed)
	for (size_t i = 0; i < size.rows; ++i)
	{
		double minDist = std::numeric_limits<double>::max(); // can only get better
		int cIndex = size.cols + 1;
		// We moeten ook de cI traverseren per cols

		// timerPoints.start();
		for (size_t cI = 0; cI < centroidNumber; ++cI)
		{
			double dist = 0;
			// Alle punten afgaan van alle dimenties
			// std::cout << "Point: ";

			// distTimer.start();
			for (size_t c = 0; c < size.cols; c++)
			{
				// std::cout << allData[c+i] << " , ";
				double diff = allData[i * size.cols + c] - centroids[cI * size.cols + c];

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
		// Som van squareddist
		// We veranderen de deling  aangezien deze vrij traag is door een optelling en zullen later pas delen door size.rows
		// avgDist += minDist / size.rows;
		avgDist += minDist;

		// Voeg hier het punt aan de juiste cluster toe via de map
		// Kan ik hier eigenlijk niet al de waardes van punten optellen bij andere
		// op basis van hun dimentie En dan achteraf delen door het aantal punten
		// dat hier eigenlijk in zat? We moeten de vector dan wel een vaste grootte
		// geven van cols + 1 => de +1 voor het aantal punten mee te geven
		// centroidMap[cIndex].push_back(i);

		int pointIndex = i;
		if (cPoints[pointIndex] != cIndex)
		{
			changed = true;
			cPoints[pointIndex] = cIndex;
			// std::cout << "Changed point" << std::endl;
		}

#pragma omp critical
		{
			for (int c = 0; c < size.cols; c++)
			{
				// std::cout << allData[c+i] << " , ";
				centroidMap[cIndex][c] += allData[i * size.cols + c];
			}
			centroidMap[cIndex][size.cols] += 1;
		}
		// std::cout << "CIndex: " << cIndex << " Distance: " << minDist <<
		// std::endl;
	}

	avgDist = avgDist / size.rows;

	// distTimer.stop();
	// timerPoints.stop();
	// timer.stop();

	// AutoAverageTimer timer2("centroid sum");
	// timer2.start();
	for (size_t i = 0; i < centroidNumber; i++)
	{
		// std::cout << "Centroid " << i << ":";
		// std::cout << "Amount of points: " << centroidMap[i][size.cols] <<
		// std::endl;
		for (size_t p = 0; p < size.cols; p++)
		{
			// Total sum divided by total amount of points
			if (centroidMap[i][size.cols] != 0)
			{
				centroids[i * size.cols + p] =
				    centroidMap[i][p] / centroidMap[i][size.cols];
			}
		}

		// timer.stop();
	}
	// timer2.stop();
}
