{ prev }:
{
  # OpenVINO accepts an invalid Scatter index instead of returning an error.
  # Keep testing other providers until OpenVINO fixes this behavior. Local fix;
  # onnxruntime 1.27.1 fails on Nixpkgs 6b93cd12c87540c01762ba068f30928f4f916954
  # (reviewed 2026-11-18). Apply it to the master package set too.
  onnxruntime = prev.onnxruntime.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./onnxruntime-scatter-openvino.patch ];
  });
}
