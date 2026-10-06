# vi:filetype=
#
# Regression test for empty JSON strings. decode_string() returned "" as a
# zero-length slice of the JSON buffer, and mustach takes a zero length to
# mean "NUL-terminated, measure it": {{a}} over {"a":"","b":"xyz"} printed
# the rest of the document (",&quot;b&quot;:&quot;xyz&quot;}") and read on
# past the end of the buffer. Same for an empty objiter key.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: empty string value, escaped and unescaped, handler mode
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "[{{a}}][{{{a}}}][{{&a}}]";
        mustach_content text/plain;
        mustach_json '{"a":"","b":"xyz"}';
    }
--- request
GET /test
--- response_body chop
[][][]

=== TEST 2: empty string value, filter mode
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /backend {
        default_type application/json;
        return 200 '{"a":"","b":"xyz"}';
    }
    location /test {
        mustach_template "[{{a}}]";
        mustach_content text/plain;
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- request
GET /test
--- response_body chop
[]

=== TEST 3: empty objiter key
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "{{#o.*}}<{{*}}={{.}}>{{/o.*}}";
        mustach_content text/plain;
        mustach_json '{"o":{"":1,"k":""},"b":"xyz"}';
    }
--- request
GET /test
--- response_body chop
<=1><k=>

