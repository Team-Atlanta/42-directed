# Directed Fuzzer Slicer
# Extends target base with complete LLVM 14 for bitcode compilation and slicing
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
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    && pip3 install --no-cache-dir \
        tree-sitter==0.20.1 \
        tree-sitter-languages==1.7.0 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy complete LLVM 14 from prepared image (overwrites base LLVM 18)
# This is done AFTER pip install to use base clang for wheel compilation
COPY --from=llvm-source /usr/local/bin/clang* /usr/local/bin/
COPY --from=llvm-source /usr/local/bin/llvm-* /usr/local/bin/
COPY --from=llvm-source /usr/local/lib/writebc.so /usr/local/lib/
COPY --from=llvm-source /usr/local/bin/sancc /usr/local/bin/
COPY --from=llvm-source /usr/local/bin/san-clang* /usr/local/bin/
COPY --from=llvm-source /usr/local/bin/analyzer /usr/local/bin/analyzer

# Copy LLVM 14 complete runtime (compiler-rt, headers, fuzzer libs)
# No symlink hack needed - this is the real LLVM 14 runtime
COPY --from=llvm-source /usr/local/lib/clang/14.0.6/ /usr/local/lib/clang/14.0.6/

# Remove clang 18 runtime to avoid compile_libfuzzer glob matching both versions
RUN rm -rf /usr/local/lib/clang/18
# Note: libc++ kept from base image

# Copy diff_parser.py from components/directed (reused diff parsing logic)
COPY components/directed/src/daemon/modules/diff_parser.py /scripts/diff_parser.py

# Copy slicer scripts
COPY oss-crs/bin/slicer.sh /slicer.sh
COPY oss-crs/scripts/generate_allowlist.py /scripts/generate_allowlist.py
RUN chmod +x /slicer.sh

# Slicer entrypoint
CMD ["/slicer.sh"]
