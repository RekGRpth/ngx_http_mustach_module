# vi:filetype=
#
# Regression test for JSON that jsmn accepts but whose object members don't
# have exactly one value ({"a"}, {"a":}, {"a" "b" "c"}, {"a":1 "b":2}).
# find_member() and objiter take a member's value to be the token right after
# its key, so on such input they read past the end of the token array. These
# are now rejected as invalid json. Also covers whitespace-only JSON, for
# which jsmn returns no tokens and tokens[0] used to be read uninitialized.

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => repeat_each() * 3 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: member without value is rejected
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "{{zz}}";
        mustach_content text/html;
        mustach_json '{"a"}';
    }
--- request
    GET /test
--- error_code: 500
--- error_log
invalid json
--- no_error_log
[alert]

=== TEST 2: member with empty value is rejected
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "{{zz}}";
        mustach_content text/html;
        mustach_json '{"a":}';
    }
--- request
    GET /test
--- error_code: 500
--- error_log
invalid json
--- no_error_log
[alert]

=== TEST 3: keys without separators are rejected
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "{{zz}}";
        mustach_content text/html;
        mustach_json '{"a" "b" "c"}';
    }
--- request
    GET /test
--- error_code: 500
--- error_log
invalid json
--- no_error_log
[alert]

=== TEST 4: member with two values is rejected
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "{{zz}}";
        mustach_content text/html;
        mustach_json '{"a":1 "b":2}';
    }
--- request
    GET /test
--- error_code: 500
--- error_log
invalid json
--- no_error_log
[alert]

=== TEST 5: nested member without value is rejected before objiter sees it
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "{{#a.*}}{{*}}{{/a.*}}";
        mustach_content text/html;
        mustach_json '{"a":{"k"}}';
    }
--- request
    GET /test
--- error_code: 500
--- error_log
invalid json
--- no_error_log
[alert]

=== TEST 6: whitespace-only JSON renders like {}
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "x{{a}}y";
        mustach_content text/html;
        mustach_json '  ';
    }
--- request
    GET /test
--- response_body chop
xy
--- no_error_log
[alert]

=== TEST 7: well-formed nested JSON still renders
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "{{#a.b}}{{c}}{{/a.b}}{{e}}";
        mustach_content text/html;
        mustach_json '{"a":{"b":[1,{"c":"d"}]},"e":"f"}';
    }
--- request
    GET /test
--- response_body chop
df
--- no_error_log
[alert]
