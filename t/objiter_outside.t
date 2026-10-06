# vi:filetype=
#
# Regression test for the objiter key ({{*}}) used outside an object
# iteration. start() left the root frame's is_objiter and key uninitialized,
# and get() walks the frames down to the root looking for an objiter key: it
# read stack garbage and could use it as an index into the token array
# (valgrind: uninitialised value in get(); a crash with a dirty stack). The
# JSON alone could get there, through a partial taken from the data. Outside
# an iteration, {{*}} is now simply empty.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: {{*}} in the template, outside any iteration
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "[{{*}}]";
        mustach_content text/plain;
        mustach_json '{"a":1}';
    }
--- request
GET /test
--- response_body chop
[]

=== TEST 2: {{*}} in a partial taken from the data
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "[{{>p}}]";
        mustach_content text/plain;
        mustach_json '{"p":"{{*}}{{*}}","a":1}';
    }
--- request
GET /test
--- response_body chop
[]

=== TEST 3: {{*}} inside an object iteration still gives the keys
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /test {
        mustach_template "{{#o.*}}<{{*}}>{{/o.*}}";
        mustach_content text/plain;
        mustach_json '{"o":{"k":1,"m":2}}';
    }
--- request
GET /test
--- response_body chop
<k><m>
