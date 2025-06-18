{ final, prev }:
{
  paperless-ngx = prev.paperless-ngx.overrideAttrs (oldAttrs: {
    doCheck = false;
    disabledTests = (oldAttrs.disabledTests or [ ]) ++ [
      "test_barcodes"
      "test_consume_file"
      "test_management_consumer"
      "test_preprocessor"
      "test_views"
    ];
  });
}
