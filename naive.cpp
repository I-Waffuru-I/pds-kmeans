#pragma once
#include <cmath>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <unordered_map>
#include <vector>
#include "util.cpp"

void naiveClustering(std::vector<double> &centroids,
                     std::vector<double> &allData, std::vector<int> &cPoints,
                     double &avgDist, DataSize &size, bool &changed) {
  int centroidNumber = centroids.size() / size.cols;
  // We slaan hier de begin index van elk punt op en kunnen dit aan de hand van
  // de dimentie eruit halen
  std::pmr::unordered_map<int, std::vector<double>> centroidMap;

  // We zetten ook eerst changed op false
  changed = false;
  // We gaan per dimentie hoveelheid de punten af
  double sumSquaredDist = 0;

  // AutoAverageTimer timer("inner loop");
  for (size_t i = 0; i < size.rows; ++i) {
    double minDist = std::numeric_limits<double>::max(); // can only get better
    int cIndex = size.cols + 1;
    // We moeten ook de cI traverseren per cols
    for (size_t cI = 0; cI < centroidNumber; ++cI) {
      double dist = 0;
      // Alle punten afgaan van alle dimenties
      // std::cout << "Point: ";

      for (size_t c = 0; c < size.cols; c++) {
        // std::cout << allData[c+i] << " , ";
        dist += std::pow(
            (allData[i * size.cols + c] - centroids[cI * size.cols + c]), 2);
      }

      // std::cout << "Dist to centroid: " << cI / size.cols << " Dist: " <<
      // dist << std::endl;

      // Check if is smaller than smallest distance
      if (dist < minDist) {
        minDist = dist;
        // We delen hier door het aantal dimenties om eruit te halen op welke
        // index we zitten
        cIndex = cI;

        // Som van squareddist
        avgDist += minDist / size.rows;
      }
    }

    // Voeg hier het punt aan de juiste cluster toe via de map
    // Kan ik hier eigenlijk niet al de waardes van punten optellen bij andere
    // op basis van hun dimentie En dan achteraf delen door het aantal punten
    // dat hier eigenlijk in zat? We moeten de vector dan wel een vaste grootte
    // geven van cols + 1 => de +1 voor het aantal punten mee te geven
    // centroidMap[cIndex].push_back(i);

    int pointIndex = i;
    if (cPoints[pointIndex] != cIndex) {
      changed = true;
      cPoints[pointIndex] = cIndex;
      // std::cout << "Changed point" << std::endl;
    }

    centroidMap[cIndex].resize(size.cols + 1);
    for (int c = 0; c < size.cols; c++) {
      // std::cout << allData[c+i] << " , ";
      centroidMap[cIndex][c] += allData[i * size.cols + c];
    }
    centroidMap[cIndex][size.cols] += 1;
    // std::cout << "CIndex: " << cIndex << " Distance: " << minDist <<
    // std::endl;
  }

  // AutoAverageTimer timer("centroid sum");
  // timer.start();
  for (size_t i = 0; i < centroidNumber; i++) {
    // std::cout << "Centroid " << i << ":";
    // std::cout << "Amount of points: " << centroidMap[i][size.cols] <<
    // std::endl;
    for (size_t p = 0; p < size.cols; p++) {
      // Total sum divided by total amount of points
      centroids[i * size.cols + p] =
          centroidMap[i][p] / centroidMap[i][size.cols];
    }

    // timer.stop();
  }
  // timer.stop();
}
