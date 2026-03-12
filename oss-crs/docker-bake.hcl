# OSS-CRS Docker Bake Configuration
#
# Prepare phase: Builds LLVM base image for use by slicer/builder/runner
# Slicer/builder/runner are built during target_build_phase via docker-compose
#
# Usage:
#   docker buildx bake -f oss-crs/docker-bake.hcl

variable "TARGET_BASE_IMAGE" {
  default = "ghcr.io/aixcc-finals/base-builder:v1.3.0"
}

group "default" {
  targets = ["prepare"]
}

# Prepare: Target base + LLVM 14.0.6 (cached, slow build)
target "prepare" {
  context    = "."
  dockerfile = "oss-crs/dockerfiles/prepare.Dockerfile"
  args = {
    target_base_image = "${TARGET_BASE_IMAGE}"
  }
  tags = ["oss-crs-prepared:latest"]
}
