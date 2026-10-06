# vi:filetype=
#
# Checks that filters further down the chain see the rendered response's
# Content-Type, not the upstream's application/json: gzip_types and
# sub_filter_types both match on it. The module now also drops the lowercased
# copy of the old type that ngx_http_test_content_type() caches, as every
# nginx module that changes the type does.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: gzip_types matches the rendered type
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /backend {
        default_type application/json;
        return 200 '{"a":"b"}';
    }
    location /test {
        mustach_template "<p>{{a}}</p>";
        mustach_content text/html;
        gzip on;
        gzip_types text/html;
        gzip_min_length 1;
        proxy_set_header Accept-Encoding "";
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- more_headers
Accept-Encoding: gzip
--- request
GET /test
--- response_headers
Content-Encoding: gzip

=== TEST 2: sub_filter_types matches the rendered type
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /backend {
        default_type application/json;
        return 200 '{"a":"b"}';
    }
    location /test {
        mustach_template "<p>{{a}}</p>";
        mustach_content text/plain;
        sub_filter_types text/plain;
        sub_filter '<p>' '<div>';
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- request
GET /test
--- response_body chop
<div>b</p>
