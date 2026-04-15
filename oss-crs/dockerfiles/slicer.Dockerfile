# Directed Fuzzer Slicer
# Extends target base with LLVM tools for bitcode compilation and slicing
#
# Uses pre-built LLVM from prepare phase (oss-crs-prepared:latest)
# to avoid rebuilding LLVM for each target.

# ARG for target base image (passed by docker-compose during target build)
ARG target_base_image

# Reference the prepared image with LLVM tools
FROM oss-crs-prepared:latest AS llvm-source

# Final stage: extend target base with LLVM tools
FROM ${target_base_image}

# Install libCRS for artifact management (context passed by docker-compose)
COPY --from=libcrs . /opt/libCRS
RUN /opt/libCRS/install.sh

# Install Python dependencies for diff parsing and slicing BEFORE copying LLVM
# (use base image's clang for wheel compilation)
# - tree-sitter + tree-sitter-languages: Multi-language parser (used by diff_parser.py)
# Pin versions for API compatibility (newer versions have breaking changes)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    && pip3 install --no-cache-dir \
        tree-sitter==0.20.1 \
        tree-sitter-languages==1.7.0 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy pre-built LLVM 14 tools from prepared image (overwrites base LLVM 18)
# This is done AFTER pip install to use base clang for wheel compilation
COPY --from=llvm-source /usr/local/bin/clang* /usr/local/bin/
COPY --from=llvm-source /usr/local/bin/llvm-* /usr/local/bin/
COPY --from=llvm-source /usr/local/lib/writebc.so /usr/local/lib/
COPY --from=llvm-source /usr/local/bin/sancc /usr/local/bin/
COPY --from=llvm-source /usr/local/bin/san-clang* /usr/local/bin/
COPY --from=llvm-source /usr/local/bin/analyzer /usr/local/bin/analyzer

# Symlink clang 14's resource dir to clang 18's so built-in headers
# (stdbool.h, stddef.h etc.) and compiler-rt libs are found.
# Safe because FUZZING_ENGINE=none avoids the compile_libfuzzer glob issue.
RUN ln -sf /usr/local/lib/clang/18 /usr/local/lib/clang/14.0.6

# Copy diff_parser.py from components/directed (reused diff parsing logic)
COPY components/directed/src/daemon/modules/diff_parser.py /scripts/diff_parser.py

# Copy slicer scripts
COPY oss-crs/bin/slicer.sh /slicer.sh
COPY oss-crs/scripts/generate_allowlist.py /scripts/generate_allowlist.py
RUN chmod +x /slicer.sh

# Slicer entrypoint
CMD ["/slicer.sh"]
