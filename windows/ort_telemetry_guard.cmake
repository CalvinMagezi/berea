# Stops a Profile or Release Windows build: the official ONNX Runtime library the read-aloud
# plugin downloads has Microsoft telemetry on by default (see TECHDEBT.md). Run as a script with
# -DCONFIG=<build configuration>; set BEREA_ALLOW_ORT_TELEMETRY=ON only to accept that on purpose.
if(NOT CONFIG STREQUAL "Debug")
  message(FATAL_ERROR
    "Windows ${CONFIG} builds are blocked: the ONNX Runtime library on Windows sends telemetry by "
    "default, which Berea's zero-data rule forbids. Build Debug, or configure with "
    "-DBEREA_ALLOW_ORT_TELEMETRY=ON (or set that environment variable) if this has been "
    "accepted. See TECHDEBT.md.")
endif()
