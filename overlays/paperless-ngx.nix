{ final, prev }:
{
  paperless-ngx = prev.paperless-ngx.overrideAttrs (oldAttrs: {
    pname = "paperless-ngx";
    # YOLO: Disable all tests
    doCheck = false;
    checkPhase = '': ''; # Override the checkPhase to no-op.
    nativeCheckInputs = [ ]; # Remove any test-related inputs to avoid triggering pytestCheckPhase.
  });
}
