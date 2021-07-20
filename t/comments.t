# vi:filetype=

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => repeat_each() * 2 * blocks();

#$Test::Nginx::LWP::LogLevel = 'debug';

run_tests();

__DATA__

=== TEST 1: Inline
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template '12345{{! Comment Block! }}67890';
        mustach_content text/html;
        return 200 '{}';
    }
--- request
    GET /mustach
--- response_body chop
1234567890
=== TEST 2: Multiline
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template '12345{{!\n  This is a\n  multi-line comment...\n}}67890\n';
        mustach_content text/html;
        return 200 '{}';
    }
--- request
    GET /mustach
--- response_body eval
"1234567890\n"
=== TEST 3: Standalone
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template 'Begin.\n{{! Comment Block! }}\nEnd.\n';
        mustach_content text/html;
        return 200 '{}';
    }
--- request
    GET /mustach
--- response_body eval
"Begin.\n\nEnd.\n"
=== TEST 4: Indented Standalone
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template 'Begin.\n  {{! Indented Comment Block! }}\nEnd.\n';
        mustach_content text/html;
        return 200 '{}';
    }
--- request
    GET /mustach
--- response_body eval
"Begin.\n  \nEnd.\n"
=== TEST 5: Standalone Line Endings
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template '|\r\n{{! Standalone Comment }}\r\n|';
        mustach_content text/html;
        return 200 '{}';
    }
--- request
    GET /mustach
--- response_body eval
"|\r\n\r\n|"
=== TEST 6: Standalone Without Previous Line
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "  {{! I'm Still Standalone }}\n!";
        mustach_content text/html;
        return 200 '{}';
    }
--- request
    GET /mustach
--- response_body eval
"  \n!"
=== TEST 7: Standalone Without Newline
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "!\n  {{! I'm Still Standalone }}";
        mustach_content text/html;
        return 200 '{}';
    }
--- request
    GET /mustach
--- response_body eval
"!\n  "
=== TEST 8: Multiline Standalone
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "Begin.\n{{!\nSomething's going on here...\n}}\nEnd.\n";
        mustach_content text/html;
        return 200 '{}';
    }
--- request
    GET /mustach
--- response_body eval
"Begin.\n\nEnd.\n"
=== TEST 9: Indented Multiline Standalone
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "Begin.\n  {{!\n    Something's going on here...\n  }}\nEnd.\n";
        mustach_content text/html;
        return 200 '{}';
    }
--- request
    GET /mustach
--- response_body eval
"Begin.\n  \nEnd.\n"
=== TEST 10: Indented Inline
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "  12 {{! 34 }}\n";
        mustach_content text/html;
        return 200 '{}';
    }
--- request
    GET /mustach
--- response_body eval
"  12 \n"
=== TEST 11: Surrounding Whitespace
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "12345 {{! Comment Block! }} 67890";
        mustach_content text/html;
        return 200 '{}';
    }
--- request
    GET /mustach
--- response_body eval
"12345  67890"
