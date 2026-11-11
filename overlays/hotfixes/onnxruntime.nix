{ prev }:
{
  # Scatter.InvalidIndex fails with OpenVINO enabled on x86_64; OpenVINO may
  # handle out-of-range indices differently from the CPU execution provider:
  # https://github.com/microsoft/onnxruntime/issues/25251
  # Exclude only OpenVINO from this test; keep the CPU bounds check and the rest
  # of the suite. Remove when upstream handles this provider in the test.
  # Reviewed 2026-11-11 at Nixpkgs f4a03c008967841f2a0b3cb7c436fc6fc31671f6:
  # the unpatched test failed on two workers; the patched full test suite passed.
  onnxruntime = prev.onnxruntime.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      substituteInPlace onnxruntime/test/providers/cpu/tensor/scatter_op_test.cc \
        --replace-fail \
          '{kCudaExecutionProvider, kCudaNHWCExecutionProvider, kTensorrtExecutionProvider, kQnnExecutionProvider, kWebGpuExecutionProvider});' \
          '{kCudaExecutionProvider, kCudaNHWCExecutionProvider, kTensorrtExecutionProvider, kQnnExecutionProvider, kWebGpuExecutionProvider, kOpenVINOExecutionProvider});'
    '';
  });
}
