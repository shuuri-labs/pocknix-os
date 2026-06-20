# Cross-toolchain for FEX's i686 (32-bit) GUEST thunk libraries.
# Ported from armada (armada-packages/fex/toolchain_x86_32.cmake), Fedora->Arch layout.
# 32-bit C++ headers live under the gcc triple's /32 subdir on both distros.
# %CPPINC% is substituted in prepare() with the real /usr/include/c++/<ver> dir.
set(CMAKE_EXE_LINKER_FLAGS_INIT "-fuse-ld=lld")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "-fuse-ld=lld")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-fuse-ld=lld -lstdc++")
set(CMAKE_C_COMPILER clang)
set(CMAKE_CXX_COMPILER clang++)
# Arch ships 32-bit libs in /usr/lib32 (Fedora used /usr/lib); clang's i686 sysroot
# search doesn't include lib32, so point it there explicitly for -lstdc++ etc.
set(CLANG_FLAGS "-nodefaultlibs -nostartfiles -target i686-linux-gnu --sysroot=${X86_DEV_ROOTFS} -L${X86_DEV_ROOTFS}/usr/lib32 -msse2 -mfpmath=sse -idirafter /usr/include")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${CLANG_FLAGS}")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${CLANG_FLAGS} -I${X86_DEV_ROOTFS}/%CPPINC%/ -I${X86_DEV_ROOTFS}/%CPPINC%/x86_64-pc-linux-gnu/32")
set(CMAKE_C_COMPILER_FORCED TRUE)
set(CMAKE_CXX_COMPILER_FORCED TRUE)
