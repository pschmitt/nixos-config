{ config, ... }:
let
  port = 8084;
in
{
  virtualisation.oci-containers.containers.cwabd = {
    image = "ghcr.io/calibrain/calibre-web-automated-book-downloader";
    autoStart = true;
    environment = {
      FLASK_PORT = toString port;
      LOG_LEVEL = "info";
      BOOK_LANGUAGE = "en";
      USE_BOOK_TITLE = "true";
      TZ = config.time.timeZone;
      APP_ENV = "prod";
      UID = "1000";
      GID = "100";
      MAX_CONCURRENT_DOWNLOADS = "3";
      DOWNLOAD_PROGRESS_UPDATE_INTERVAL = "5";
    };
    volumes = [
      "/mnt/data/books/ingest:/cwa-book-ingest"
    ];
    extraOptions = [
      "--net=ns:/run/netns/mullvad"
    ];
  };

  arr.services.cwabd = {
    inherit port;
    host = "cwabd.arr.${config.domains.main}";
    container = "cwabd";
    # The book downloader exposes its UI at "/", not a dedicated health path.
    monit.request = "/";
  };
}
