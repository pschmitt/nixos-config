{ final, prev }:
{
  paperless-ngx = prev.paperless-ngx.overrideAttrs (oldAttrs: {
    pname = "paperless-ngx";
    doCheck = false;
  });
}
