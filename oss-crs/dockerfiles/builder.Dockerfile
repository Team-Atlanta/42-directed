# Directed Fuzzer Builder
# Compiles target with AFL++ using allowlist from slicer
#
# Uses pre-built LLVM from prepare phase (oss-crs-prepared:latest)

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

# Copy builder script
COPY oss-crs/bin/builder.sh /builder.sh
RUN chmod +x /builder.sh

CMD ["/builder.sh"]
