# vi:filetype=
#
# Regression test for which upstream responses the body filter renders. It
# used to render any application/json response whatever its status: an API
# error such as a 404 {"error":...} came out as the page template filled with
# nothing, and a 206 to a Range request, a slice of JSON, failed to parse and
# turned into a 500. Now only 200 responses are rendered; anything else
# passes through untouched.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 3 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: 200 is rendered
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /backend {
        default_type application/json;
        return 200 '{"name":"x"}';
    }
    location /test {
        mustach_template "<p>{{name}}</p>";
        mustach_content text/html;
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- request
GET /test
--- response_headers
Content-Type: text/html
--- response_body chop
<p>x</p>

=== TEST 2: a 404 API error passes through untouched
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /backend {
        default_type application/json;
        return 404 '{"error":"nope"}';
    }
    location /test {
        mustach_template "<p>{{name}}</p>";
        mustach_content text/html;
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- request
GET /test
--- error_code: 404
--- response_headers
Content-Type: application/json
--- response_body chop
{"error":"nope"}

=== TEST 3: a 206 slice of JSON passes through untouched
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /data/ {
        alias html/;
        types { }
        default_type application/json;
    }
    location /test {
        mustach_template "<p>{{name}}</p>";
        mustach_content text/html;
        proxy_pass http://127.0.0.1:$server_port/data/a.json;
    }
--- user_files
>>> a.json
{"name":"full","pad":"xxxxxxxxxxxxxxxxxxxxxxxxxx"}
--- more_headers
Range: bytes=0-9
--- request
GET /test
--- error_code: 206
--- response_headers
Content-Type: application/json
--- response_body chop
{"name":"f

=== TEST 4: 201 is not rendered either
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /backend {
        default_type application/json;
        return 201 '{"name":"x"}';
    }
    location /test {
        mustach_template "<p>{{name}}</p>";
        mustach_content text/html;
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- request
GET /test
--- error_code: 201
--- response_headers
Content-Type: application/json
--- response_body chop
{"name":"x"}
