# Prepare Phase: Target + LLVM
# Creates a shared base image with LLVM 14.0.6 pre-installed
#
# Build stages:
# 1. llvm-builder: Compiles LLVM 14.0.6 with static analyzer and bitcode tools
# 2. Final: Extends target base image with LLVM binaries
#
# Note: libCRS is installed during target_build_phase via docker-compose,
# not during the prepare phase.

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

# Stage 2: Extend target base with LLVM
FROM ${target_base_image}

# Copy pre-built LLVM tools from builder stage
COPY --from=llvm-builder /usr/local/bin/clang* /usr/local/bin/
COPY --from=llvm-builder /usr/local/bin/llvm-* /usr/local/bin/
COPY --from=llvm-builder /usr/local/lib/writebc.so /usr/local/lib/
COPY --from=llvm-builder /usr/local/bin/sancc /usr/local/bin/
COPY --from=llvm-builder /usr/local/bin/san-clang* /usr/local/bin/
COPY --from=llvm-builder /build/analyzer/build/lib/analyzer /usr/local/bin/analyzer

# Symlink clang 14's expected lib path to base image's clang 18 libs
# This allows clang 14 binaries to find compiler-rt (ASan, UBSan, libFuzzer, etc.)
# Note: Base image has libs at /usr/local/lib/clang/18/lib/x86_64-unknown-linux-gnu/
RUN ln -sf /usr/local/lib/clang/18 /usr/local/lib/clang/14.0.6
