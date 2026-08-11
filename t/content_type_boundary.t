# vi:filetype=
#
# Regression test for the Content-Type prefix match in
# ngx_http_mustach_header_filter: it used to match any type starting with
# "application/json" case-insensitively with no boundary check, so
# "application/jsonp" (a distinct, real media type) was wrongly treated as
# JSON and passed through the mustach body filter, mangling the response.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: application/jsonp is not treated as JSON
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        default_type application/jsonp;
        mustach_template "{{a}}";
        return 200 '{"a":"b"}';
    }
--- request
    GET /test
--- response_body chop
{"a":"b"}

=== TEST 2: application/json is still treated as JSON
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        default_type application/json;
        mustach_template "{{a}}";
        return 200 '{"a":"b"}';
    }
--- request
    GET /test
--- response_body chop
b

=== TEST 3: application/json with a charset param is still treated as JSON
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        default_type 'application/json; charset=utf-8';
        mustach_template "{{a}}";
        return 200 '{"a":"b"}';
    }
--- request
    GET /test
--- response_body chop
b
