#  Copyright (c) 2017 John Biddiscombe
#
#  Distributed under the Boost Software License, Version 1.0. (See accompanying
#  file LICENSE_1_0.txt or copy at http://www.boost.org/LICENSE_1_0.txt)

cmake_minimum_required(VERSION 3.1 FATAL_ERROR)

#######################################################################
# For debugging this script
#######################################################################
message("Pull request is  " ${PYCICLE_PR})
message("PR-Branchname is " ${PYCICLE_BRANCH})
message("master branch is " ${PYCICLE_MASTER})
message("Machine name is  " ${PYCICLE_HOST})
message("PYCICLE_ROOT is  " ${PYCICLE_ROOT})
message("Random string is " ${PYCICLE_RANDOM})
message("COMPILER is      " ${PYCICLE_COMPILER})
message("BOOST is         " ${PYCICLE_BOOST})

# need to make this a passed in option
set(CTEST_BUILD_CONFIGURATION "Release")

#######################################################################
# Load machine specific settings
# This is where the main machine config file is read in and params set
#######################################################################
include(${CMAKE_CURRENT_LIST_DIR}/config/${PYCICLE_HOST}.cmake)

#######################################################################
# User vars that need to be set on each machine using this script
#######################################################################
set(GIT_REPO "https://github.com/STEllAR-GROUP/hpx.git")

#######################################################################
# a function that calls ctest_submit - only used to make
# debugging a bit simpler by allowing us to disable submits
#######################################################################
function(pycicle_submit)
#  if(NOT DEBUG_MODE)
    ctest_submit(${ARGN})
#  endif()
endfunction()

#######################################################################
# All the rest below here should not need changes
#######################################################################
set(PYCICLE_SRC_ROOT       "${PYCICLE_ROOT}/src")
set(PYCICLE_BUILD_ROOT     "${PYCICLE_ROOT}/build")
set(PYCICLE_LOCAL_GIT_COPY "${PYCICLE_ROOT}/repo")

file(MAKE_DIRECTORY          "${PYCICLE_SRC_ROOT}/${PYCICLE_PR}")
set(CTEST_SOURCE_DIRECTORY   "${PYCICLE_SRC_ROOT}/${PYCICLE_PR}/repo")
set(PYCICLE_BINARY_DIRECTORY "${PYCICLE_BUILD_ROOT}/${PYCICLE_PR}-${PYCICLE_BUILD_STAMP}")

if (PYCICLE_PR STREQUAL "master")
  set(CTEST_BUILD_NAME "${PYCICLE_BRANCH}-${CTEST_BUILD_CONFIGURATION}")
else()
  set(CTEST_BUILD_NAME "${PYCICLE_PR}-${PYCICLE_BRANCH}-${CTEST_BUILD_CONFIGURATION}")
endif()

#######################################################################
# Not yet implemented memcheck/coverage/etc
#######################################################################
set(WITH_MEMCHECK FALSE)
set(WITH_COVERAGE FALSE)

#######################################################################
# Wipe build dir when starting a new build
#######################################################################
#ctest_empty_binary_directory(${CTEST_BINARY_DIRECTORY})

#######################################################################
# setup git
#######################################################################
include(FindGit)
set(CTEST_GIT_COMMAND "${GIT_EXECUTABLE}")

#######################################################################
# Initial checkout if no source directory
# if repo copy local - save time by copying instead of doing a clone
#######################################################################
if(NOT PYCICLE_LOCAL_GIT_COPY)
  message(FATAL_ERROR "You must have a local clone")
endif()

#######################################################################
# First checkout, copy from a local repo to save clone of many GB's
#######################################################################
set (make_repo_copy_ "")
if (NOT EXISTS "${CTEST_SOURCE_DIRECTORY}/.git")
  set (make_repo_copy_ "cp -r ${PYCICLE_LOCAL_GIT_COPY} ${CTEST_SOURCE_DIRECTORY};")
  message("cp -r ${PYCICLE_LOCAL_GIT_COPY} ${CTEST_SOURCE_DIRECTORY};")
endif()

#####################################################################
# if this is a PR to be merged with master for testing
#####################################################################
if (NOT PYCICLE_PR STREQUAL "master")
  set(CTEST_SUBMISSION_TRACK "Pull Requests")
  set(PYCICLE_BRANCH "pull/${PYCICLE_PR}/head")
  set(GIT_BRANCH "PYCICLE_PR_${PYCICLE_PR}")
  #
  # checkout master, merge the PR into a new branch with the PR name
  # then checkout master again, then set the CTEST_UPDATE_OPTIONS
  # to fetch the merged branch so that the update step shows the
  # files that are different in the branch from master
  #
  set(WORK_DIR "${PYCICLE_SRC_ROOT}/${PYCICLE_PR}")
  execute_process(
    COMMAND bash "-c" "${make_repo_copy_}
                       cd ${CTEST_SOURCE_DIRECTORY};
                       ${CTEST_GIT_COMMAND} checkout ${PYCICLE_MASTER};
                       ${CTEST_GIT_COMMAND} fetch origin;
                       ${CTEST_GIT_COMMAND} reset --hard origin/${PYCICLE_MASTER};
                       ${CTEST_GIT_COMMAND} branch -D ${GIT_BRANCH};
                       ${CTEST_GIT_COMMAND} checkout -b ${GIT_BRANCH};
                       ${CTEST_GIT_COMMAND} fetch origin ${PYCICLE_BRANCH};
                       ${CTEST_GIT_COMMAND} merge --no-edit FETCH_HEAD;
                       ${CTEST_GIT_COMMAND} checkout ${PYCICLE_MASTER};
                       ${CTEST_GIT_COMMAND} clean -fd;"
    WORKING_DIRECTORY "${WORK_DIR}"
    OUTPUT_VARIABLE output
    ERROR_VARIABLE  output
    RESULT_VARIABLE failed
  )
  set(CTEST_UPDATE_OPTIONS "${CTEST_SOURCE_DIRECTORY} ${GIT_BRANCH}")
else()
  set(CTEST_SUBMISSION_TRACK "Master")
  set(WORK_DIR "${PYCICLE_SRC_ROOT}/master")
  execute_process(
    COMMAND bash "-c" "${make_repo_copy_}
                       cd ${CTEST_SOURCE_DIRECTORY};
                       ${CTEST_GIT_COMMAND} checkout ${PYCICLE_MASTER};
                       ${CTEST_GIT_COMMAND} fetch origin;
                       ${CTEST_GIT_COMMAND} reset --hard;"
    WORKING_DIRECTORY "${WORK_DIR}"
    OUTPUT_VARIABLE output
    ERROR_VARIABLE  output
    RESULT_VARIABLE failed
  )
  #message("Process output copy : " ${output})
endif()

#######################################################################
# Dashboard model : use Experimental unless problems arise
#######################################################################
set(CTEST_MODEL Experimental)

#######################################################################
# INSPECT : START a fake dashboard using only configure to run inspect
#######################################################################
message("Initialize dashboard : ${CTEST_MODEL} ...")
set(CTEST_BINARY_DIRECTORY "${PYCICLE_BINARY_DIRECTORY}/inspect")
ctest_start(${CTEST_MODEL}
    TRACK "Inspect"
    "${CTEST_SOURCE_DIRECTORY}"
    "${CTEST_BINARY_DIRECTORY}"
)

# configure step calls inspect instead of cmake
string(CONCAT CTEST_CONFIGURE_COMMAND
  "${PYCICLE_ROOT}/inspect/inspect ${CTEST_SOURCE_DIRECTORY}/hpx --all --text"
)

message("Running inspect...")
ctest_configure()
ctest_submit(PARTS Configure)

#######################################################################
# Erase any test complete status before starting new dashboard run
#######################################################################
set(CTEST_BINARY_DIRECTORY "${PYCICLE_BINARY_DIRECTORY}")
file(REMOVE "${CTEST_BINARY_DIRECTORY}/pycicle-TAG.txt")

#######################################################################
# START dashboard
#######################################################################
message("Initialize ${CTEST_MODEL} testing...")
ctest_start(${CTEST_MODEL}
    TRACK "${CTEST_SUBMISSION_TRACK}"
    "${CTEST_SOURCE_DIRECTORY}"
    "${CTEST_BINARY_DIRECTORY}"
)

#######################################################################
# Update dashboard
#######################################################################
message("Update source... using ${CTEST_SOURCE_DIRECTORY}")
ctest_update(RETURN_VALUE NB_CHANGED_FILES)
pycicle_submit(PARTS Update)
message("Found ${NB_CHANGED_FILES} changed file(s)")

string(CONCAT CTEST_CONFIGURE_COMMAND
  " ${CMAKE_COMMAND} -DCMAKE_BUILD_TYPE=${CTEST_BUILD_CONFIGURATION} "
  " ${CTEST_BUILD_OPTIONS}"
  " ${CTEST_CONFIGURE_COMMAND} \"-G${CTEST_CMAKE_GENERATOR}\""
  " ${CTEST_CONFIGURE_COMMAND} \"${CTEST_SOURCE_DIRECTORY}\"")

message("CTEST_CONFIGURE_COMMAND is\n${CTEST_CONFIGURE_COMMAND}")

message("Configure...")
ctest_configure()
pycicle_submit(PARTS Update Configure)

message("Build...")
set(CTEST_BUILD_FLAGS "-j ${BUILD_PARALLELISM}")
ctest_build(TARGET "tests" )
pycicle_submit(PARTS Update Configure Build)

message("Test...")
ctest_test(RETURN_VALUE test_result_ EXCLUDE "compile")
pycicle_submit(PARTS Update Configure Build Test)

if (WITH_COVERAGE AND CTEST_COVERAGE_COMMAND)
  ctest_coverage()
endif (WITH_COVERAGE AND CTEST_COVERAGE_COMMAND)
if (WITH_MEMCHECK AND CTEST_MEMORYCHECK_COMMAND)
  ctest_memcheck()
endif (WITH_MEMCHECK AND CTEST_MEMORYCHECK_COMMAND)

# Create a file when this build has finished so that pycicle can scrape the most
# recent results and use them to update the github  pull request status
# we will get the TAG from ctest and use it to find the correct XML files
# with our Configure/Build/Test errors/warnings
execute_process(
  COMMAND bash "-c"
    "TEMP=$(head -n 1 ${PYCICLE_BINARY_DIRECTORY}/Testing/TAG);
    {
    grep '<Error>' ${PYCICLE_BINARY_DIRECTORY}/Testing/$TEMP/Configure.xml | wc -l
    grep '<Error>' ${PYCICLE_BINARY_DIRECTORY}/Testing/$TEMP/Build.xml | wc -l
    grep '<Test Status=\"failed\">' ${PYCICLE_BINARY_DIRECTORY}/Testing/$TEMP/Test.xml | wc -l
    echo $TEMP
    } > ${CTEST_BINARY_DIRECTORY}/pycicle-TAG.txt"
  WORKING_DIRECTORY "${PYCICLE_BINARY_DIRECTORY}"
  OUTPUT_VARIABLE output
  ERROR_VARIABLE  output
  RESULT_VARIABLE failed
)
