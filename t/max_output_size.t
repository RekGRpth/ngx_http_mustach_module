# vi:filetype=
#
# Regression test for mustach_max_output_size. Nothing bounded the size of a
# render, and since partials taken from the data are templates too, a small
# JSON could expand into an arbitrarily large page held in worker memory. The
# render now stops with a 500 once its output outgrows the limit (10m by
# default); 0 lifts it.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: output exactly at the limit is rendered
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_max_output_size 20;
        mustach_template "{{a}}{{a}}";
        mustach_content text/plain;
        mustach_json '{"a":"0123456789"}';
    }
--- request
GET /test
--- response_body chop
01234567890123456789

=== TEST 2: output over the limit is a 500, handler mode
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_max_output_size 19;
        mustach_template "{{a}}{{a}}";
        mustach_content text/plain;
        mustach_json '{"a":"0123456789"}';
    }
--- request
GET /test
--- error_code: 500
--- error_log
rendered output is larger than mustach_max_output_size

=== TEST 3: output over the limit through a data partial, filter mode
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /backend {
        default_type application/json;
        return 200 '{"a":"0123456789","p":"{{a}}{{a}}"}';
    }
    location /test {
        mustach_max_output_size 15;
        mustach_template "{{>p}}";
        mustach_content text/plain;
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- request
GET /test
--- error_code: 500
--- error_log
rendered output is larger than mustach_max_output_size

=== TEST 4: 0 lifts the limit
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_max_output_size 0;
        mustach_template "{{a}}{{a}}";
        mustach_content text/plain;
        mustach_json '{"a":"0123456789"}';
    }
--- request
GET /test
--- response_body chop
01234567890123456789
