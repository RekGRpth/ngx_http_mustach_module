# vi:filetype=
#
# Regression test for an empty mustach_template. A literal "" loaded fine and
# then failed every JSON response with a 500, and there was no way to turn an
# inherited template off in a nested location. Now "" turns rendering off
# there; a variable template that comes out empty lets that response through
# in body-filter mode (so a map can switch rendering per request), and still
# gives a 500 in content-handler mode, with a clear log line.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: mustach_template "" turns an inherited template off
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /backend {
        default_type application/json;
        return 200 '{"a":"b"}';
    }
    location /p/ {
        mustach_template "[{{a}}]";
        location /p/raw {
            mustach_template "";
            proxy_pass http://127.0.0.1:$server_port/backend;
        }
    }
--- request
GET /p/raw
--- response_body chop
{"a":"b"}

=== TEST 2: a map that gives an empty template lets the response through
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- http_config
    map $arg_raw $page_tmpl { 1 ""; default "[{{a}}]"; }
--- config
    location /backend {
        default_type application/json;
        return 200 '{"a":"b"}';
    }
    location /test {
        mustach_template $page_tmpl;
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- request
GET /test?raw=1
--- response_body chop
{"a":"b"}

=== TEST 3: ... and a non-empty one renders
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- http_config
    map $arg_raw $page_tmpl { 1 ""; default "[{{a}}]"; }
--- config
    location /backend {
        default_type application/json;
        return 200 '{"a":"b"}';
    }
    location /test {
        mustach_template $page_tmpl;
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- request
GET /test
--- response_body chop
[b]

=== TEST 4: an empty variable template in content-handler mode is a 500
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        set $t "";
        mustach_template $t;
        mustach_json '{"a":"b"}';
    }
--- request
GET /test
--- error_code: 500
--- error_log
mustach: empty mustach_template

=== TEST 5: mustach_json next to mustach_template "" is a configuration error
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "";
        mustach_json '{"a":"b"}';
    }
--- must_die
--- suppress_stderr
--- error_log
"mustach_json" requires "mustach_template"
