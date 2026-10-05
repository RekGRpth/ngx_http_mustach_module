# ngx_http_mustach_module

An nginx module that renders [Mustache](https://mustache.github.io/) templates against JSON data, using the [mustach](https://gitlab.com/jobol/mustach) C library.

It can work two ways:

- **As a content handler** — a location renders a template against JSON coming from an nginx variable (`mustach_json`) and returns the result directly. No upstream/backend needed.
- **As a body filter** — a location's response is produced by something else (`proxy_pass`, `return`, a static file, ...); if that response comes back with `Content-Type: application/json`, this module buffers it, treats it as the data, and rewrites the body by rendering `mustach_template` against it.

## Directives

### mustach_template

- **syntax:** `mustach_template <text>;`
- **context:** `http`, `server`, `location`, `if in location`
- Sets the Mustache template. Required for both modes — it's what actually turns the module on (installing the body filter for the whole `http` block once any location uses it). The value is an [nginx complex value](https://nginx.org/en/docs/dev/development_guide.html#http_variables) and can reference variables, e.g. `mustach_template $tmpl;`.
- Inherited by nested locations unless overridden.

### mustach_json

- **syntax:** `mustach_json <text>;`
- **context:** `location`, `if in location`
- Sets the JSON data and switches the location into **content-handler mode**: this directive installs itself as the location's content handler, so the location no longer needs (or should have) another one like `proxy_pass` or `return`. Requires `mustach_template`, set in the same location or inherited — the module refuses to start otherwise, rather than crashing on the first request.
- Combining `mustach_json` with another directive that already claims the location's content handler (`proxy_pass`, `return`, ...) is a configuration error, whichever of the two is declared second.
- Like `proxy_pass`, not inherited by nested locations: each location that should render needs its own `mustach_json`. (Blocks such as `if` and `limit_except` inside the location do keep it.)

### mustach_content

- **syntax:** `mustach_content <text>;`
- **context:** `http`, `server`, `location`, `if in location`
- Overrides the `Content-Type` of the rendered response (e.g. `mustach_content text/html;`). Without it, the usual nginx `Content-Type` resolution applies (MIME type by extension, then `default_type`).
- Inherited by nested locations unless overridden.

### mustach_flags

- **syntax:** `mustach_flags flag ...;`
- **default:** all extensions enabled
- **context:** `http`, `server`, `location`, `if in location`
- Selects which [mustach extensions](https://gitlab.com/jobol/mustach) are active, as a space-separated list of: `allextensions`, `colon`, `compare`, `emptytag`, `equal`, `errorundefined`, `escfirstcmp`, `incpartial`, `jsonpointer`, `noextensions`, `objectiter`, `partialdatafirst`, `singledot`.
- Can only be given once per location (a second `mustach_flags` in the same location is a configuration error); inherited by nested locations that don't set their own.

### mustach_partials_root

- **syntax:** `mustach_partials_root path;`
- **default:** —
- **context:** `http`, `server`, `location`, `if in location`
- Lets partials (`{{> name}}`) be read from files in this directory: `path/name`, then `path/name.mustache`. A relative `path` is taken from the nginx prefix. `name` must be a single path component (no `/`, not `..`), so nothing outside the directory can be reached.
- Partials always come from the JSON data too: by default the data is tried first, the directory second; without `partialdatafirst` in `mustach_flags`, the other way round. Without this directive, partials come from the data only and no file is ever read — note that a partial taken from the data is itself a template, so letting it name arbitrary files would let the JSON read them.
- Files are read with blocking I/O on every render that uses them.
- Inherited by nested locations unless overridden.

### mustach_template_cache

- **syntax:** `mustach_template_cache <number>;`
- **default:** `256`
- **context:** `http`
- Templates are compiled once and reused rather than reparsed on every request. A literal `mustach_template` is compiled once at config load. A `mustach_template` sourced from a variable can differ per request, so compiled templates are kept in a bounded, per-worker LRU cache instead — this directive sets that cache's capacity (number of distinct compiled templates it holds at once). `0` disables the cache: a variable-sourced template is then compiled on every request and freed when the request ends. Doesn't apply to literal templates, which aren't cached this way in the first place.
- Can only be given once for the whole `http` block (a second `mustach_template_cache` is a configuration error).

## Examples

### Content-handler mode

```nginx
location /hello {
    mustach_template "Hello, {{name}}!";
    mustach_content  text/plain;
    mustach_json     '{"name":"World"}';
}
```

Typically the JSON comes from a variable instead of a literal, e.g. built with `set`/`ngx_http_evaluate_module`/the request body:

```nginx
location /hello {
    mustach_template "Hello, {{name}}!";
    mustach_content  text/plain;
    mustach_json     $arg_name_as_json;
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

Whatever `backend` returns is only rewritten if it comes back as `200` with `application/json` (optionally followed by `;` or a space, e.g. `application/json; charset=utf-8`) — any other `Content-Type`, and any other status (API errors, a `206` to a `Range` request, ...), passes through untouched.

## Building

Add it with `--add-module=path/to/ngx_http_mustach_module` (static) or `--add-dynamic-module=path/to/ngx_http_mustach_module` (dynamic) to nginx's `configure`.

The build always requires [libmustach](https://gitlab.com/jobol/mustach) itself, plus the vendored header-only JSON tokenizer ([jsmn.h](jsmn.h)) — no other JSON library needed.

## Testing

The test suite uses [Test::Nginx](https://metacpan.org/pod/Test::Nginx::Socket):

```sh
prove -r t/
```
