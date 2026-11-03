#include "centroids.hpp"
#include "globals.hpp"
#include <iostream>

void initCentroids(Rng &rng, std::vector<double> &centroids,
                   std::vector<double> &allData, DataSize &dsize)
{
	size_t ccount = centroids.size() / dsize.cols;
	std::vector<size_t> centroid_indices(ccount);

	if (PRINT_DEBUG)
	{
		std::cout << "size: " << dsize.rows << ", " << dsize.cols << std::endl;
		std::cout << "cluster count: " << ccount << std::endl;
	}

	rng.pickRandomIndices(dsize.rows, centroid_indices);
	for (int i = 0; i < ccount; i++)
	{
		size_t row = centroid_indices[i];
		for (int e = 0; e < dsize.cols; e++)
		{
			centroids[i * dsize.cols + e] = allData[row * dsize.cols + e];
		}
	}
}

void debugCentroids(std::vector<double> &centroids, DataSize &size)
{
	std::cout << "debug centroid: " << std::endl;
	for (int r = 0; r < centroids.size() / size.cols; r++)
	{
		for (int c = 0; c < size.cols; c++)
		{
			std::cout << centroids[r * size.cols + c] << ", ";
		}
		std::cout << std::endl;
	}
}

void debugCentroidPoints(std::vector<int> &pCentroid)
{
	std::cout << "Debug centroid points" << std::endl;
	for (int r = 0; r < pCentroid.size(); r++)
	{
		std::cout << pCentroid[r] << ",";
	}
	std::cout << std::endl;
}
