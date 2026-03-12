group "default" {
  targets = ["directed-fuzzer-base"]
}

target "directed-fuzzer-base" {
  context    = "."
  dockerfile = "oss-crs/dockerfiles/base.Dockerfile"
}
