# flutter_inappwebview_windows 0.6.x uses DEPENDS with add_custom_command(TARGET),
# which CMake 3.31+ flags under CMP0175. Remove the invalid keyword until upstream
# fixes it (https://github.com/pichillilorenzo/flutter_inappwebview/issues/2672).
set(_FIW_CMAKE
  "${CMAKE_CURRENT_SOURCE_DIR}/flutter/ephemeral/.plugin_symlinks/flutter_inappwebview_windows/windows/CMakeLists.txt"
)
if(EXISTS "${_FIW_CMAKE}")
  file(READ "${_FIW_CMAKE}" _fiw_cmake_content)
  if(_fiw_cmake_content MATCHES "add_custom_command\\([^)]*TARGET[^)]*DEPENDS")
    string(REPLACE "  DEPENDS \${NUGET}" "" _fiw_cmake_content "${_fiw_cmake_content}")
    file(WRITE "${_FIW_CMAKE}" "${_fiw_cmake_content}")
  endif()
  unset(_fiw_cmake_content)
endif()
unset(_FIW_CMAKE)
