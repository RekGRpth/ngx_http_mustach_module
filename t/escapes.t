# vi:filetype=

use lib 'lib';
use Test::Nginx::Socket;

plan tests => repeat_each() * 2 * blocks();

no_shuffle();
run_tests();

__DATA__

=== TEST 1: decodes JSON string escapes delivered over the wire
# JSON string escapes (\n, \t, \") can't be tested via a literal in any
# nginx directive argument, including mustach_json and echo: nginx's own
# config-file lexer (ngx_conf_read_token) unescapes \n/\t/\"/\\/\' in
# directive values before this module ever sees them, so a config literal
# can't deliver a raw backslash-escape sequence for the jsmn backend to
# decode -- a general characteristic of nginx.conf, not specific to this
# module. --- user_files bypasses the config parser entirely (the content
# is written to disk as-is), so serving it as a static file and running it
# through the body-filter path (like split_body.t does) is the only way to
# deliver a literal backslash-escape here.
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /backend.json {
        default_type application/json;
        root html;
    }
    location /test {
        mustach_template "{{msg}}|{{emoji}}";
        proxy_pass http://127.0.0.1:$server_port/backend.json;
    }
--- user_files
>>> backend.json
{"msg":"line1\nline2\ttab\"quote\"","emoji":"😀"}
--- request
    GET /test
--- response_body chop
line1
line2	tab&quot;quote&quot;|😀
