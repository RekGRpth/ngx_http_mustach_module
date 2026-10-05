# vi:filetype=
#
# Regression test for a template that renders to nothing. The rendered output
# went out in a zero-size temporary buffer, which the write filter rejects
# ("zero size buf in writer"), so the client got no response at all. Now an
# empty render is sent as a special last buffer, with Content-Length: 0.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 4 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: handler mode, empty output
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "{{x}}";
        mustach_content text/plain;
        mustach_json '{}';
    }
--- request
GET /test
--- response_headers
Content-Length: 0
--- response_body chop
--- no_error_log
[alert]

=== TEST 2: filter mode, empty output
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /backend {
        default_type application/json;
        return 200 '{}';
    }
    location /test {
        mustach_template "{{x}}";
        mustach_content text/plain;
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- request
GET /test
--- response_headers
Content-Length: 0
--- response_body chop
--- no_error_log
[alert]
