# vi:filetype=
#
# Regression test for content-handler output that is itself application/json
# (mustach_content application/json, or default_type). The header filter used
# to take the handler's own response for upstream JSON and render the already
# rendered output a second time with the same template.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: mustach_content application/json is rendered once
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template '{"b":"{{b}}!"}';
        mustach_content application/json;
        mustach_json '{"b":"x"}';
    }
--- request
GET /test
--- response_body chop
{"b":"x!"}

=== TEST 2: default_type application/json is rendered once
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        default_type application/json;
        mustach_template '{"b":"{{b}}!"}';
        mustach_json '{"b":"x"}';
    }
--- request
GET /test
--- response_body chop
{"b":"x!"}

=== TEST 3: filter mode still renders upstream JSON
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /backend {
        default_type application/json;
        return 200 '{"b":"x"}';
    }
    location /test {
        mustach_template '{"b":"{{b}}!"}';
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- request
GET /test
--- response_body chop
{"b":"x!"}
