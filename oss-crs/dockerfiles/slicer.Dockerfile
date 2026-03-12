# Slicer container for diff parsing and function detection
# Part of build-target phase: fetches diff, identifies changed functions

ARG target_base_image
FROM ${target_base_image}

# Install libCRS for artifact management
COPY --from=libcrs . /opt/libCRS
RUN /opt/libCRS/install.sh

# Install Python dependencies for diff parsing
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
RUN chmod +x /slicer.sh

# Slicer entrypoint
CMD ["/slicer.sh"]
