# Directed Fuzzer Builder
# Compiles target with AFL++ using allowlist from slicer
#
# Uses base image's compiler toolchain (not LLVM 14).
# LLVM 14 is only needed in the slicer for bitcode analysis.

# ARG for target base image (passed by docker-compose during target build)
ARG target_base_image

# Final stage: extend target base with builder tools
FROM ${target_base_image}

# Install libCRS for artifact management (context passed by docker-compose)
COPY --from=libcrs . /opt/libCRS
RUN /opt/libCRS/install.sh

# Copy builder script
COPY oss-crs/bin/builder.sh /builder.sh
RUN chmod +x /builder.sh

CMD ["/builder.sh"]
