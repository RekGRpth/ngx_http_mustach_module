# vi:filetype=
#
# Regression test for the body-filter buffering path in
# ngx_http_mustach_body_filter (chain-append fix for a dropped final
# ngx_chain_t link). This is a non-regression check, not a bug catcher:
# empirically, nginx's own proxy/upstream code always emits the terminal
# last_buf marker as its own separate, empty buffer, decoupled from real
# data, so this exact scenario doesn't actually exercise the fixed code
# path via proxy_pass -- it passes the same with or without the fix.
# Kept anyway to pin down correct behaviour for this realistic multi-flush
# shape and catch unrelated regressions.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: final data chunk arrives together with the last_buf flag (close-delimited upstream)
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
    load_module /etc/nginx/modules/ngx_http_echo_module.so;
--- config
    location /backend {
        default_type application/json;
        echo -n '{"greeting":"Hello, ';
        echo_flush;
        echo_sleep 0.3;
        echo -n 'World!"}';
    }
    location /test {
        mustach_template "{{greeting}}";
        proxy_pass http://127.0.0.1:$server_port/backend;
        proxy_http_version 1.0;
    }
--- request
    GET /test
--- response_body chop
Hello, World!
