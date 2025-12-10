{ config, ... }:
let
  autheliaDomain = "auth.${config.domains.main}";
  authzURL = "https://${autheliaDomain}/api/authz/auth-request";
in
{
  location = ''
    ## Send a subrequest to Authelia to verify if the user is authenticated and has permission to access the resource.
    auth_request /internal/authelia/authz;

    ## Save the upstream metadata response headers from Authelia to variables.
    auth_request_set $user $upstream_http_remote_user;
    auth_request_set $groups $upstream_http_remote_groups;
    auth_request_set $name $upstream_http_remote_name;
    auth_request_set $email $upstream_http_remote_email;

    ## Modern Method: Set the $redirection_url to the Location header of the response to the Authz endpoint.
    auth_request_set $redirection_url $upstream_http_location;

    ## Inject the metadata response headers from the variables into the request made to the backend.
    proxy_set_header Remote-User $user;
    proxy_set_header Remote-Groups $groups;
    proxy_set_header Remote-Email $email;
    proxy_set_header Remote-Name $name;

    ## Modern Method: When there is a 401 response code from the authz endpoint redirect to the $redirection_url.
    error_page 401 =302 $redirection_url;
  '';

  server = ''
    set $upstream_authelia ${authzURL};

    ## Virtual endpoint created by nginx to forward auth requests.
    location /internal/authelia/authz {
      ## Bypass Authelia if API key is present
      if ($http_x_api_key) {
        return 200;
      }

      ## Essential Proxy Configuration
      internal;
      resolver 1.1.1.1 valid=30s;
      proxy_pass $upstream_authelia;

      ## Headers
      ## The headers starting with X-* are required.
      proxy_set_header X-Original-Method $request_method;
      proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
      proxy_set_header X-Forwarded-For $remote_addr;
      proxy_set_header Content-Length "";
      proxy_set_header Connection "";

      ## Basic Proxy Configuration
      proxy_pass_request_body off;
      proxy_next_upstream error timeout invalid_header http_500 http_502 http_503; # Timeout if the real server is dead
      proxy_redirect http:// $scheme://;
      proxy_http_version 1.1;
      proxy_cache_bypass $cookie_session;
      proxy_no_cache $cookie_session;
      proxy_buffers 4 32k;
      client_body_buffer_size 128k;

      ## Advanced Proxy Configuration
      send_timeout 5m;
      proxy_read_timeout 240;
      proxy_send_timeout 240;
      proxy_connect_timeout 240;
    }
  '';
}
