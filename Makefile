# Compiler and flags
CXX := g++
CXXFLAGS := -std=c++17 -Wall -Wextra -O3 -DNDEBUG -march=native -mtune=native -MMD -MP
INCLUDES := -Iinclude -Ilibs
LDFLAGS :=
EXTRAFLAGS :=

# Directories and target executable
SRC_DIRS := src libs
BUILD_DIR := build
TARGET := kmeans
DATA := datasets
OUTPUT := output

ARGS ?= --input $(DATA)/100000x5.csv \
	--output $(OUTPUT)/output.csv \
	--repetitions 20 --k 10 \
	--seed 1337

# Find all .cpp files in src/ and libs/
SRCS := $(wildcard src/*.cpp libs/*.cpp)
OBJS := $(patsubst %.cpp,$(BUILD_DIR)/%.o,$(notdir $(SRCS)))
DEPS := $(OBJS:.o=.d)

# Tell Make where to search for .cpp files
vpath %.cpp $(SRC_DIRS)

# Default rule: build the executable
all: $(TARGET)

# Link object files to create the final executable
$(TARGET): $(OBJS)
	$(CXX) $(OBJS) -o $(TARGET) $(LDFLAGS)

# Compile each .cpp file into build/*.o
$(BUILD_DIR)/%.o: %.cpp | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(INCLUDES)  -c $< -o $@

# Create build directory if it does not exist
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Enable OpenMP support
omp: CXXFLAGS += -fopenmp -DHAVE_OMP
omp: LDFLAGS += -fopenmp
omp: $(TARGET)

# Custom rule to compile and run with arguments
run: $(TARGET)
	./$(TARGET) $(ARGS) $(EXTRAFLAGS)

# Run with debug trace options
debug: $(TARGET)
	./$(TARGET) $(EXTRAFLAGS) --input $(DATA)/mouse_500x2.csv \
		--output $(OUTPUT)/output.csv \
		--repetitions 10 --k 3 \
		--centroidtrace $(OUTPUT)/centroidtrace.csv \
		--trace $(OUTPUT)/clustertrace.csv --seed 1338

# Remove build artifacts
clean:
	rm -rf $(BUILD_DIR) $(TARGET)

# Include automatically generated header dependency files
-include $(DEPS)

.PHONY: all omp run debug clean
