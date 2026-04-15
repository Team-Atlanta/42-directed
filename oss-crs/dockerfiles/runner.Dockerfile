# Directed Fuzzer Runner
# Executes AFL++ against instrumented targets with crash/seed submission
#
# Downloads build artifacts from builder phase via libCRS and runs
# AFL++ fuzzing with parallel instances based on OSS_CRS_CPUSET.
#
# AFL++ (afl-fuzz) is pre-installed in the base-builder image at /src/aflplusplus/

# ARG for target base image (passed by docker-compose during target build)
ARG target_base_image
FROM ${target_base_image}

# Install libCRS for artifact management (context passed by docker-compose)
COPY --from=libcrs . /opt/libCRS
RUN /opt/libCRS/install.sh

# Ensure afl-fuzz is on PATH (base image has it at /src/aflplusplus/)
ENV PATH="/src/aflplusplus:${PATH}"

# Copy runner script
COPY oss-crs/bin/runner.sh /runner.sh
RUN chmod +x /runner.sh

CMD ["/runner.sh"]
