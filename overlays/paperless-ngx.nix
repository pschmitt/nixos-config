{ final, prev }:
{
  paperless-ngx = prev.paperless-ngx.overrideAttrs (oldAttrs: {
    disabledTests = (oldAttrs.disabledTests or [ ]) ++ [
      "test_consume_file"
    ];
  });
}
