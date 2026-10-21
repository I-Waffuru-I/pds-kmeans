#!/bin/bash -l
#SBATCH --cluster=wice
#SBATCH --account=llp_h_pds
#SBATCH --error="data/%x.e%A"
#SBATCH --output="data/%x.o%A"
#
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#
#SBATCH --job-name=kmeans_serial_mv_nb
#SBATCH --time=00:5:00
#

# My own code, remove if it causes problems
# (do not change 'vsc30380')

source /data/leuven/303/vsc30380/slurmhooks


module purge
module load GCC/14.3.0

echo ""


g++ -O3 -DNDEBUG -std=c++17 -o kmeans main_startcode.cpp rng.cpp

./kmeans --input datasets/mouse_500x2.csv \
		--output output/mouse_500x2_3.csv \
		--repetitions 4   --k 3 \
		--seed 2507953

./kmeans --input datasets/simple1_5000x2.csv \
		--output output/simple1_5000x2_3.csv \
		--repetitions 5   --k 3 \
		--seed 2507953

./kmeans --input datasets/simple1_5000x2.csv \
		--output output/simple1_5000x2_4.csv \
		--repetitions 5   --k 4 \
		--seed 2507953

./kmeans --input datasets/simple1_5000x2.csv \
		--output output/simple1_5000x2_5.csv \
		--repetitions 5   --k 5 \
		--seed 2507953
