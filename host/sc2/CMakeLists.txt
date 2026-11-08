cmake_minimum_required(VERSION 3.16)
project(fpga_sc2_smoke LANGUAGES C CXX)

set(SC2_API_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../third_party/s2client-api")
if(NOT EXISTS "${SC2_API_ROOT}/protocol/s2clientprotocol/sc2api.proto")
    message(FATAL_ERROR "Initialize the SDK: git submodule update --init --recursive")
endif()

set(BUILD_API_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BUILD_API_TESTS OFF CACHE BOOL "" FORCE)
# EXCLUDE_FROM_ALL keeps unrelated examples, renderer and SDL out of this build.
add_subdirectory("${SC2_API_ROOT}" "${CMAKE_CURRENT_BINARY_DIR}/sdk" EXCLUDE_FROM_ALL)
add_executable(sc2_smoke smoke.cc)
set_target_properties(sc2_smoke PROPERTIES
    CXX_STANDARD 14 CXX_STANDARD_REQUIRED YES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
target_include_directories(sc2_smoke PRIVATE
    "${SC2_API_ROOT}/include" "${CMAKE_CURRENT_BINARY_DIR}/sdk/generated")
target_link_libraries(sc2_smoke PRIVATE sc2api sc2utils)
