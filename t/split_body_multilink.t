# vi:filetype=
#
# Regression test for the tail-scan fix in ngx_http_mustach_body_filter
# (last_buf/last_in_chain must be checked on the last link of the `in`
# chain, not just the head). This request reliably produces a genuine
# 2-link chain in one filter call, with last_buf set on the second link
# only -- confirmed via debug logs. It is a non-regression check, not a
# bug catcher: nginx's upstream code still sends a separate empty
# finalizing flush afterwards regardless of what this module decides, so
# even the unfixed head-only check ends up producing the right answer here
# (buffering both links, then finishing on that later empty call). Kept to
# pin down correct behaviour for this chain shape and catch unrelated
# regressions.

use lib 'lib';
use Test::Nginx::Socket;

plan tests => 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: last_buf flag lands on a non-head link of a multi-link chain
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
    load_module /etc/nginx/modules/ngx_http_echo_module.so;
--- config
    location /backend {
        default_type application/json;
        echo -n '{"greeting":"Hello, ';
        echo -n 'World!"}';
    }
    location /test {
        mustach_template "{{greeting}}";
        proxy_pass http://127.0.0.1:$server_port/backend;
    }
--- request
    GET /test
--- timeout: 3
--- response_body chop
Hello, World!
