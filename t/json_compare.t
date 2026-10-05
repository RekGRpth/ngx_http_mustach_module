# vi:filetype=
#
# Regression test for numeric comparisons ({{#x=N}}, {{#x>N}}, {{#x<N}}).
# compare() ran atof() straight on the JSON buffer, which isn't
# NUL-terminated: when the whole JSON is a bare number, atof() read past its
# end (a crash next to an unmapped page, a wrong value when whatever follows
# in the pool looks like more digits). Overrunning the buffer can't be
# reproduced deterministically from here; these cases check that the
# comparisons themselves still come out right, including numbers too long
# for the on-stack copy.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: bare root number, equal / greater / less
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /backend {
        default_type application/json;
        return 200 '5';
    }
    location /test {
        mustach_template "{{#.=5}}eq{{/.=5}}{{#.>4}}gt{{/.>4}}{{#.<4}}lt{{/.<4}}";
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- request
GET /test
--- response_body chop
eqgt

=== TEST 2: number inside an object
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /backend {
        default_type application/json;
        return 200 '{"a":5}';
    }
    location /test {
        mustach_template "{{#a=5}}eq{{/a=5}}{{#a>4}}gt{{/a>4}}{{#a<4}}lt{{/a<4}}";
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- request
GET /test
--- response_body chop
eqgt

=== TEST 3: bare root number longer than the on-stack copy
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /backend {
        default_type application/json;
        return 200 '100000000000000000000000000000000000000000000000000000000000000000000000000000000';
    }
    location /test {
        mustach_template "{{#.=1e80}}eq{{/.=1e80}}{{#.>1e79}}gt{{/.>1e79}}";
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- request
GET /test
--- response_body chop
eqgt
