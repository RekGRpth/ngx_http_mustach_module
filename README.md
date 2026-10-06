# ngx_http_mustach_module

An nginx module that renders [Mustache](https://mustache.github.io/) templates against JSON data, using the [mustach](https://gitlab.com/jobol/mustach) C library.

It can work two ways:

- **As a content handler** — a location renders a template against JSON given by `mustach_json` (a literal, a variable, the request body, ...) and returns the result directly. No upstream/backend needed.
- **As a body filter** — a location's response is produced by something else (`proxy_pass`, a static file, `return`, a cache hit, ...); if that response is a `200` with `Content-Type: application/json`, this module buffers it, treats it as the data, and rewrites the body by rendering `mustach_template` against it. See [How body-filter mode decides](#how-body-filter-mode-decides).

Both modes also work inside subrequests, e.g. an SSI `<!--# include virtual="..." -->` of a location that renders.

## Directives

### mustach_template

- **syntax:** `mustach_template <text>;`
- **context:** `http`, `server`, `location`, `if in location`
- Sets the Mustache template. Required for both modes — it's what actually turns the module on (installing the body filter for the whole `http` block once any location uses it). The value is an [nginx complex value](https://nginx.org/en/docs/dev/development_guide.html#http_variables) and can reference variables, e.g. `mustach_template $tmpl;`.
- `mustach_template "";` turns rendering off in a location, e.g. in a nested location that would otherwise inherit a template: responses there pass through untouched. A template from a variable that comes out empty does the same for that response in body-filter mode, so a `map` can switch rendering per request:

  ```nginx
  map $arg_raw $page_tmpl { 1 ""; default "<h1>{{title}}</h1>"; }
  ```

  In content-handler mode there is no response to fall back to: an empty template there gives a 500 (and `mustach_json` next to `mustach_template "";` is a configuration error).
- A literal template is compiled once, at configuration load: a syntax error in it stops nginx from starting (or a reload from being applied). A template taken from a variable is compiled when used, and kept in a per-worker cache (see `mustach_template_cache`).
- Inherited by nested locations unless overridden.

### mustach_json

- **syntax:** `mustach_json <text>;`
- **context:** `location`, `if in location`
- Sets the JSON data and switches the location into **content-handler mode**: this directive installs itself as the location's content handler. Requires `mustach_template`, set in the same location or inherited — the module refuses to start otherwise, rather than crashing on the first request.
- Combining it with another content handler such as `proxy_pass` or `fastcgi_pass` is a configuration error, whichever of the two comes first. `return` isn't a content handler — it runs earlier, in the rewrite phase — so it isn't caught: in a location with both, `return` answers (and its response is then rendered in body-filter mode if it's JSON).
- Like `proxy_pass`, not inherited by nested locations: each location that should render needs its own `mustach_json`. (Blocks such as `if` and `limit_except` inside the location do keep it.)
- The request body is read before rendering (subject to `client_max_body_size`), so the data can come from it: `mustach_json $request_body;`. `$request_body` is empty once the body is written to a temporary file, so make `client_body_buffer_size` as large as the bodies you expect; the module logs a warning when the data comes out empty because of this.
- The response is always a `200`.

### mustach_content

- **syntax:** `mustach_content <text>;`
- **context:** `http`, `server`, `location`, `if in location`
- Overrides the `Content-Type` of the rendered response (e.g. `mustach_content text/html;`). Without it, the usual nginx `Content-Type` resolution applies (MIME type by extension, then `default_type`) — in body-filter mode, that leaves the upstream's `application/json`.
- Inherited by nested locations unless overridden.

### mustach_data_partials_limit

- **syntax:** `mustach_data_partials_limit size;`
- **default:** `1m`
- **context:** `http`, `server`, `location`, `if in location`
- A per-render budget for partial lookups in the JSON data. Every `{{> name}}` that looks in the data is charged 64 bytes — whether or not the name is found there, and so also when the partial then comes from a file under `mustach_partials_root` (by default the data is looked at first) — and a partial found in the data is charged its length when that is more. Once the budget runs out, rendering stops and the request gets a 500. A partial from the data is a template the JSON supplies, and lookups cost work and memory even when they output nothing, so this bounds what the data can make a render do. `0` lifts the limit. The contents of partials from files, and the template itself, aren't charged.
- So a page that uses a partial per item of a list needs at least 64 bytes of budget per item: the default `1m` covers about 16,000.
- Inherited by nested locations unless overridden.

### mustach_flags

- **syntax:** `mustach_flags flag ...;`
- **default:** all extensions enabled, except `errorundefined`
- **context:** `http`, `server`, `location`, `if in location`
- Selects which [mustach extensions](https://gitlab.com/jobol/mustach) are active, as a space-separated list of: `allextensions`, `colon`, `compare`, `emptytag`, `equal`, `errorundefined`, `escfirstcmp`, `incpartial`, `jsonpointer`, `noextensions`, `objectiter`, `partialdatafirst`, `singledot`.
- Can only be given once per location (a second `mustach_flags` in the same location is a configuration error); inherited by nested locations that don't set their own.

### mustach_max_json_size

- **syntax:** `mustach_max_json_size size;`
- **default:** `1m`
- **context:** `http`, `server`, `location`, `if in location`
- In body-filter mode, the largest upstream JSON the module will hold in memory to render (like `image_filter_buffer`). A larger response gets a 500 — right away when its `Content-Length` says so, or as soon as it's grown past the limit otherwise. `0` lifts the limit. (In content-handler mode, a request body is bounded by `client_max_body_size`.)
- Inherited by nested locations unless overridden.

### mustach_max_output_size

- **syntax:** `mustach_max_output_size size;`
- **default:** `10m`
- **context:** `http`, `server`, `location`, `if in location`
- The largest page a render may produce, in both modes. Rendering stops as soon as the output grows past it, and the request gets a 500. A template's output can be far larger than its data — partials taken from the data are templates too — so this bounds the size of the page a single render can build; the work partials from the data take is bounded by `mustach_data_partials_limit`. `0` lifts the limit.
- Inherited by nested locations unless overridden.

### mustach_partials_root

- **syntax:** `mustach_partials_root path;`
- **default:** —
- **context:** `http`, `server`, `location`, `if in location`
- Lets partials (`{{> name}}`) be read from files in this directory: `path/name`, then `path/name.mustache`. A relative `path` is taken from the nginx prefix. `name` must be a single path component (no `/`, not `..`), so nothing outside the directory can be reached.
- Partials always come from the JSON data too: by default the data is tried first, the directory second; without `partialdatafirst` in `mustach_flags`, the other way round. Without this directive, partials come from the data only and no file is ever read — note that a partial taken from the data is itself a template, so letting it name arbitrary files would let the JSON read them.
- Files are read with blocking I/O on every render that uses them.
- A partial taken from the data may be at most 64k: it is a template the JSON supplies, and a longer one is refused (500) rather than risk a tag name overflowing the worker's stack inside libmustach. Partials from files are not limited.
- Inherited by nested locations unless overridden.

### mustach_template_cache

- **syntax:** `mustach_template_cache <number>;`
- **default:** `256`
- **context:** `http`
- Templates are compiled once and reused rather than reparsed on every request. A literal `mustach_template` is compiled once at config load. A `mustach_template` sourced from a variable can differ per request, so compiled templates are kept in a bounded, per-worker LRU cache instead — this directive sets that cache's capacity (number of distinct compiled templates it holds at once). `0` disables the cache: a variable-sourced template is then compiled on every request and freed when the request ends. Templates larger than 64k are never cached, but compiled per request that way, so the cache holds at most this many entries of at most 64k each. Doesn't apply to literal templates, which aren't cached this way in the first place.
- Can only be given once for the whole `http` block (a second `mustach_template_cache` is a configuration error).

## How body-filter mode decides

In a location with `mustach_template` (and no `mustach_json`), a response is rendered only if all of these hold; otherwise it passes through untouched, headers and body:

- its status is `200` — API errors, redirects, a `206` to a `Range` request, ... are left alone;
- its `Content-Type` is `application/json`, optionally followed by `;` or a space (e.g. `application/json; charset=utf-8`);
- it isn't compressed: a response with a `Content-Encoding` (other than `identity`) can't be parsed here, so it passes through and the module logs a warning — see the example below.

A rendered response gets a fresh `Content-Length`, a weakened `ETag`, no `Accept-Ranges`, and the `Content-Type` from `mustach_content` if set. A `HEAD` request gets the same headers as the corresponding `GET` would, without a `Content-Length` when the body never arrived (e.g. through a proxy). A `200` JSON response with an empty body passes through as is.

Static files, `sendfile`, and responses served from `proxy_cache` are rendered like any other response. A response fetched by the `slice` module never is, even when it fits in one slice: its pieces arrive through subrequests, so the JSON doesn't come together in one place. Such a response passes through as it is, whatever its size, with a warning in the error log; other subrequests (SSI includes, `add_after_body`, ...) are rendered as usual.

## Errors and limits

- Invalid JSON, a template error, a partial from the data over 64k, partials from the data over `mustach_data_partials_limit`, an output over `mustach_max_output_size` or an upstream JSON over `mustach_max_json_size` all give a `500` and a line in the error log saying what went wrong.
- In body-filter mode the module holds the upstream response's header back until the body has been rendered, so it can still answer with a proper `500` page.
- A template that renders to nothing gives an empty `200` (`Content-Length: 0`).

## Examples

### Content-handler mode

```nginx
location /hello {
    mustach_template "Hello, {{name}}!";
    mustach_content  text/plain;
    mustach_json     '{"name":"World"}';
}
```

Typically the JSON comes from a variable instead of a literal — the request body, a variable built with `set` or another module, ...:

```nginx
location /render {
    client_body_buffer_size 64k;   # keep bodies in memory, where $request_body can see them
    mustach_template "Hello, {{name}}!";
    mustach_content  text/plain;
    mustach_json     $request_body;
}
```

### Body-filter mode

```nginx
location /api/ {
    mustach_template '<h1>{{title}}</h1>';
    mustach_content  text/html;
    proxy_pass       http://backend;
}
```

`proxy_pass` forwards the client's `Accept-Encoding`, so a backend that compresses JSON will do so for any browser, and those responses would pass through unrendered — have it send the data uncompressed:

```nginx
location /api/ {
    mustach_template  '<h1>{{title}}</h1>';
    mustach_content   text/html;
    proxy_set_header  Accept-Encoding "";
    proxy_pass        http://backend;
}
```

The rendered page itself can still be compressed on the way out with `gzip on;`.

### Partials

```nginx
location /list {
    mustach_template      '<ul>{{#items}}{{> item}}{{/items}}</ul>';
    mustach_content       text/html;
    mustach_partials_root /etc/nginx/mustache;   # item, or item.mustache, from here
    # each {{> item}} also costs 64 bytes of mustach_data_partials_limit (1m: ~16,000 items)
    proxy_pass            http://backend;
}
```

## Building

Add it with `--add-module=path/to/ngx_http_mustach_module` (static) or `--add-dynamic-module=path/to/ngx_http_mustach_module` (dynamic) to nginx's `configure`.

The build requires [libmustach](https://gitlab.com/jobol/mustach) 2.x (it uses the compiled-template API: `mustach_make_template`, `mustach_wrap_apply`), linked as `-lmustach`. JSON is parsed by the vendored header-only tokenizer [jsmn.h](jsmn.h) — no other JSON library needed. That copy carries a local change, marked in the file, that keeps parsing linear on deeply nested input.

## Testing

The test suite uses [Test::Nginx](https://metacpan.org/pod/Test::Nginx::Socket). Run it from the repository root (some tests read fixture partials from there):

```sh
prove -r t/
```

The tests load the module from `/etc/nginx/modules/ngx_http_mustach_module.so`, so install the build you want to test there first. A few tests also load `ngx_http_echo_module.so` and `ngx_http_evaluate_module.so` from the same directory.
