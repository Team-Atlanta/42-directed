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

# Copy pre-built LLVM tools from prepared image
COPY --from=llvm-source /usr/local/bin/clang* /usr/local/bin/
COPY --from=llvm-source /usr/local/bin/llvm-* /usr/local/bin/
COPY --from=llvm-source /usr/local/lib/writebc.so /usr/local/lib/
COPY --from=llvm-source /usr/local/bin/sancc /usr/local/bin/
COPY --from=llvm-source /usr/local/bin/san-clang* /usr/local/bin/
COPY --from=llvm-source /usr/local/bin/analyzer /usr/local/bin/analyzer

# Install libCRS for artifact management (context passed by docker-compose)
COPY --from=libcrs . /opt/libCRS
RUN /opt/libCRS/install.sh

# Install Python dependencies for diff parsing and slicing
# - tree-sitter-languages: Multi-language tree-sitter parser (used by diff_parser.py)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    && pip3 install --no-cache-dir \
        tree-sitter-languages \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy slice.py from components/slice (proven LLVM analyzer invocation)
COPY components/slice/slice.py /scripts/slice.py

# Copy diff_parser.py from components/directed (reused diff parsing logic)
COPY components/directed/src/daemon/modules/diff_parser.py /scripts/diff_parser.py

# Copy slicer scripts
COPY oss-crs/bin/slicer.sh /slicer.sh
COPY oss-crs/scripts/generate_allowlist.py /scripts/generate_allowlist.py
RUN chmod +x /slicer.sh

# Slicer entrypoint
CMD ["/slicer.sh"]
