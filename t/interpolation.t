# vi:filetype=

use lib 'lib';
use Test::Nginx::Socket;

repeat_each(2);

plan tests => repeat_each() * 2 * blocks();

#$Test::Nginx::LWP::LogLevel = 'debug';

run_tests();

__DATA__

=== TEST 1: No Interpolation
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "Hello from {Mustache}!\n";
        mustach_content text/html;
        return 200 '{
      }';
    }
--- request
    GET /mustach
--- response_body eval
"Hello from {Mustache}!\n"
=== TEST 2: Basic Interpolation
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "Hello, {{subject}}!\n";
        mustach_content text/html;
        return 200 '{
        "subject": "world"
      }';
    }
--- request
    GET /mustach
--- response_body eval
"Hello, world!\n"
=== TEST 3: HTML Escaping
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "These characters should be HTML escaped: {{forbidden}}\n";
        mustach_content text/html;
        return 200 '{
        "forbidden": "& \\" < >"
      }';
    }
--- request
    GET /mustach
--- response_body eval
"These characters should be HTML escaped: &amp; \" &lt; &gt;\n"
=== TEST 4: Triple Mustache
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "These characters should not be HTML escaped: {{{forbidden}}}\n";
        mustach_content text/html;
        return 200 '{
        "forbidden": "& \\" < >"
      }';
    }
--- request
    GET /mustach
--- response_body eval
"These characters should not be HTML escaped: & \" < >\n"
=== TEST 5: Ampersand
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "These characters should not be HTML escaped: {{&forbidden}}\n";
        mustach_content text/html;
        return 200 '{
        "forbidden": "& \\" < >"
      }';
    }
--- request
    GET /mustach
--- response_body eval
"These characters should not be HTML escaped: & \" < >\n"
=== TEST 6: Basic Integer Interpolation
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "\"{{mph}} miles an hour!\"";
        mustach_content text/html;
        return 200 '{
        "mph": 85
      }';
    }
--- request
    GET /mustach
--- response_body eval
"\"85 miles an hour!\""
=== TEST 7: Triple Mustache Integer Interpolation
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "\"{{{mph}}} miles an hour!\"";
        mustach_content text/html;
        return 200 '{
        "mph": 85
      }';
    }
--- request
    GET /mustach
--- response_body eval
"\"85 miles an hour!\""
=== TEST 8: Ampersand Integer Interpolation
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "\"{{&mph}} miles an hour!\"";
        mustach_content text/html;
        return 200 '{
        "mph": 85
      }';
    }
--- request
    GET /mustach
--- response_body eval
"\"85 miles an hour!\""
=== TEST 9: Basic Decimal Interpolation
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "\"{{power}} jiggawatts!\"";
        mustach_content text/html;
        return 200 '{
        "power": 1.21
      }';
    }
--- request
    GET /mustach
--- response_body eval
"\"1.21 jiggawatts!\""
=== TEST 10: Triple Mustache Decimal Interpolation
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "\"{{{power}}} jiggawatts!\"";
        mustach_content text/html;
        return 200 '{
        "power": 1.21
      }';
    }
--- request
    GET /mustach
--- response_body eval
"\"1.21 jiggawatts!\""
=== TEST 11: Ampersand Decimal Interpolation
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "\"{{&power}} jiggawatts!\"";
        mustach_content text/html;
        return 200 '{
        "power": 1.21
      }';
    }
--- request
    GET /mustach
--- response_body eval
"\"1.21 jiggawatts!\""
=== TEST 12: Basic Null Interpolation
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "I ({{cannot}}) be seen!";
        mustach_content text/html;
        return 200 '{
        "cannot": null
      }';
    }
--- request
    GET /mustach
--- response_body eval
"I (null) be seen!"
=== TEST 13: Triple Mustache Null Interpolation
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "I ({{{cannot}}}) be seen!";
        mustach_content text/html;
        return 200 '{
        "cannot": null
      }';
    }
--- request
    GET /mustach
--- response_body eval
"I (null) be seen!"
=== TEST 14: Ampersand Null Interpolation
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "I ({{&cannot}}) be seen!";
        mustach_content text/html;
        return 200 '{
        "cannot": null
      }';
    }
--- request
    GET /mustach
--- response_body eval
"I (null) be seen!"
=== TEST 15: Basic Context Miss Interpolation
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "I ({{cannot}}) be seen!";
        mustach_content text/html;
        return 200 '{
      }';
    }
--- request
    GET /mustach
--- response_body eval
"I () be seen!"
=== TEST 16: Triple Mustache Context Miss Interpolation
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "I ({{{cannot}}}) be seen!";
        mustach_content text/html;
        return 200 '{
      }';
    }
--- request
    GET /mustach
--- response_body eval
"I () be seen!"
=== TEST 17: Ampersand Context Miss Interpolation
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "I ({{&cannot}}) be seen!";
        mustach_content text/html;
        return 200 '{
      }';
    }
--- request
    GET /mustach
--- response_body eval
"I () be seen!"
=== TEST 18: Dotted Names - Basic Interpolation
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "\"{{person.name}}\" == \"{{#person}}{{name}}{{/person}}\"";
        mustach_content text/html;
        return 200 '{
        "person": {
          "name": "Joe"
        }
      }';
    }
--- request
    GET /mustach
--- response_body eval
"\"Joe\" == \"Joe\""
=== TEST 19: Dotted Names - Triple Mustache Interpolation
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "\"{{{person.name}}}\" == \"{{#person}}{{{name}}}{{/person}}\"";
        mustach_content text/html;
        return 200 '{
        "person": {
          "name": "Joe"
        }
      }';
    }
--- request
    GET /mustach
--- response_body eval
"\"Joe\" == \"Joe\""
=== TEST 20: Dotted Names - Ampersand Interpolation
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "\"{{&person.name}}\" == \"{{#person}}{{&name}}{{/person}}\"";
        mustach_content text/html;
        return 200 '{
        "person": {
          "name": "Joe"
        }
      }';
    }
--- request
    GET /mustach
--- response_body eval
"\"Joe\" == \"Joe\""
=== TEST 21: Dotted Names - Arbitrary Depth
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "\"{{a.b.c.d.e.name}}\" == \"Phil\"";
        mustach_content text/html;
        return 200 '{
        "a": {
          "b": {
            "c": {
              "d": {
                "e": {
                  "name": "Phil"
                }
              }
            }
          }
        }
      }';
    }
--- request
    GET /mustach
--- response_body eval
"\"Phil\" == \"Phil\""
=== TEST 22: Dotted Names - Broken Chains
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "\"{{a.b.c}}\" == \"\"";
        mustach_content text/html;
        return 200 '{
        "a": {
        }
      }';
    }
--- request
    GET /mustach
--- response_body eval
"\"\" == \"\""
=== TEST 23: Dotted Names - Broken Chain Resolution
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "\"{{a.b.c.name}}\" == \"\"";
        mustach_content text/html;
        return 200 '{
        "a": {
          "b": {
          }
        },
        "c": {
          "name": "Jim"
        }
      }';
    }
--- request
    GET /mustach
--- response_body eval
"\"\" == \"\""
=== TEST 24: Dotted Names - Initial Resolution
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "\"{{#a}}{{b.c.d.e.name}}{{/a}}\" == \"Phil\"";
        mustach_content text/html;
        return 200 '{
        "a": {
          "b": {
            "c": {
              "d": {
                "e": {
                  "name": "Phil"
                }
              }
            }
          }
        },
        "b": {
          "c": {
            "d": {
              "e": {
                "name": "Wrong"
              }
            }
          }
        }
      }';
    }
--- request
    GET /mustach
--- response_body eval
"\"Phil\" == \"Phil\""
=== TEST 25: Dotted Names - Context Precedence
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "{{#a}}{{b.c}}{{/a}} ";
        mustach_content text/html;
        return 200 '{
        "a": {
          "b": {
          }
        },
        "b": {
          "c": "ERROR"
        }
      }';
    }
--- request
    GET /mustach
--- response_body eval
" "
=== TEST 26: Implicit Iterators - Basic Interpolation
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "Hello, {{.}}!\n";
        mustach_content text/html;
        return 200 '"world"';
    }
--- request
    GET /mustach
--- response_body eval
"Hello, world!\n"
=== TEST 27: Implicit Iterators - HTML Escaping
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "These characters should be HTML escaped: {{.}}\n";
        mustach_content text/html;
        return 200 '"& \\" < >"';
    }
--- request
    GET /mustach
--- response_body eval
"These characters should be HTML escaped: &amp; \" &lt; &gt;\n"
=== TEST 28: Implicit Iterators - Triple Mustache
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "These characters should not be HTML escaped: {{{.}}}\n";
        mustach_content text/html;
        return 200 '"& \\" < >"';
    }
--- request
    GET /mustach
--- response_body eval
"These characters should not be HTML escaped: & \" < >\n"
=== TEST 29: Implicit Iterators - Ampersand
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "These characters should not be HTML escaped: {{&.}}\n";
        mustach_content text/html;
        return 200 '"& \\" < >"';
    }
--- request
    GET /mustach
--- response_body eval
"These characters should not be HTML escaped: & \" < >\n"
=== TEST 30: Implicit Iterators - Basic Integer Interpolation
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "\"{{.}} miles an hour!\"";
        mustach_content text/html;
        return 200 '"85"';
    }
--- request
    GET /mustach
--- response_body eval
"\"85 miles an hour!\""
=== TEST 31: Interpolation - Surrounding Whitespace
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "| {{string}} |";
        mustach_content text/html;
        return 200 '{
        "string": "---"
      }';
    }
--- request
    GET /mustach
--- response_body eval
"| --- |"
=== TEST 32: Triple Mustache - Surrounding Whitespace
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "| {{{string}}} |";
        mustach_content text/html;
        return 200 '{
        "string": "---"
      }';
    }
--- request
    GET /mustach
--- response_body eval
"| --- |"
=== TEST 33: Ampersand - Surrounding Whitespace
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "| {{&string}} |";
        mustach_content text/html;
        return 200 '{
        "string": "---"
      }';
    }
--- request
    GET /mustach
--- response_body eval
"| --- |"
=== TEST 34: Interpolation - Standalone
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "  {{string}}\n";
        mustach_content text/html;
        return 200 '{
        "string": "---"
      }';
    }
--- request
    GET /mustach
--- response_body eval
"  ---\n"
=== TEST 35: Triple Mustache - Standalone
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "  {{{string}}}\n";
        mustach_content text/html;
        return 200 '{
        "string": "---"
      }';
    }
--- request
    GET /mustach
--- response_body eval
"  ---\n"
=== TEST 36: Ampersand - Standalone
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "  {{&string}}\n";
        mustach_content text/html;
        return 200 '{
        "string": "---"
      }';
    }
--- request
    GET /mustach
--- response_body eval
"  ---\n"
=== TEST 37: Interpolation With Padding
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "|{{ string }}|";
        mustach_content text/html;
        return 200 '{
        "string": "---"
      }';
    }
--- request
    GET /mustach
--- response_body eval
"|---|"
=== TEST 38: Triple Mustache With Padding
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "|{{{ string }}}|";
        mustach_content text/html;
        return 200 '{
        "string": "---"
      }';
    }
--- request
    GET /mustach
--- response_body eval
"|---|"
=== TEST 39: Ampersand With Padding
--- main_config
    load_module /etc/nginx/modules/ngx_http_mustach_module.so;
--- config
    location /mustach {
        default_type application/json;
        mustach_template "|{{& string }}|";
        mustach_content text/html;
        return 200 '{
        "string": "---"
      }';
    }
--- request
    GET /mustach
--- response_body eval
"|---|"
