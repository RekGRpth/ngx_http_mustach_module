# vi:filetype=
#
# Regression test for the size of templates kept in the per-worker cache. The
# LRU bounded the number of entries only, so a variable-sourced template that
# a client can influence could keep up to mustach_template_cache entries of
# any size alive per worker. Templates larger than 64k are now compiled per
# request instead of cached; this checks that such a template renders, on
# repeated requests too, and that a small one still does.

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => repeat_each() * 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: a template over 64k from a variable renders
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        client_body_buffer_size 1m;
        mustach_template $request_body;
        mustach_content text/plain;
        mustach_json '{"a":"!"}';
    }
--- request eval
"POST /test\n" . ('x' x 70000) . '{{a}}'
--- response_body eval
('x' x 70000) . '!'

=== TEST 2: a small template from a variable still renders
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template $request_body;
        mustach_content text/plain;
        mustach_json '{"a":"!"}';
    }
--- request eval
"POST /test\n" . '[{{a}}]'
--- response_body chop
[!]
