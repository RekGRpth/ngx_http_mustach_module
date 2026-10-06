# vi:filetype=
#
# Regression test for the truthiness of JSON numbers in sections. A number
# counted as zero only when it had no non-zero digit anywhere, exponent
# included, so 0e5 and 0.0e1 -- both zero -- opened {{#x}} sections. Only the
# mantissa counts now.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: zeros, whatever their spelling, are falsy
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "{{#a}}a{{/a}}{{#b}}b{{/b}}{{#c}}c{{/c}}{{#d}}d{{/d}}{{#e}}e{{/e}}{{#f}}f{{/f}}.";
        mustach_content text/plain;
        mustach_json '{"a":0,"b":-0,"c":0.0,"d":0e5,"e":0.0e1,"f":0E-3}';
    }
--- request
GET /test
--- response_body chop
.

=== TEST 2: non-zero numbers are truthy, small or with an exponent
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "{{#a}}a{{/a}}{{#b}}b{{/b}}{{#c}}c{{/c}}{{#d}}d{{/d}}{{#e}}e{{/e}}.";
        mustach_content text/plain;
        mustach_json '{"a":1,"b":-0.5,"c":1e-5,"d":10,"e":2E3}';
    }
--- request
GET /test
--- response_body chop
abcde.
