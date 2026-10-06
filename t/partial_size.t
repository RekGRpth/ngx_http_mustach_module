# vi:filetype=
#
# Regression test for the size of partials taken from the data. Such a
# partial is a template the JSON supplies, and libmustach copies every tag
# name it looks up into a stack buffer of that name's size: a multi-megabyte
# tag name in a data partial overflowed the worker's stack (SIGSEGV). Data
# partials are now capped at 64k, which bounds their tag names; a larger one
# gets a 500. Partials from files aren't affected.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: a data partial of exactly 64k is rendered
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        client_body_buffer_size 1m;
        mustach_template "{{>p}}";
        mustach_content text/plain;
        mustach_json $request_body;
    }
--- request eval
"POST /test\n" . '{"p":"' . ('x' x 65536) . '"}'
--- response_body eval
'x' x 65536

=== TEST 2: a data partial one byte over 64k is a 500
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        client_body_buffer_size 1m;
        mustach_template "{{>p}}";
        mustach_content text/plain;
        mustach_json $request_body;
    }
--- request eval
"POST /test\n" . '{"p":"' . ('x' x 65537) . '"}'
--- error_code: 500
--- error_log
partial "p" from the data is larger than 64k

=== TEST 3: a partial from a file isn't limited
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "{{>big}}";
        mustach_content text/plain;
        mustach_partials_root html;
        mustach_json '{}';
    }
--- user_files eval
">>> big.mustache\n" . ('y' x 100000)
--- request
GET /test
--- response_body eval
'y' x 100000
