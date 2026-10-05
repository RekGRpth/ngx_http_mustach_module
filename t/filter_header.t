# vi:filetype=
#
# Regression test for the filter-mode header that the header filter holds
# back until the body has been rendered. It used to be sent only when there
# was a body to render and the render succeeded, so the client got no status
# line and no headers at all for:
# - HEAD through a proxy (no body ever arrives),
# - an empty upstream body,
# - JSON the render fails on (instead of a 500).

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 13;

no_shuffle();
run_tests();

__DATA__

=== TEST 1: HEAD through a proxy gets the GET headers, minus the length
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /backend {
        default_type application/json;
        return 200 '{"a":"b"}';
    }
    location /test {
        mustach_template "{{a}}";
        mustach_content text/plain;
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- request
HEAD /test
--- response_headers
Content-Type: text/plain
!Content-Length
--- timeout: 3
--- no_error_log
[alert]

=== TEST 2: HEAD to a static JSON file is rendered as for GET
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /data/ {
        alias html/;
        types { }
        default_type application/json;
        mustach_template "{{a}}";
        mustach_content text/plain;
    }
--- user_files
>>> a.json
{"a":"b"}
--- request
HEAD /data/a.json
--- response_headers
Content-Type: text/plain
--- timeout: 3
--- no_error_log
[alert]

=== TEST 3: empty upstream body passes through with its header
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /backend {
        default_type application/json;
        return 200 '';
    }
    location /test {
        mustach_template "{{a}}";
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- request
GET /test
--- response_body chop
--- timeout: 3
--- no_error_log
[alert]

=== TEST 4: invalid upstream JSON gets a 500
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /backend {
        default_type application/json;
        return 200 '{"a"';
    }
    location /test {
        mustach_template "{{a}}";
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- request
GET /test
--- error_code: 500
--- timeout: 3
--- error_log
invalid json
--- no_error_log
[alert]
