# vi:filetype=
#
# Regression test for upstream JSON arriving in many small pieces. Each piece
# used to be copied into a buffer and chain link of its own, and every call
# walked the whole chain to append: quadratic time and many times the data in
# memory for a body sent in tiny chunks. It's now appended to one buffer that
# grows by doubling; this checks that a body in many pieces renders the same
# as a whole one.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: JSON in 32 flushed pieces, unbuffered proxy
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
    load_module /etc/nginx/modules/ngx_http_echo_module.so;
--- config
    location /backend {
        default_type application/json;
        echo -n '{"items":[';
        echo_flush;
        echo -n '{"n":1},';
        echo_flush;
        echo -n '{"n":2},';
        echo_flush;
        echo -n '{"n":3},';
        echo_flush;
        echo -n '{"n":4},';
        echo_flush;
        echo -n '{"n":5},';
        echo_flush;
        echo -n '{"n":6},';
        echo_flush;
        echo -n '{"n":7},';
        echo_flush;
        echo -n '{"n":8},';
        echo_flush;
        echo -n '{"n":9},';
        echo_flush;
        echo -n '{"n":10},';
        echo_flush;
        echo -n '{"n":11},';
        echo_flush;
        echo -n '{"n":12},';
        echo_flush;
        echo -n '{"n":13},';
        echo_flush;
        echo -n '{"n":14},';
        echo_flush;
        echo -n '{"n":15},';
        echo_flush;
        echo -n '{"n":16},';
        echo_flush;
        echo -n '{"n":17},';
        echo_flush;
        echo -n '{"n":18},';
        echo_flush;
        echo -n '{"n":19},';
        echo_flush;
        echo -n '{"n":20},';
        echo_flush;
        echo -n '{"n":21},';
        echo_flush;
        echo -n '{"n":22},';
        echo_flush;
        echo -n '{"n":23},';
        echo_flush;
        echo -n '{"n":24},';
        echo_flush;
        echo -n '{"n":25},';
        echo_flush;
        echo -n '{"n":26},';
        echo_flush;
        echo -n '{"n":27},';
        echo_flush;
        echo -n '{"n":28},';
        echo_flush;
        echo -n '{"n":29},';
        echo_flush;
        echo -n '{"n":30}],';
        echo_flush;
        echo -n '"title":"many"}';
        echo_flush;
    }
    location /test {
        mustach_template "[{{title}}]{{#items}}<{{n}}>{{/items}}";
        mustach_content text/plain;
        proxy_pass http://127.0.0.1:$server_port/backend;
        proxy_http_version 1.1;
        proxy_buffering off;
    }
--- request
GET /test
--- response_body chop
[many]<1><2><3><4><5><6><7><8><9><10><11><12><13><14><15><16><17><18><19><20><21><22><23><24><25><26><27><28><29><30>

=== TEST 2: the same JSON in 32 pieces, buffered proxy with tiny buffers
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
    load_module /etc/nginx/modules/ngx_http_echo_module.so;
--- config
    location /backend {
        default_type application/json;
        echo -n '{"items":[';
        echo_flush;
        echo -n '{"n":1},';
        echo_flush;
        echo -n '{"n":2},';
        echo_flush;
        echo -n '{"n":3},';
        echo_flush;
        echo -n '{"n":4},';
        echo_flush;
        echo -n '{"n":5},';
        echo_flush;
        echo -n '{"n":6},';
        echo_flush;
        echo -n '{"n":7},';
        echo_flush;
        echo -n '{"n":8},';
        echo_flush;
        echo -n '{"n":9},';
        echo_flush;
        echo -n '{"n":10},';
        echo_flush;
        echo -n '{"n":11},';
        echo_flush;
        echo -n '{"n":12},';
        echo_flush;
        echo -n '{"n":13},';
        echo_flush;
        echo -n '{"n":14},';
        echo_flush;
        echo -n '{"n":15},';
        echo_flush;
        echo -n '{"n":16},';
        echo_flush;
        echo -n '{"n":17},';
        echo_flush;
        echo -n '{"n":18},';
        echo_flush;
        echo -n '{"n":19},';
        echo_flush;
        echo -n '{"n":20},';
        echo_flush;
        echo -n '{"n":21},';
        echo_flush;
        echo -n '{"n":22},';
        echo_flush;
        echo -n '{"n":23},';
        echo_flush;
        echo -n '{"n":24},';
        echo_flush;
        echo -n '{"n":25},';
        echo_flush;
        echo -n '{"n":26},';
        echo_flush;
        echo -n '{"n":27},';
        echo_flush;
        echo -n '{"n":28},';
        echo_flush;
        echo -n '{"n":29},';
        echo_flush;
        echo -n '{"n":30}],';
        echo_flush;
        echo -n '"title":"many"}';
        echo_flush;
    }
    location /test {
        mustach_template "[{{title}}]{{#items}}<{{n}}>{{/items}}";
        mustach_content text/plain;
        proxy_pass http://127.0.0.1:$server_port/backend;
        proxy_http_version 1.1;
        proxy_buffer_size 256;
        proxy_buffers 2 256;
        proxy_busy_buffers_size 256;
    }
--- request
GET /test
--- response_body chop
[many]<1><2><3><4><5><6><7><8><9><10><11><12><13><14><15><16><17><18><19><20><21><22><23><24><25><26><27><28><29><30>
