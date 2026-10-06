# vi:filetype=
#
# Regression test for JSON taken from the request body. The content handler
# used to discard the body, so mustach_json $request_body always rendered
# against {}. It now reads the body first (in one buffer), warns when the
# data comes out empty because the body went to a temporary file, and
# client_max_body_size applies.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 10;

no_shuffle();
run_tests();

__DATA__

=== TEST 1: POST with JSON in the body is rendered
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "[{{a}}]";
        mustach_content text/plain;
        mustach_json $request_body;
    }
--- request
POST /test
{"a":"from body"}
--- response_body chop
[from body]
--- no_error_log
[warn]

=== TEST 2: GET without a body renders against {}
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "[{{a}}]";
        mustach_content text/plain;
        mustach_json $request_body;
    }
--- request
GET /test
--- response_body chop
[]
--- no_error_log
[warn]

=== TEST 3: a body buffered to a file renders against {} with a warning
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        client_body_buffer_size 1k;
        mustach_template "[{{a}}]";
        mustach_content text/plain;
        mustach_json $request_body;
    }
--- request eval
"POST /test\n" . '{"a":"in a file","pad":"' . ('x' x 8000) . '"}'
--- response_body chop
[]
--- error_log
raise client_body_buffer_size

=== TEST 4: client_max_body_size applies
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        client_max_body_size 10;
        mustach_template "[{{a}}]";
        mustach_content text/plain;
        mustach_json $request_body;
    }
--- request
POST /test
{"a":"more than ten bytes"}
--- error_code: 413
