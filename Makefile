# Compiler and flags
CXX := g++
CXXFLAGS := -std=c++17 -Wall -Wextra -O3 -DNDEBUG -march=native -mtune=native -MMD -MP
INCLUDES := -Iinclude -Ilibs
LDFLAGS :=
EXTRAFLAGS :=

# Directories
SRC_DIRS := src libs
BUILD_DIR := build
BIN_DIR := $(BUILD_DIR)/bin
SERIAL_DIR := $(BUILD_DIR)/serial
OMP_DIR := $(BUILD_DIR)/omp

# Executable targets
SERIAL_TARGET := $(BIN_DIR)/kmeans_serial
OMP_TARGET := $(BIN_DIR)/kmeans_omp

DATA := datasets
OUTPUT := output

ARGS ?= --input $(DATA)/100000x5.csv \
	--output $(OUTPUT)/output.csv \
	--repetitions 20 --k 10 \
	--seed 1337

# Find all .cpp files in src/ and libs/
SRCS := $(wildcard src/*.cpp libs/*.cpp)
SERIAL_OBJS := $(patsubst %.cpp,$(SERIAL_DIR)/%.o,$(notdir $(SRCS)))
OMP_OBJS := $(patsubst %.cpp,$(OMP_DIR)/%.o,$(notdir $(SRCS)))
DEPS := $(SERIAL_OBJS:.o=.d) $(OMP_OBJS:.o=.d)

# Tell Make where to search for .cpp files
vpath %.cpp $(SRC_DIRS)

# Default rule: build both serial and OpenMP executables
all: serial omp

serial: $(SERIAL_TARGET)

omp: $(OMP_TARGET)

kmeans_serial: $(SERIAL_TARGET)

kmeans_omp: $(OMP_TARGET)

# Link serial executable
$(SERIAL_TARGET): $(SERIAL_OBJS) | $(BIN_DIR)
	$(CXX) $(SERIAL_OBJS) -o $@ $(LDFLAGS)

# Link OpenMP executable
$(OMP_TARGET): $(OMP_OBJS) | $(BIN_DIR)
	$(CXX) $(OMP_OBJS) -o $@ $(LDFLAGS) -fopenmp

# Compile serial objects
$(SERIAL_DIR)/%.o: %.cpp | $(SERIAL_DIR)
	$(CXX) $(CXXFLAGS) $(INCLUDES) -c $< -o $@

# Compile OpenMP objects
$(OMP_DIR)/%.o: %.cpp | $(OMP_DIR)
	$(CXX) $(CXXFLAGS) -fopenmp -DHAVE_OMP $(INCLUDES) -c $< -o $@

# Create directories if they do not exist
$(BIN_DIR) $(SERIAL_DIR) $(OMP_DIR):
	mkdir -p $@

# Run rules
run: run-serial

run-serial: $(SERIAL_TARGET)
	./$(SERIAL_TARGET) $(ARGS) $(EXTRAFLAGS)

run-omp: $(OMP_TARGET)
	./$(OMP_TARGET) $(ARGS) $(EXTRAFLAGS)

# Run with debug trace options
debug: debug-omp

debug-serial: $(SERIAL_TARGET)
	./$(SERIAL_TARGET) $(EXTRAFLAGS) --input $(DATA)/mouse_500x2.csv \
		--output $(OUTPUT)/output.csv \
		--repetitions 10 --k 3 \
		--centroidtrace $(OUTPUT)/centroidtrace.csv \
		--trace $(OUTPUT)/clustertrace.csv --seed 1338

debug-omp: $(OMP_TARGET)
	./$(OMP_TARGET) $(EXTRAFLAGS) --input $(DATA)/mouse_500x2.csv \
		--output $(OUTPUT)/output.csv \
		--repetitions 10 --k 3 \
		--centroidtrace $(OUTPUT)/centroidtrace.csv \
		--trace $(OUTPUT)/clustertrace.csv --seed 1338

# Remove build artifacts
clean:
	rm -rf $(BUILD_DIR) kmeans

# Include automatically generated header dependency files
-include $(DEPS)

.PHONY: all serial omp kmeans_serial kmeans_omp run run-serial run-omp debug debug-serial debug-omp clean
