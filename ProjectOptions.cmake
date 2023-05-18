include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(mando_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(mando_setup_options)
  option(MANDO_ENABLE_HARDENING "Enable hardening" ON)
  option(MANDO_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    MANDO_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    MANDO_ENABLE_HARDENING
    OFF)

  mando_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR mando_PACKAGING_MAINTAINER_MODE)
    option(MANDO_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(MANDO_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(MANDO_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(MANDO_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(MANDO_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(MANDO_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(MANDO_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(MANDO_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(MANDO_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(MANDO_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(MANDO_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(MANDO_ENABLE_PCH "Enable precompiled headers" OFF)
    option(MANDO_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(MANDO_ENABLE_IPO "Enable IPO/LTO" ON)
    option(MANDO_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(MANDO_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(MANDO_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(MANDO_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(MANDO_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(MANDO_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(MANDO_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(MANDO_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(MANDO_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(MANDO_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(MANDO_ENABLE_PCH "Enable precompiled headers" OFF)
    option(MANDO_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      MANDO_ENABLE_IPO
      MANDO_WARNINGS_AS_ERRORS
      MANDO_ENABLE_USER_LINKER
      MANDO_ENABLE_SANITIZER_ADDRESS
      MANDO_ENABLE_SANITIZER_LEAK
      MANDO_ENABLE_SANITIZER_UNDEFINED
      MANDO_ENABLE_SANITIZER_THREAD
      MANDO_ENABLE_SANITIZER_MEMORY
      MANDO_ENABLE_UNITY_BUILD
      MANDO_ENABLE_CLANG_TIDY
      MANDO_ENABLE_CPPCHECK
      MANDO_ENABLE_COVERAGE
      MANDO_ENABLE_PCH
      MANDO_ENABLE_CACHE)
  endif()

  mando_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (MANDO_ENABLE_SANITIZER_ADDRESS OR MANDO_ENABLE_SANITIZER_THREAD OR MANDO_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(mando_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(mando_global_options)
  if(MANDO_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    mando_enable_ipo()
  endif()

  mando_supports_sanitizers()

  if(MANDO_ENABLE_HARDENING AND MANDO_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR MANDO_ENABLE_SANITIZER_UNDEFINED
       OR MANDO_ENABLE_SANITIZER_ADDRESS
       OR MANDO_ENABLE_SANITIZER_THREAD
       OR MANDO_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${MANDO_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${MANDO_ENABLE_SANITIZER_UNDEFINED}")
    mando_enable_hardening(mando_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(mando_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(mando_warnings INTERFACE)
  add_library(mando_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  mando_set_project_warnings(
    mando_warnings
    ${MANDO_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(MANDO_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    configure_linker(mando_options)
  endif()

  include(cmake/Sanitizers.cmake)
  mando_enable_sanitizers(
    mando_options
    ${MANDO_ENABLE_SANITIZER_ADDRESS}
    ${MANDO_ENABLE_SANITIZER_LEAK}
    ${MANDO_ENABLE_SANITIZER_UNDEFINED}
    ${MANDO_ENABLE_SANITIZER_THREAD}
    ${MANDO_ENABLE_SANITIZER_MEMORY})

  set_target_properties(mando_options PROPERTIES UNITY_BUILD ${MANDO_ENABLE_UNITY_BUILD})

  if(MANDO_ENABLE_PCH)
    target_precompile_headers(
      mando_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(MANDO_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    mando_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(MANDO_ENABLE_CLANG_TIDY)
    mando_enable_clang_tidy(mando_options ${MANDO_WARNINGS_AS_ERRORS})
  endif()

  if(MANDO_ENABLE_CPPCHECK)
    mando_enable_cppcheck(${MANDO_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(MANDO_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    mando_enable_coverage(mando_options)
  endif()

  if(MANDO_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(mando_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(MANDO_ENABLE_HARDENING AND NOT MANDO_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR MANDO_ENABLE_SANITIZER_UNDEFINED
       OR MANDO_ENABLE_SANITIZER_ADDRESS
       OR MANDO_ENABLE_SANITIZER_THREAD
       OR MANDO_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    mando_enable_hardening(mando_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
