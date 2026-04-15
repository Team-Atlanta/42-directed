# Directed Fuzzer Runner
# Executes libFuzzer harnesses with crash/seed submission
#
# Downloads build artifacts from builder phase via libCRS and runs
# fuzzing with parallel workers based on OSS_CRS_CPUSET.

# ARG for target base image (passed by docker-compose during target build)
ARG target_base_image
FROM ${target_base_image}

# Install libCRS for artifact management (context passed by docker-compose)
COPY --from=libcrs . /opt/libCRS
RUN /opt/libCRS/install.sh

# Copy runner script
COPY oss-crs/bin/runner.sh /runner.sh
RUN chmod +x /runner.sh

CMD ["/runner.sh"]
