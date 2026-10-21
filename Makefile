# -std=c++14: we're limiting ourselves to c++14, since that's what the 
#             GCC compiler on the VSC supports.
# -DNDEBUG: turns off e.g. assertion checks
# -O3: enables optimizations in the compiler

# Settings for optimized build
FLAGS=-O3 -DNDEBUG -std=c++17

# Settings for a debug build
#FLAGS=-g -std=c++14

BUILD = kmeans
DATA = datasets
OUTPUT = output

all: build

clean:
	rm -f $(BUILD)
	rm -fr $(OUTPUT)

build: main_startcode.cpp rng.cpp
	$(CXX) $(FLAGS) -o $(BUILD) main_startcode.cpp rng.cpp

run: build
	./$(BUILD) --input $(DATA)/mouse_500x2.csv \
		--output $(OUTPUT)/output.csv \
		--repetitions 4   --k 3 \
		--seed 2507953

debug: build
	./$(BUILD) --input $(DATA)/mouse_500x2.csv \
		--output $(OUTPUT)/output.csv \
		--repetitions 4   --k 3 \
		--centroidtrace $(OUTPUT)/centroidtrace.csv \
		--trace $(OUTPUT)/clustertrace.csv --seed 2507953

