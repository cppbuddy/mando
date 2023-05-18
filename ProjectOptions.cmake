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
  option(mando_ENABLE_HARDENING "Enable hardening" ON)
  option(mando_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    mando_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    mando_ENABLE_HARDENING
    OFF)

  mando_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR mando_PACKAGING_MAINTAINER_MODE)
    option(mando_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(mando_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(mando_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(mando_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(mando_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(mando_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(mando_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(mando_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(mando_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(mando_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(mando_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(mando_ENABLE_PCH "Enable precompiled headers" OFF)
    option(mando_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(mando_ENABLE_IPO "Enable IPO/LTO" ON)
    option(mando_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(mando_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(mando_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(mando_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(mando_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(mando_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(mando_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(mando_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(mando_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(mando_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(mando_ENABLE_PCH "Enable precompiled headers" OFF)
    option(mando_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      mando_ENABLE_IPO
      mando_WARNINGS_AS_ERRORS
      mando_ENABLE_USER_LINKER
      mando_ENABLE_SANITIZER_ADDRESS
      mando_ENABLE_SANITIZER_LEAK
      mando_ENABLE_SANITIZER_UNDEFINED
      mando_ENABLE_SANITIZER_THREAD
      mando_ENABLE_SANITIZER_MEMORY
      mando_ENABLE_UNITY_BUILD
      mando_ENABLE_CLANG_TIDY
      mando_ENABLE_CPPCHECK
      mando_ENABLE_COVERAGE
      mando_ENABLE_PCH
      mando_ENABLE_CACHE)
  endif()

  mando_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (mando_ENABLE_SANITIZER_ADDRESS OR mando_ENABLE_SANITIZER_THREAD OR mando_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(mando_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(mando_global_options)
  if(mando_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    mando_enable_ipo()
  endif()

  mando_supports_sanitizers()

  if(mando_ENABLE_HARDENING AND mando_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR mando_ENABLE_SANITIZER_UNDEFINED
       OR mando_ENABLE_SANITIZER_ADDRESS
       OR mando_ENABLE_SANITIZER_THREAD
       OR mando_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${mando_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${mando_ENABLE_SANITIZER_UNDEFINED}")
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
    ${mando_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(mando_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    configure_linker(mando_options)
  endif()

  include(cmake/Sanitizers.cmake)
  mando_enable_sanitizers(
    mando_options
    ${mando_ENABLE_SANITIZER_ADDRESS}
    ${mando_ENABLE_SANITIZER_LEAK}
    ${mando_ENABLE_SANITIZER_UNDEFINED}
    ${mando_ENABLE_SANITIZER_THREAD}
    ${mando_ENABLE_SANITIZER_MEMORY})

  set_target_properties(mando_options PROPERTIES UNITY_BUILD ${mando_ENABLE_UNITY_BUILD})

  if(mando_ENABLE_PCH)
    target_precompile_headers(
      mando_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(mando_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    mando_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(mando_ENABLE_CLANG_TIDY)
    mando_enable_clang_tidy(mando_options ${mando_WARNINGS_AS_ERRORS})
  endif()

  if(mando_ENABLE_CPPCHECK)
    mando_enable_cppcheck(${mando_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(mando_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    mando_enable_coverage(mando_options)
  endif()

  if(mando_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(mando_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(mando_ENABLE_HARDENING AND NOT mando_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR mando_ENABLE_SANITIZER_UNDEFINED
       OR mando_ENABLE_SANITIZER_ADDRESS
       OR mando_ENABLE_SANITIZER_THREAD
       OR mando_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    mando_enable_hardening(mando_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
