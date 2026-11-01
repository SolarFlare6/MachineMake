cmake_minimum_required(VERSION 3.18.1)
project(needle_bridge LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(
    needle_bridge
    SHARED
    needle_bridge.cpp
)

target_include_directories(
    needle_bridge
    PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)

find_library(log-lib log)

if(ANDROID_ABI STREQUAL "arm64-v8a" OR ANDROID_ABI STREQUAL "armeabi-v7a" OR ANDROID_ABI STREQUAL "x86_64")
    add_library(needle_static STATIC IMPORTED)
    set_target_properties(
        needle_static
        PROPERTIES
        IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/${ANDROID_ABI}/libneedle.a"
    )
    target_link_libraries(
        needle_bridge
        needle_static
        ${log-lib}
        m
        dl
    )
else()
    target_link_libraries(
        needle_bridge
        ${log-lib}
        m
    )
endif()
