# Stage 1: Build LLVM tools (cached across targets)
# This stage compiles LLVM 14.0.6 with static analyzer and bitcode tools
FROM ubuntu:22.04 AS llvm-builder

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

# Copy LLVM build script and source from components
COPY components/slice/oss-fuzz-aixcc/infra/base-images/base-clang/checkout_build_install_llvm.sh /build/
COPY components/slice/oss-fuzz-aixcc/infra/base-images/base-clang/analyzer /build/analyzer
COPY components/slice/oss-fuzz-aixcc/infra/base-images/base-clang/klaus /build/klaus

WORKDIR /build
RUN chmod +x checkout_build_install_llvm.sh && ./checkout_build_install_llvm.sh

# Stage 2: Slicer runtime
# Extends target base image with LLVM tools for bitcode compilation and slicing
ARG target_base_image
FROM ${target_base_image}

# Copy pre-built LLVM tools from builder stage
COPY --from=llvm-builder /usr/local/bin/clang* /usr/local/bin/
COPY --from=llvm-builder /usr/local/bin/llvm-* /usr/local/bin/
COPY --from=llvm-builder /usr/local/lib/writebc.so /usr/local/lib/
COPY --from=llvm-builder /usr/local/bin/sancc /usr/local/bin/
COPY --from=llvm-builder /usr/local/bin/san-clang* /usr/local/bin/
COPY --from=llvm-builder /build/analyzer/build/lib/analyzer /usr/local/bin/analyzer

# Install libCRS for artifact management
COPY --from=libcrs . /opt/libCRS
RUN /opt/libCRS/install.sh

# Install Python dependencies for diff parsing and slicing
# - tree-sitter: AST parsing to identify function boundaries
# - tree-sitter-c: C language grammar for tree-sitter
# - unidiff: Parse unified diff files
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    && pip3 install --no-cache-dir \
        tree-sitter \
        tree-sitter-c \
        unidiff \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy slicer scripts
COPY oss-crs/bin/slicer.sh /slicer.sh
COPY oss-crs/scripts/parse_diff.py /scripts/parse_diff.py
COPY oss-crs/scripts/generate_allowlist.py /scripts/generate_allowlist.py
RUN chmod +x /slicer.sh

# Slicer entrypoint
CMD ["/slicer.sh"]
