cmake_minimum_required(VERSION 3.13.4)
project(KANALYZER)

SET(CMAKE_FIND_LIBRARY_SUFFIXES ".a")

# LLVM 18 cmake config expects zstd::libzstd_shared target
# Create an alias if zstd was found but target doesn't exist
find_package(zstd QUIET)
if(NOT TARGET zstd::libzstd_shared)
    find_library(ZSTD_LIBRARY NAMES zstd libzstd)
    if(ZSTD_LIBRARY)
        add_library(zstd::libzstd_shared UNKNOWN IMPORTED)
        set_target_properties(zstd::libzstd_shared PROPERTIES
            IMPORTED_LOCATION "${ZSTD_LIBRARY}")
    endif()
endif()

find_package(LLVM REQUIRED CONFIG)

# set(ZLIB_USE_STATIC_LIBS "ON")

message("suffix: ${CMAKE_FIND_LIBRARY_SUFFIXES}")
message(STATUS "Found LLVM ${LLVM_PACKAGE_VERSION}")
message(STATUS "Using LLVMConfig.cmake in: ${LLVM_DIR}")

# LLVM 18 requires C++17
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
# Use libstdc++ to match LLVM static libraries (built with GCC)
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fno-rtti -fPIC -Wall -stdlib=libstdc++")
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -stdlib=libstdc++")

include_directories(${LLVM_INCLUDE_DIRS})
add_definitions(${LLVM_DEFINITIONS})

add_subdirectory (lib)
