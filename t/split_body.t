# vi:filetype=

use lib 'lib';
use Test::Nginx::Socket;

plan tests => 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: json body split across two upstream reads with buffer reuse
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
    load_module /etc/nginx/modules/ngx_http_echo_module.so;
--- config
    location /backend {
        default_type application/json;
        echo -n '{"greeting":"Hello, ';
        echo_flush;
        echo_sleep 0.3;
        echo -n 'World!","junk":"XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"}';
    }
    location /test {
        mustach_template "{{greeting}}";
        proxy_pass http://127.0.0.1:$server_port/backend;
        proxy_http_version 1.1;
        proxy_buffering on;
        proxy_buffer_size 256;
        proxy_buffers 3 256;
        proxy_busy_buffers_size 256;
    }
--- request
    GET /test
--- response_body chop
Hello, World!
