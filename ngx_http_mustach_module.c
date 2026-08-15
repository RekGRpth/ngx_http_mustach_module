#include <nginx.h>
#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <stddef.h>
#include <stdio.h>

#include <mustach/mustach.h>
#include <mustach/mustach-wrap.h>

int mustach_build_jsmn(const char *template, size_t length, int flags, mustach_template_t **templ, char **err);
int mustach_apply_jsmn(mustach_template_t *templ, const char *json, size_t jsonlen, int flags, FILE *file, char **err, ngx_pool_t *pool);

typedef struct {
    ngx_chain_t *cl;
    ngx_flag_t done;
} ngx_http_mustach_context_t;

typedef struct {
    ngx_flag_t enable;
    ngx_int_t cache_size;
} ngx_http_mustach_main_t;

typedef struct {
    ngx_http_complex_value_t *content;
    ngx_http_complex_value_t *json;
    ngx_http_complex_value_t *template;
    ngx_uint_t flags;
    mustach_template_t *compiled; /* set when `template` is a constant, built once at config time */
} ngx_http_mustach_location_t;

ngx_module_t ngx_http_mustach_module;

static ngx_http_output_header_filter_pt ngx_http_next_header_filter;
static ngx_http_output_body_filter_pt ngx_http_next_body_filter;

static char *ngx_http_mustach_flags_conf(ngx_conf_t *cf, ngx_command_t *cmd, void *conf) {
    ngx_http_mustach_location_t *location = conf;
    if (location->flags != NGX_CONF_UNSET_UINT) return "is duplicate";
    ngx_str_t *args = cf->args->elts;
    static const ngx_conf_enum_t e[] = {
        { ngx_string("allextensions"), Mustach_With_AllExtensions },
        { ngx_string("colon"), Mustach_With_Colon },
        { ngx_string("compare"), Mustach_With_Compare },
        { ngx_string("emptytag"), Mustach_With_EmptyTag },
        { ngx_string("equal"), Mustach_With_Equal },
        { ngx_string("errorundefined"), Mustach_With_ErrorUndefined },
        { ngx_string("escfirstcmp"), Mustach_With_EscFirstCmp },
        { ngx_string("incpartial"), Mustach_With_IncPartial },
        { ngx_string("jsonpointer"), Mustach_With_JsonPointer },
        { ngx_string("noextensions"), Mustach_With_NoExtensions },
        { ngx_string("objectiter"), Mustach_With_ObjectIter },
        { ngx_string("partialdatafirst"), Mustach_With_PartialDataFirst },
        { ngx_string("singledot"), Mustach_With_SingleDot },
        { ngx_null_string, 0 }
    };
    location->flags = Mustach_With_NoExtensions;
    for (ngx_uint_t i = 1; i < cf->args->nelts; i++) {
        ngx_uint_t j;
        for (j = 0; e[j].name.len; j++) if (e[j].name.len == args[i].len && !ngx_strncmp(e[j].name.data, args[i].data, args[i].len)) { location->flags |= e[j].value; break; }
        if (!e[j].name.len) { ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "\"%V\" directive error: value \"%V\" must be \"allextensions\", \"colon\", \"compare\", \"emptytag\", \"equal\", \"errorundefined\", \"escfirstcmp\", \"incpartial\", \"jsonpointer\", \"noextensions\", \"objectiter\", \"partialdatafirst\" or \"singledot\"", &cmd->name, &args[i]); return NGX_CONF_ERROR; }
    }
    return NGX_CONF_OK;
}

static void ngx_http_mustach_log_error(ngx_http_request_t *r, int rc, const char *err) {
    switch (rc) {
        case MUSTACH_OK: return;
        case MUSTACH_ERROR_SYSTEM: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_SYSTEM"); return;
        case MUSTACH_ERROR_UNEXPECTED_END: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_UNEXPECTED_END"); return;
        case MUSTACH_ERROR_EMPTY_TAG: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_EMPTY_TAG"); return;
#if MUSTACH_VERSION >= 200
        case MUSTACH_ERROR_TOO_BIG: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_TOO_BIG"); return;
#else
        case MUSTACH_ERROR_TAG_TOO_LONG: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_TAG_TOO_LONG"); return;
#endif
#if MUSTACH_VERSION >= 200
        case MUSTACH_ERROR_BAD_DELIMITER: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_BAD_DELIMITER"); return;
#else
        case MUSTACH_ERROR_BAD_SEPARATORS: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_BAD_SEPARATORS"); return;
#endif
        case MUSTACH_ERROR_TOO_DEEP: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_TOO_DEEP"); return;
        case MUSTACH_ERROR_CLOSING: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_CLOSING"); return;
        case MUSTACH_ERROR_BAD_UNESCAPE_TAG: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_BAD_UNESCAPE_TAG"); return;
        case MUSTACH_ERROR_INVALID_ITF: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_INVALID_ITF"); return;
#if MUSTACH_VERSION >= 200
        case MUSTACH_ERROR_NOT_FOUND: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_NOT_FOUND"); return;
#else
        case MUSTACH_ERROR_ITEM_NOT_FOUND: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_ITEM_NOT_FOUND"); return;
        case MUSTACH_ERROR_PARTIAL_NOT_FOUND: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_PARTIAL_NOT_FOUND"); return;
#endif
        case MUSTACH_ERROR_UNDEFINED_TAG: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_UNDEFINED_TAG"); return;
        case MUSTACH_ERROR_TOO_MUCH_NESTING: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_TOO_MUCH_NESTING"); return;
#if MUSTACH_VERSION >= 200
        case MUSTACH_ERROR_OUT_OF_MEMORY: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_OUT_OF_MEMORY"); return;
#endif
        default: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "%s", err); return;
    }
}

/* Per-worker cache of compiled templates, for the case where `mustach_template`
 * comes from a variable and so can differ per request. Plain process memory,
 * no locking: each worker is single-threaded, and a cold cache after reload
 * (a new worker starts with none of this) is fine -- same tradeoff nginx's
 * own open_file_cache makes. Bounded by an LRU so an attacker-controlled
 * variable can't grow it without limit. */
#define NGX_HTTP_MUSTACH_CACHE_BUCKETS 61

typedef struct ngx_http_mustach_cache_entry_s ngx_http_mustach_cache_entry_t;

struct ngx_http_mustach_cache_entry_s {
    ngx_http_mustach_cache_entry_t *hnext;
    ngx_http_mustach_cache_entry_t *lru_prev;
    ngx_http_mustach_cache_entry_t *lru_next;
    uint32_t hash;
    ngx_uint_t bflags;
    ngx_str_t text;
    mustach_template_t *compiled;
};

static ngx_http_mustach_cache_entry_t *ngx_http_mustach_cache_buckets[NGX_HTTP_MUSTACH_CACHE_BUCKETS];
static ngx_http_mustach_cache_entry_t *ngx_http_mustach_cache_lru_head;
static ngx_http_mustach_cache_entry_t *ngx_http_mustach_cache_lru_tail;
static ngx_uint_t ngx_http_mustach_cache_count;

static void ngx_http_mustach_cache_unlink_lru(ngx_http_mustach_cache_entry_t *e) {
    if (e->lru_prev) e->lru_prev->lru_next = e->lru_next; else ngx_http_mustach_cache_lru_head = e->lru_next;
    if (e->lru_next) e->lru_next->lru_prev = e->lru_prev; else ngx_http_mustach_cache_lru_tail = e->lru_prev;
}

static void ngx_http_mustach_cache_push_front(ngx_http_mustach_cache_entry_t *e) {
    e->lru_prev = NULL;
    e->lru_next = ngx_http_mustach_cache_lru_head;
    if (ngx_http_mustach_cache_lru_head) ngx_http_mustach_cache_lru_head->lru_prev = e;
    ngx_http_mustach_cache_lru_head = e;
    if (!ngx_http_mustach_cache_lru_tail) ngx_http_mustach_cache_lru_tail = e;
}

static void ngx_http_mustach_cache_free_entry(ngx_http_mustach_cache_entry_t *e) {
    mustach_destroy_template(e->compiled, NULL, NULL);
    ngx_free(e->text.data);
    ngx_free(e);
}

static ngx_int_t ngx_http_mustach_cache_get(ngx_http_request_t *r, ngx_str_t text, ngx_uint_t flags, mustach_template_t **out) {
    ngx_http_mustach_main_t *main = ngx_http_get_module_main_conf(r, ngx_http_mustach_module);
    ngx_http_mustach_cache_entry_t *e, *victim, **pp;
    ngx_uint_t bflags = 0, bucket, vbucket;
    uint32_t hash;
    char *err;
    int rc;
    mustach_template_t *compiled;
    u_char *data;

    if (flags & Mustach_With_Colon) bflags |= 1;
    if (flags & Mustach_With_EmptyTag) bflags |= 2;

    hash = ngx_crc32_long(text.data, text.len);
    bucket = (hash ^ bflags) % NGX_HTTP_MUSTACH_CACHE_BUCKETS;

    for (e = ngx_http_mustach_cache_buckets[bucket]; e; e = e->hnext) {
        if (e->hash == hash && e->bflags == bflags && e->text.len == text.len && !ngx_memcmp(e->text.data, text.data, text.len)) {
            if (e != ngx_http_mustach_cache_lru_head) {
                ngx_http_mustach_cache_unlink_lru(e);
                ngx_http_mustach_cache_push_front(e);
            }
            *out = e->compiled;
            return NGX_OK;
        }
    }

    if (!(e = ngx_alloc(sizeof(*e), r->connection->log))) return NGX_ERROR;
    if (!(data = ngx_alloc(text.len ? text.len : 1, r->connection->log))) { ngx_free(e); return NGX_ERROR; }
    ngx_memcpy(data, text.data, text.len);
    /* compile from the cache's own copy: the compiled template keeps pointers
     * into whatever buffer it's built from, and this copy -- unlike `text`,
     * which may live in the request pool -- stays alive for as long as the
     * cache entry does. */
    if ((rc = mustach_build_jsmn((const char *)data, text.len, flags, &compiled, &err)) != MUSTACH_OK) { ngx_http_mustach_log_error(r, rc, err); ngx_free(data); ngx_free(e); return NGX_ERROR; }

    e->hash = hash;
    e->bflags = bflags;
    e->text.data = data;
    e->text.len = text.len;
    e->compiled = compiled;
    e->hnext = ngx_http_mustach_cache_buckets[bucket];
    ngx_http_mustach_cache_buckets[bucket] = e;
    ngx_http_mustach_cache_push_front(e);
    ngx_http_mustach_cache_count++;

    if ((ngx_int_t) ngx_http_mustach_cache_count > main->cache_size) {
        victim = ngx_http_mustach_cache_lru_tail;
        ngx_http_mustach_cache_unlink_lru(victim);
        vbucket = (victim->hash ^ victim->bflags) % NGX_HTTP_MUSTACH_CACHE_BUCKETS;
        for (pp = &ngx_http_mustach_cache_buckets[vbucket]; *pp != victim; pp = &(*pp)->hnext);
        *pp = victim->hnext;
        ngx_http_mustach_cache_free_entry(victim);
        ngx_http_mustach_cache_count--;
    }

    *out = compiled;
    return NGX_OK;
}

static ngx_buf_t *ngx_http_mustach_process(ngx_http_request_t *r, ngx_str_t json) {
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0, "%s", __func__);
    ngx_http_clear_accept_ranges(r);
    ngx_http_clear_content_length(r);
    ngx_http_weak_etag(r);
    ngx_http_mustach_location_t *location = ngx_http_get_module_loc_conf(r, ngx_http_mustach_module);
    if (location->content && ngx_http_complex_value(r, location->content, &r->headers_out.content_type) != NGX_OK) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "ngx_http_complex_value != NGX_OK"); return NULL; }
    if (ngx_http_set_content_type(r) != NGX_OK) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "ngx_http_set_content_type != NGX_OK"); return NULL; }
    r->headers_out.content_type_len = r->headers_out.content_type.len;
    mustach_template_t *templ;
    if (location->compiled) {
        templ = location->compiled;
    } else {
        ngx_str_t template;
        if (ngx_http_complex_value(r, location->template, &template) != NGX_OK) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "ngx_http_complex_value != NGX_OK"); return NULL; }
        if (!template.len) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!template.len"); return NULL; }
        if (ngx_http_mustach_cache_get(r, template, location->flags, &templ) != NGX_OK) return NULL;
    }
    ngx_str_t output = ngx_null_string;
    FILE *out = open_memstream((char **)&output.data, &output.len);
    if (!out) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!open_memstream"); return NULL; }
    ngx_buf_t *b = NULL;
    char *err;
    int rc = mustach_apply_jsmn(templ, (const char *)json.data, json.len, location->flags, out, &err, r->pool);
    if (rc != MUSTACH_OK) { ngx_http_mustach_log_error(r, rc, err); goto free; }
    if (!(b = ngx_create_temp_buf(r->pool, output.len))) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!ngx_create_temp_buf"); goto free; }
    b->last_buf = 1;
    b->last = ngx_copy(b->last, output.data, output.len);
    if (b->last != b->end) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "b->last != b->end"); goto free; }
    if (r == r->main) {
        r->headers_out.content_length_n = b->last - b->pos;
        if (r->headers_out.content_length) {
            r->headers_out.content_length->hash = 0;
            r->headers_out.content_length = NULL;
        }
        ngx_http_weak_etag(r);
    }
free:
    free(output.data);
    return b;
}

static ngx_int_t ngx_http_mustach_handler(ngx_http_request_t *r) {
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0, "%s", __func__);
    ngx_int_t rc = ngx_http_discard_request_body(r);
    if (rc != NGX_OK && rc != NGX_AGAIN) return rc;
    ngx_http_mustach_location_t *location = ngx_http_get_module_loc_conf(r, ngx_http_mustach_module);
    ngx_str_t json;
    if (ngx_http_complex_value(r, location->json, &json) != NGX_OK) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "ngx_http_complex_value != NGX_OK"); return NGX_HTTP_INTERNAL_SERVER_ERROR; }
    ngx_chain_t cl = {.buf = ngx_http_mustach_process(r, json), .next = NULL};
    if (!cl.buf) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!cl.buf"); return NGX_HTTP_INTERNAL_SERVER_ERROR; }
    r->headers_out.status = NGX_HTTP_OK;
    rc = ngx_http_send_header(r);
    if (rc == NGX_ERROR || rc > NGX_OK || r->header_only) return rc;
    return ngx_http_output_filter(r, &cl);
}

static char *ngx_http_set_complex_value_slot_enable(ngx_conf_t *cf, ngx_command_t *cmd, void *conf) {
    ngx_http_mustach_main_t *main = ngx_http_conf_get_module_main_conf(cf, ngx_http_mustach_module);
    main->enable = 1;
    return ngx_http_set_complex_value_slot(cf, cmd, conf);
}

static char *ngx_http_set_complex_value_slot_handler(ngx_conf_t *cf, ngx_command_t *cmd, void *conf) {
    ngx_http_core_loc_conf_t *core = ngx_http_conf_get_module_loc_conf(cf, ngx_http_core_module);
    if (core->handler && core->handler != ngx_http_mustach_handler) { ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "\"%V\" directive conflicts with another content handler already set for this location", &cmd->name); return NGX_CONF_ERROR; }
    core->handler = ngx_http_mustach_handler;
    return ngx_http_set_complex_value_slot(cf, cmd, conf);
}

static ngx_command_t ngx_http_mustach_commands[] = {
  { .name = ngx_string("mustach_content"),
    .type = NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF|NGX_CONF_TAKE1,
    .set = ngx_http_set_complex_value_slot,
    .conf = NGX_HTTP_LOC_CONF_OFFSET,
    .offset = offsetof(ngx_http_mustach_location_t, content),
    .post = NULL },
  { .name = ngx_string("mustach_flags"),
    .type = NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF|NGX_CONF_1MORE,
    .set = ngx_http_mustach_flags_conf,
    .conf = NGX_HTTP_LOC_CONF_OFFSET,
    .offset = offsetof(ngx_http_mustach_location_t, flags),
    .post = NULL },
  { .name = ngx_string("mustach_json"),
    .type = NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF|NGX_CONF_TAKE1,
    .set = ngx_http_set_complex_value_slot_handler,
    .conf = NGX_HTTP_LOC_CONF_OFFSET,
    .offset = offsetof(ngx_http_mustach_location_t, json),
    .post = NULL },
  { .name = ngx_string("mustach_template"),
    .type = NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF|NGX_CONF_TAKE1,
    .set = ngx_http_set_complex_value_slot_enable,
    .conf = NGX_HTTP_LOC_CONF_OFFSET,
    .offset = offsetof(ngx_http_mustach_location_t, template),
    .post = NULL },
  { .name = ngx_string("mustach_template_cache"),
    .type = NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE1,
    .set = ngx_conf_set_num_slot,
    .conf = NGX_HTTP_MAIN_CONF_OFFSET,
    .offset = offsetof(ngx_http_mustach_main_t, cache_size),
    .post = NULL },
    ngx_null_command
};

static void *ngx_http_mustach_create_main_conf(ngx_conf_t *cf) {
    ngx_http_mustach_main_t *main = ngx_pcalloc(cf->pool, sizeof(*main));
    if (!main) return NULL;
    main->cache_size = NGX_CONF_UNSET;
    return main;
}

static char *ngx_http_mustach_init_main_conf(ngx_conf_t *cf, void *conf) {
    ngx_http_mustach_main_t *main = conf;
    ngx_conf_init_value(main->cache_size, 256);
    return NGX_CONF_OK;
}

static void *ngx_http_mustach_create_loc_conf(ngx_conf_t *cf) {
    ngx_http_mustach_location_t *location = ngx_pcalloc(cf->pool, sizeof(*location));
    if (!location) return NULL;
    location->flags = NGX_CONF_UNSET_UINT;
    return location;
}

static char *ngx_http_mustach_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child) {
    ngx_http_mustach_location_t *prev = parent;
    ngx_http_mustach_location_t *conf = child;
    if (!conf->content) conf->content = prev->content;
    if (!conf->json) conf->json = prev->json;
    if (!conf->template) conf->template = prev->template;
    if (conf->json && !conf->template) { ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "\"mustach_json\" requires \"mustach_template\" to be set in the same location"); return NGX_CONF_ERROR; }
    ngx_conf_merge_uint_value(conf->flags, prev->flags, Mustach_With_AllExtensions);
    if (conf->template && conf->template->lengths == NULL && conf->template->value.len) {
        char *err;
        if (mustach_build_jsmn((const char *)conf->template->value.data, conf->template->value.len, conf->flags, &conf->compiled, &err) != MUSTACH_OK) {
            ngx_conf_log_error(NGX_LOG_EMERG, cf, 0, "\"mustach_template\" error: %s", err);
            return NGX_CONF_ERROR;
        }
    }
    return NGX_CONF_OK;
}

static ngx_int_t ngx_http_mustach_header_filter(ngx_http_request_t *r) {
    ngx_http_mustach_location_t *location = ngx_http_get_module_loc_conf(r, ngx_http_mustach_module);
    if (!location->template) return ngx_http_next_header_filter(r);
    size_t len = sizeof("application/json") - 1;
    u_char *p = r->headers_out.content_type.data;
    if (!(r->headers_out.content_type.len >= len && !ngx_strncasecmp(p, (u_char *)"application/json", len) && (r->headers_out.content_type.len == len || p[len] == ';' || p[len] == ' '))) return ngx_http_next_header_filter(r);
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0, "%s", __func__);
    ngx_http_mustach_context_t *context = ngx_pcalloc(r->pool, sizeof(*context));
    if (!context) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!ngx_pcalloc"); return NGX_ERROR; }
    ngx_http_set_ctx(r, context, ngx_http_mustach_module);
    return NGX_OK;
}

static ngx_int_t ngx_chain_add_copy_buf(ngx_pool_t *pool, ngx_chain_t **chain, ngx_chain_t *in) {
    ngx_chain_t *cl, **ll = chain;
    ngx_int_t rc = NGX_ERROR;
    for (cl = *chain; cl; cl = cl->next) ll = &cl->next;
    while (in) {
        size_t size = in->buf->last - in->buf->pos;
        if (!(cl = ngx_alloc_chain_link(pool))) goto ret;
        if (!(cl->buf = ngx_create_temp_buf(pool, size))) goto ret;
        cl->buf->last = ngx_cpymem(cl->buf->pos, in->buf->pos, size);
        in->buf->pos = in->buf->last;
        *ll = cl;
        ll = &cl->next;
        in = in->next;
    }
    rc = NGX_OK;
ret:
    *ll = NULL;
    return rc;
}

static ngx_int_t ngx_http_mustach_body_filter(ngx_http_request_t *r, ngx_chain_t *in) {
    if (!in) return ngx_http_next_body_filter(r, in);
    ngx_http_mustach_context_t *context = ngx_http_get_module_ctx(r, ngx_http_mustach_module);
    ngx_http_mustach_location_t *location = ngx_http_get_module_loc_conf(r, ngx_http_mustach_module);
    if (!location->template || !context || context->done) return ngx_http_next_body_filter(r, in);
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0, "%s", __func__);
    ngx_chain_t *last;
    for (last = in; last->next; last = last->next);
    if (!last->buf->last_buf && !last->buf->last_in_chain) {
        if (ngx_chain_add_copy_buf(r->pool, &context->cl, in) != NGX_OK) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "ngx_chain_add_copy_buf != NGX_OK"); return NGX_HTTP_INTERNAL_SERVER_ERROR; }
        return NGX_OK;
    }
    if (context->cl) {
        ngx_chain_t *tail;
        for (tail = context->cl; tail->next; tail = tail->next);
        tail->next = in;
    }
    ngx_str_t json = ngx_null_string;
    for (ngx_chain_t *cl = context->cl ? context->cl : in; cl; cl = cl->next) {
        if (!ngx_buf_in_memory(cl->buf)) continue;
        json.len += cl->buf->last - cl->buf->pos;
    }
    if (!json.len) return ngx_http_next_body_filter(r, in);
    if (!(json.data = ngx_pnalloc(r->pool, json.len))) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!ngx_pnalloc"); return NGX_HTTP_INTERNAL_SERVER_ERROR; }
    u_char *p = json.data;
    size_t len;
    for (ngx_chain_t *cl = context->cl ? context->cl : in; cl; cl = cl->next) {
        if (!ngx_buf_in_memory(cl->buf)) continue;
        if (!(len = cl->buf->last - cl->buf->pos)) continue;
        p = ngx_copy(p, cl->buf->pos, len);
    }
    ngx_chain_t cl = {.buf = ngx_http_mustach_process(r, json), .next = NULL};
    if (!cl.buf) return NGX_HTTP_INTERNAL_SERVER_ERROR;
    context->done = 1;
    ngx_int_t rc = ngx_http_next_header_filter(r);
    if (rc == NGX_ERROR || rc > NGX_OK || r->header_only) return rc;
    return ngx_http_next_body_filter(r, &cl);
}

static ngx_int_t ngx_http_mustach_postconfiguration(ngx_conf_t *cf) {
    ngx_http_mustach_main_t *main = ngx_http_conf_get_module_main_conf(cf, ngx_http_mustach_module);
    if (!main->enable) return NGX_OK;
    ngx_http_next_header_filter = ngx_http_top_header_filter;
    ngx_http_top_header_filter = ngx_http_mustach_header_filter;
    ngx_http_next_body_filter = ngx_http_top_body_filter;
    ngx_http_top_body_filter = ngx_http_mustach_body_filter;
    return NGX_OK;
}

static ngx_http_module_t ngx_http_mustach_ctx = {
    .preconfiguration = NULL,
    .postconfiguration = ngx_http_mustach_postconfiguration,
    .create_main_conf = ngx_http_mustach_create_main_conf,
    .init_main_conf = ngx_http_mustach_init_main_conf,
    .create_srv_conf = NULL,
    .merge_srv_conf = NULL,
    .create_loc_conf = ngx_http_mustach_create_loc_conf,
    .merge_loc_conf = ngx_http_mustach_merge_loc_conf
};

ngx_module_t ngx_http_mustach_module = {
    NGX_MODULE_V1,
    .ctx = &ngx_http_mustach_ctx,
    .commands = ngx_http_mustach_commands,
    .type = NGX_HTTP_MODULE,
    .init_master = NULL,
    .init_module = NULL,
    .init_process = NULL,
    .init_thread = NULL,
    .exit_thread = NULL,
    .exit_process = NULL,
    .exit_master = NULL,
    NGX_MODULE_V1_PADDING
};
