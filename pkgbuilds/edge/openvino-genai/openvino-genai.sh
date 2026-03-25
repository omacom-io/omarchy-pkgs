export INTEL_OPENVINO_DIR=/opt/intel/openvino_2026.0.0.0
export PATH="${INTEL_OPENVINO_DIR}/runtime/bin${PATH:+:${PATH}}"
export LD_LIBRARY_PATH="${INTEL_OPENVINO_DIR}/runtime/lib/intel64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
