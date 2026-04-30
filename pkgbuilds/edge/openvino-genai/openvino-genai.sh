_openvino_dir=/opt/intel/openvino_genai
_openvino_libdir="${_openvino_dir}/runtime/lib/intel64"
_openvino_tbbdir="${_openvino_dir}/runtime/3rdparty/tbb/lib"
_openvino_pkgconfig=
_openvino_ld=

if [ -d "${_openvino_dir}" ]; then
  export OPENVINO_INSTALL_DIR="${_openvino_dir}"
  export INTEL_OPENVINO_DIR="${_openvino_dir}"

  if [ -d "${_openvino_dir}/runtime/cmake" ]; then
    export OpenVINO_DIR="${_openvino_dir}/runtime/cmake"
    export OpenVINOGenAI_DIR="${_openvino_dir}/runtime/cmake"
  fi

  if [ -d "${_openvino_libdir}" ]; then
    _openvino_ld="${_openvino_libdir}"
    if [ -d "${_openvino_libdir}/pkgconfig" ]; then
      _openvino_pkgconfig="${_openvino_libdir}/pkgconfig"
    fi
  fi

  if [ -d "${_openvino_tbbdir}" ]; then
    _openvino_ld="${_openvino_ld:+${_openvino_ld}:}${_openvino_tbbdir}"
    if [ -d "${_openvino_tbbdir}/pkgconfig" ]; then
      _openvino_pkgconfig="${_openvino_pkgconfig:+${_openvino_pkgconfig}:}${_openvino_tbbdir}/pkgconfig"
    fi
    if [ -d "${_openvino_tbbdir}/cmake/TBB" ]; then
      export TBB_DIR="${_openvino_tbbdir}/cmake/TBB"
    fi
  fi

  if [ -n "${_openvino_ld}" ]; then
    export LD_LIBRARY_PATH="${_openvino_ld}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
  fi

  if [ -n "${_openvino_pkgconfig}" ]; then
    export PKG_CONFIG_PATH="${_openvino_pkgconfig}${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
  fi
fi

unset _openvino_dir
unset _openvino_libdir
unset _openvino_tbbdir
unset _openvino_pkgconfig
unset _openvino_ld
