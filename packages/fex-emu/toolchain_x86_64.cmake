# Cross-toolchain for FEX's x86_64 GUEST thunk libraries (ThunkLibs/GuestLibs).
# Ported from armada (armada-packages/fex/toolchain_x86_64.cmake), adapted from
# Fedora's gcc layout (x86_64-redhat-linux) to Arch's (x86_64-pc-linux-gnu).
#
# clang is an inherent cross-compiler: -target x86_64-linux-gnu + --sysroot at the
# x86 dev sysroot (pinned Arch x86_64 packages, assembled in PKGBUILD prepare())
# is all that's needed — no nix, no separate x86 GCC. This is what unblocks thunks
# on Arch (the AUR/ALARM packages lack them precisely because they never wired this).
#
# %CPPINC% is substituted in prepare() with the real /usr/include/c++/<ver> dir.
set(CMAKE_EXE_LINKER_FLAGS_INIT "-fuse-ld=lld")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "-fuse-ld=lld")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "-fuse-ld=lld -lstdc++")
set(CMAKE_C_COMPILER clang)
set(CMAKE_CXX_COMPILER clang++)
set(CLANG_FLAGS "-nodefaultlibs -nostartfiles -target x86_64-linux-gnu --sysroot=${X86_DEV_ROOTFS} -idirafter /usr/include")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${CLANG_FLAGS}")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${CLANG_FLAGS} -I${X86_DEV_ROOTFS}/%CPPINC%/ -I${X86_DEV_ROOTFS}/%CPPINC%/x86_64-pc-linux-gnu")
set(CMAKE_C_COMPILER_FORCED TRUE)
set(CMAKE_CXX_COMPILER_FORCED TRUE)
