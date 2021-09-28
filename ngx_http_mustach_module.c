#include "ngx_http_mustach_module.h"

#include <ngx_config.h>
#include <ngx_core.h>
#include <mustach/mustach.h>

typedef enum {
    MUSTACH_CJSON,
    MUSTACH_JANSSON,
    MUSTACH_JSON_C
} ngx_http_mustach_type_t;

typedef struct {
    ngx_chain_t *cl;
    ngx_flag_t done;
} ngx_http_mustach_context_t;

typedef struct {
    ngx_flag_t enable;
} ngx_http_mustach_main_t;

typedef struct {
    ngx_http_complex_value_t *content;
    ngx_http_complex_value_t *json;
    ngx_http_complex_value_t *template;
    ngx_uint_t type;
} ngx_http_mustach_location_t;

ngx_module_t ngx_http_mustach_module;

static ngx_http_output_header_filter_pt ngx_http_next_header_filter;
static ngx_http_output_body_filter_pt ngx_http_next_body_filter;

static ngx_buf_t *ngx_http_mustach_process(ngx_http_request_t *r, ngx_str_t json) {
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0, "%s", __func__);
    ngx_http_clear_accept_ranges(r);
    ngx_http_clear_content_length(r);
    ngx_http_weak_etag(r);
    ngx_http_mustach_location_t *location = ngx_http_get_module_loc_conf(r, ngx_http_mustach_module);
    if (location->content && ngx_http_complex_value(r, location->content, &r->headers_out.content_type) != NGX_OK) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "ngx_http_complex_value != NGX_OK"); return NULL; }
    if (!r->headers_out.content_type.data) {
        ngx_http_core_loc_conf_t *core = ngx_http_get_module_loc_conf(r, ngx_http_core_module);
        r->headers_out.content_type = core->default_type;
    }
    r->headers_out.content_type_len = r->headers_out.content_type.len;
    ngx_str_t template;
    if (ngx_http_complex_value(r, location->template, &template) != NGX_OK) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "ngx_http_complex_value != NGX_OK"); return NULL; }
    if (!template.len) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!template.len"); return NULL; }
    int (*ngx_http_mustach_process)(ngx_http_request_t *r, const char *template, size_t length, const char *data, size_t len, FILE *file);
    switch (location->type) {
        case MUSTACH_CJSON: ngx_http_mustach_process = ngx_http_mustach_process_cjson; break;
        case MUSTACH_JANSSON: ngx_http_mustach_process = ngx_http_mustach_process_jansson; break;
        case MUSTACH_JSON_C: ngx_http_mustach_process = ngx_http_mustach_process_json_c; break;
        default: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "location->type = %i", location->type); return NULL;
    }
    ngx_str_t output = ngx_null_string;
    FILE *out = open_memstream((char **)&output.data, &output.len);
    if (!out) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!open_memstream"); return NULL; }
    ngx_buf_t *b = NULL;
    switch (ngx_http_mustach_process(r, (const char *)template.data, template.len, (const char *)json.data, json.len, out)) {
        case MUSTACH_OK: break;
        case MUSTACH_ERROR_SYSTEM: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_SYSTEM"); goto free;
        case MUSTACH_ERROR_UNEXPECTED_END: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_UNEXPECTED_END"); goto free;
        case MUSTACH_ERROR_EMPTY_TAG: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_EMPTY_TAG"); goto free;
        case MUSTACH_ERROR_TAG_TOO_LONG: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_TAG_TOO_LONG"); goto free;
        case MUSTACH_ERROR_BAD_SEPARATORS: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_BAD_SEPARATORS"); goto free;
        case MUSTACH_ERROR_TOO_DEEP: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_TOO_DEEP"); goto free;
        case MUSTACH_ERROR_CLOSING: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_CLOSING"); goto free;
        case MUSTACH_ERROR_BAD_UNESCAPE_TAG: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_BAD_UNESCAPE_TAG"); goto free;
        case MUSTACH_ERROR_INVALID_ITF: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_INVALID_ITF"); goto free;
        case MUSTACH_ERROR_ITEM_NOT_FOUND: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_ITEM_NOT_FOUND"); goto free;
        case MUSTACH_ERROR_PARTIAL_NOT_FOUND: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "MUSTACH_ERROR_PARTIAL_NOT_FOUND"); goto free;
        default: ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "ngx_http_mustach_process"); goto free;
    }
    fclose(out);
    if (!output.len) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!output.len"); goto free; }
    if (!(b = ngx_create_temp_buf(r->pool, output.len))) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!ngx_create_temp_buf"); goto free; }
    b->last_buf = 1;
    b->last = ngx_copy(b->last, output.data, output.len);
    b->memory = 1;
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
    if (!core->handler) core->handler = ngx_http_mustach_handler;
    return ngx_http_set_complex_value_slot(cf, cmd, conf);
}

static ngx_conf_enum_t ngx_http_mustach_type[] = {
    { ngx_string("cjson"), MUSTACH_CJSON },
    { ngx_string("jansson"), MUSTACH_JANSSON },
    { ngx_string("json-c"), MUSTACH_JSON_C },
    { ngx_null_string, 0 }
};

static ngx_command_t ngx_http_mustach_commands[] = {
  { .name = ngx_string("mustach_content"),
    .type = NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF|NGX_CONF_TAKE1,
    .set = ngx_http_set_complex_value_slot,
    .conf = NGX_HTTP_LOC_CONF_OFFSET,
    .offset = offsetof(ngx_http_mustach_location_t, content),
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
  { .name = ngx_string("mustach_type"),
    .type = NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF|NGX_CONF_TAKE1,
    .set = ngx_conf_set_enum_slot,
    .conf = NGX_HTTP_LOC_CONF_OFFSET,
    .offset = offsetof(ngx_http_mustach_location_t, type),
    .post = &ngx_http_mustach_type },
    ngx_null_command
};

static void *ngx_http_mustach_create_main_conf(ngx_conf_t *cf) {
    ngx_http_mustach_main_t *main = ngx_pcalloc(cf->pool, sizeof(*main));
    if (!main) return NULL;
    return main;
}

static void *ngx_http_mustach_create_loc_conf(ngx_conf_t *cf) {
    ngx_http_mustach_location_t *location = ngx_pcalloc(cf->pool, sizeof(*location));
    if (!location) return NULL;
    location->type = NGX_CONF_UNSET_UINT;
    return location;
}

static char *ngx_http_mustach_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child) {
    ngx_http_mustach_location_t *prev = parent;
    ngx_http_mustach_location_t *conf = child;
    if (!conf->content) conf->content = prev->content;
    if (!conf->json) conf->json = prev->json;
    if (!conf->template) conf->template = prev->template;
    ngx_conf_merge_uint_value(conf->type, prev->type, MUSTACH_JSON_C);
    return NGX_CONF_OK;
}

static ngx_int_t ngx_http_mustach_header_filter(ngx_http_request_t *r) {
    ngx_http_mustach_location_t *location = ngx_http_get_module_loc_conf(r, ngx_http_mustach_module);
    if (!location->template) return ngx_http_next_header_filter(r);
    if (!(r->headers_out.content_type.len >= sizeof("application/json") - 1 && !ngx_strncasecmp(r->headers_out.content_type.data, (u_char *)"application/json", sizeof("application/json") - 1))) return ngx_http_next_header_filter(r);
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0, "%s", __func__);
    ngx_http_mustach_context_t *context = ngx_pcalloc(r->pool, sizeof(*context));
    if (!context) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!ngx_pcalloc"); return NGX_ERROR; }
    ngx_http_set_ctx(r, context, ngx_http_mustach_module);
    return NGX_OK;
}

static ngx_int_t ngx_http_mustach_body_filter(ngx_http_request_t *r, ngx_chain_t *in) {
    if (!in) return ngx_http_next_body_filter(r, in);
    ngx_http_mustach_context_t *context = ngx_http_get_module_ctx(r, ngx_http_mustach_module);
    ngx_http_mustach_location_t *location = ngx_http_get_module_loc_conf(r, ngx_http_mustach_module);
    if (!location->template || !context || context->done) return ngx_http_next_body_filter(r, in);
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0, "%s", __func__);
    if (!in->buf->last_buf && !in->buf->last_in_chain) {
        if (ngx_chain_add_copy(r->pool, &context->cl, in) != NGX_OK) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "ngx_chain_add_copy != NGX_OK"); return NGX_HTTP_INTERNAL_SERVER_ERROR; }
        return ngx_http_next_body_filter(r, in);
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
    if (!cl.buf) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!cl.buf"); return NGX_HTTP_INTERNAL_SERVER_ERROR; }
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
    .init_main_conf = NULL,
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
