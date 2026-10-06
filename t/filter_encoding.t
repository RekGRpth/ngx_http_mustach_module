# vi:filetype=
#
# Regression test for compressed upstream JSON. proxy_pass forwards the
# client's Accept-Encoding, so a backend that compresses JSON sent gzip bytes,
# which the body filter tried to parse and failed with a 500 "invalid json".
# A response with a Content-Encoding is now passed through untouched, with a
# warning; with Accept-Encoding cleared towards the upstream it renders.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 9;

no_shuffle();
run_tests();

__DATA__

=== TEST 1: gzip-encoded JSON passes through with a warning
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /data/ {
        alias html/;
        types { }
        default_type application/json;
        gzip on;
        gzip_types application/json;
        gzip_min_length 1;
    }
    location /test {
        mustach_template "[{{a}}]";
        mustach_content text/plain;
        proxy_pass http://127.0.0.1:$server_port/data/a.json;
    }
--- user_files
>>> a.json
{"a":"b"}
--- more_headers
Accept-Encoding: gzip
--- request
GET /test
--- response_headers
Content-Encoding: gzip
Content-Type: application/json
--- error_log
not rendering a "gzip"-encoded response

=== TEST 2: with Accept-Encoding cleared towards the upstream, it renders
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /data/ {
        alias html/;
        types { }
        default_type application/json;
        gzip on;
        gzip_types application/json;
        gzip_min_length 1;
    }
    location /test {
        mustach_template "[{{a}}]";
        mustach_content text/plain;
        proxy_set_header Accept-Encoding "";
        proxy_pass http://127.0.0.1:$server_port/data/a.json;
    }
--- user_files
>>> a.json
{"a":"b"}
--- more_headers
Accept-Encoding: gzip
--- request
GET /test
--- response_body chop
[b]
--- no_error_log
not rendering

=== TEST 3: Content-Encoding: identity still renders
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /backend {
        default_type application/json;
        add_header Content-Encoding identity;
        return 200 '{"a":"b"}';
    }
    location /test {
        mustach_template "[{{a}}]";
        mustach_content text/plain;
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- request
GET /test
--- response_body chop
[b]
