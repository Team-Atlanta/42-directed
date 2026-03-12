# Global ARG for target base image (must be before first FROM)
ARG target_base_image

# Stage 1: Build custom components using target's LLVM
FROM ${target_base_image} AS component-builder

ENV SRC=/src
ENV WORK=/work
ENV DEBIAN_FRONTEND=noninteractive
RUN mkdir -p $SRC $WORK

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build git python3 \
    libssl-dev zlib1g-dev libzstd-dev curl ca-certificates llvm-18-dev \
    libstdc++-10-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy and build analyzer
COPY components/slice/oss-fuzz-aixcc/infra/base-images/base-clang/analyzer /src/analyzer
WORKDIR /src/analyzer
RUN mkdir -p build && cd build && \
    cmake -DLLVM_DIR=/usr/lib/llvm-18/lib/cmake/llvm \
          -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_EXE_LINKER_FLAGS="-L/usr/lib/x86_64-linux-gnu -lz" \
          -DZLIB_LIBRARY_RELEASE=/usr/lib/x86_64-linux-gnu/libz.a \
          -DZLIB_INCLUDE_DIR=/usr/include \
          ../src && \
    make -j$(nproc)

# Copy and build writebc.so - ABI fix v1.0-noop
# IMPORTANT: Must use base image's llvm-config (/usr/local/bin) not system llvm-18-dev
# to match the ABI of the clang binary that will load the plugin
COPY components/slice/oss-fuzz-aixcc/infra/base-images/base-clang/klaus /src/klaus
WORKDIR /src/klaus/llvm_bitcode_writer
RUN LLVM_CONFIG=/usr/local/bin/llvm-config make -j$(nproc)

# Copy and build compiler wrappers
WORKDIR /src/klaus/compiler_wrapper
RUN ./build.sh

# Stage 2: Slicer runtime
FROM ${target_base_image}

# Copy built components from builder stage
COPY --from=component-builder /src/analyzer/build/lib/analyzer /usr/local/bin/analyzer
COPY --from=component-builder /src/klaus/llvm_bitcode_writer/writebc.so /usr/local/lib/
COPY --from=component-builder /src/klaus/compiler_wrapper/sancc /usr/local/bin/
COPY --from=component-builder /src/klaus/compiler_wrapper/san-clang /usr/local/bin/
COPY --from=component-builder /src/klaus/compiler_wrapper/san-clang++ /usr/local/bin/
COPY --from=component-builder /src/klaus/compiler_wrapper/san-gcc /usr/local/bin/
COPY --from=component-builder /src/klaus/compiler_wrapper/san-g++ /usr/local/bin/

COPY --from=libcrs . /opt/libCRS
RUN /opt/libCRS/install.sh

RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-pip \
    && pip3 install --no-cache-dir 'tree-sitter==0.21.3' 'tree-sitter-languages==1.10.2' \
    && rm -rf /var/lib/apt/lists/*

COPY components/slice/slice.py /scripts/slice.py
COPY components/directed/src/daemon/modules/diff_parser.py /scripts/diff_parser.py
COPY oss-crs/bin/slicer.sh /slicer.sh
COPY oss-crs/scripts/generate_allowlist.py /scripts/generate_allowlist.py
RUN chmod +x /slicer.sh

CMD ["/slicer.sh"]
