# Prepare Phase: Target + LLVM 14
# Creates a shared base image with a complete LLVM 14.0.6 toolchain
#
# Build stages:
# 1. llvm-builder: Compiles LLVM 14.0.6 with static analyzer, writebc, and san-clang
# 2. Final: Extends target base image with complete LLVM 14 (clang, compiler-rt, headers)
#
# This mirrors the original 42-afc-crs base-clang → base-builder chain.

# Global ARG - must be declared before any FROM to use in FROM instruction
ARG target_base_image=ghcr.io/aixcc-finals/base-builder:v1.3.0

# Stage 1: Build LLVM tools (cached across targets)
# Use ubuntu:20.04 (focal) to match base-builder's glibc 2.31
FROM ubuntu:20.04 AS llvm-builder

# Prevent apt from prompting for timezone/locale config
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    ninja-build \
    git \
    python3 \
    libssl-dev \
    zlib1g-dev \
    curl \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Clone fuzz-introspector (required by checkout_build_install_llvm.sh)
RUN git clone https://github.com/ossf/fuzz-introspector.git /fuzz-introspector && \
    cd /fuzz-introspector && \
    git checkout f9bcb8824a18d60d57e2430c5b43f525d811cae8 && \
    git submodule init && \
    git submodule update && \
    rm -rf .git

# Copy LLVM build script and source from components
COPY components/slice/oss-fuzz-aixcc/infra/base-images/base-clang/checkout_build_install_llvm.sh /build/
COPY components/slice/oss-fuzz-aixcc/infra/base-images/base-clang/analyzer /build/analyzer
COPY components/slice/oss-fuzz-aixcc/infra/base-images/base-clang/klaus /build/klaus

# Set up environment variables expected by the build script
ENV SRC=/build
ENV WORK=/work

WORKDIR /build
RUN chmod +x checkout_build_install_llvm.sh && ./checkout_build_install_llvm.sh

# Stage 2: Extend target base with complete LLVM 14
FROM ${target_base_image}

# Copy complete LLVM 14 toolchain from builder stage
# This overwrites the base image's clang 18, giving us a native LLVM 14 environment
# with matching compiler-rt (ASan, fuzzer, etc.), headers (stdbool.h), and libs
COPY --from=llvm-builder /usr/local/bin/clang* /usr/local/bin/
COPY --from=llvm-builder /usr/local/bin/llvm-* /usr/local/bin/
COPY --from=llvm-builder /usr/local/bin/sancc /usr/local/bin/
COPY --from=llvm-builder /usr/local/bin/san-clang* /usr/local/bin/
COPY --from=llvm-builder /usr/local/lib/writebc.so /usr/local/lib/
COPY --from=llvm-builder /build/analyzer/build/lib/analyzer /usr/local/bin/analyzer

# Copy LLVM 14 runtime: compiler-rt, headers, fuzzer libs
# This is the key difference from before - we copy the COMPLETE runtime
COPY --from=llvm-builder /usr/local/lib/clang/14.0.6/ /usr/local/lib/clang/14.0.6/

# Note: libc++ headers/libs are kept from the base image (clang 18).
# The key LLVM 14 components are: clang binary, compiler-rt, writebc, san-clang, analyzer.
