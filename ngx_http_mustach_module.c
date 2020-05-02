#include <nginx.h>
#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <mustach/mustach-json-c.h>

typedef struct {
    ngx_str_t type;
} ngx_http_mustach_context_t;

typedef struct {
    ngx_http_complex_value_t *json;
    ngx_http_complex_value_t *template;
    ngx_http_complex_value_t *type;
} ngx_http_mustach_location_conf_t;

ngx_module_t ngx_http_mustach_module;

static ngx_http_output_header_filter_pt ngx_http_next_header_filter;
static ngx_http_output_body_filter_pt ngx_http_next_body_filter;

static ngx_int_t ngx_http_mustach_handler(ngx_http_request_t *r) {
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0, "%s", __func__);
    r->headers_out.status = NGX_HTTP_OK;
    ngx_int_t rc = ngx_http_send_header(r);
    if (rc == NGX_ERROR || rc > NGX_OK || r->header_only); else rc = ngx_http_output_filter(r, NULL);
    return rc;
}

static char *ngx_http_set_complex_value_slot_my(ngx_conf_t *cf, ngx_command_t *cmd, void *conf) {
    ngx_http_core_loc_conf_t *core_loc_conf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_core_module);
    if (!core_loc_conf->handler) core_loc_conf->handler = ngx_http_mustach_handler;
    return ngx_http_set_complex_value_slot(cf, cmd, conf);
}

static ngx_command_t ngx_http_mustach_commands[] = {
  { .name = ngx_string("mustach_json"),
    .type = NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
    .set = ngx_http_set_complex_value_slot,
    .conf = NGX_HTTP_LOC_CONF_OFFSET,
    .offset = offsetof(ngx_http_mustach_location_conf_t, json),
    .post = NULL },
  { .name = ngx_string("mustach_template"),
    .type = NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
    .set = ngx_http_set_complex_value_slot_my,
    .conf = NGX_HTTP_LOC_CONF_OFFSET,
    .offset = offsetof(ngx_http_mustach_location_conf_t, template),
    .post = NULL },
  { .name = ngx_string("mustach_type"),
    .type = NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_CONF_TAKE1,
    .set = ngx_http_set_complex_value_slot,
    .conf = NGX_HTTP_LOC_CONF_OFFSET,
    .offset = offsetof(ngx_http_mustach_location_conf_t, type),
    .post = NULL },
    ngx_null_command
};

static void *ngx_http_mustach_create_loc_conf(ngx_conf_t *cf) {
    ngx_http_mustach_location_conf_t *location_conf = ngx_pcalloc(cf->pool, sizeof(ngx_http_mustach_location_conf_t));
    if (!location_conf) return NULL;
    return location_conf;
}

static char *ngx_http_mustach_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child) {
    ngx_http_mustach_location_conf_t *prev = parent;
    ngx_http_mustach_location_conf_t *conf = child;
    if (!conf->json) conf->json = prev->json;
    if (!conf->template) conf->template = prev->template;
    if (!conf->type) conf->type = prev->type;
    return NGX_CONF_OK;
}

static ngx_int_t ngx_http_mustach_header_filter(ngx_http_request_t *r) {
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0, "%s", __func__);
    ngx_http_mustach_location_conf_t *location_conf = ngx_http_get_module_loc_conf(r, ngx_http_mustach_module);
    ngx_http_mustach_context_t *context = ngx_pcalloc(r->pool, sizeof(ngx_http_mustach_context_t));
    if (!context) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!ngx_pcalloc"); return NGX_ERROR; }
    ngx_http_set_ctx(r, context, ngx_http_mustach_module);
    context->type = r->headers_out.content_type;
    if (!location_conf->json && !(context->type.len >= sizeof("application/json") - 1 && !ngx_strncasecmp(context->type.data, (u_char *)"application/json", sizeof("application/json") - 1))) return ngx_http_next_header_filter(r);
    if (!location_conf->template) return ngx_http_next_header_filter(r);
    ngx_http_clear_content_length(r);
    ngx_http_clear_accept_ranges(r);
    ngx_http_weak_etag(r);
    if (location_conf->type && ngx_http_complex_value(r, location_conf->type, &r->headers_out.content_type) != NGX_OK) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "ngx_http_complex_value != NGX_OK"); return NGX_ERROR; }
    if (!r->headers_out.content_type.data) {
        ngx_http_core_loc_conf_t *core = ngx_http_get_module_loc_conf(r, ngx_http_core_module);
        r->headers_out.content_type = core->default_type;
    }
    r->headers_out.content_type_len = r->headers_out.content_type.len;
    return ngx_http_next_header_filter(r);
}

static ngx_int_t ngx_http_mustach_body_filter_internal(ngx_http_request_t *r, ngx_chain_t *in) {
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0, "%s", __func__);
    ngx_http_mustach_location_conf_t *location_conf = ngx_http_get_module_loc_conf(r, ngx_http_mustach_module);
    ngx_int_t rc = NGX_ERROR;
    u_char *jsonc;
    if (in) {
        size_t len = 0;
        for (ngx_chain_t *cl = in; cl; cl = cl->next) {
            if (!ngx_buf_in_memory(cl->buf)) continue;
            len += cl->buf->last - cl->buf->pos;
        }
        if (!(jsonc = ngx_pnalloc(r->pool, len + 1))) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!ngx_pnalloc"); goto ret; }
        u_char *p = jsonc;
        for (ngx_chain_t *cl = in; cl; cl = cl->next) {
            if (!ngx_buf_in_memory(cl->buf)) continue;
            if (!(len = cl->buf->last - cl->buf->pos)) continue;
            p = ngx_copy(p, cl->buf->pos, len);
        }
        *p = '\0';
    } else if (location_conf->json) {
        ngx_str_t json;
        if (ngx_http_complex_value(r, location_conf->json, &json) != NGX_OK) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "ngx_http_complex_value != NGX_OK"); goto ret; }
        if (!(jsonc = ngx_pnalloc(r->pool, json.len + 1))) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!ngx_pnalloc"); goto ret; }
        (void) ngx_cpystrn(jsonc, json.data, json.len + 1);
    } else { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!in && !json"); goto ret; }
    ngx_str_t template;
    if (ngx_http_complex_value(r, location_conf->template, &template) != NGX_OK) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "ngx_http_complex_value != NGX_OK"); goto ret; }
    u_char *templatec = ngx_pnalloc(r->pool, template.len + 1);
    if (!templatec) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!ngx_pnalloc"); goto ret; }
    (void) ngx_cpystrn(templatec, template.data, template.len + 1);
    struct json_object *object = json_tokener_parse(jsonc);
    if (!object) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!json_tokener_parse"); goto ret; }
    ngx_str_t output = ngx_null_string;
    FILE *out = open_memstream((char **)&output.data, &output.len);
    if (!out) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!open_memstream"); goto json_object_put; }
    if (fmustach_json_c(templatec, object, out)) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "fmustach_json_c"); goto free; }
    fclose(out);
    if (!output.len) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!output.len"); goto free; }
    ngx_chain_t *chain = ngx_alloc_chain_link(r->pool);
    if (!chain) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!ngx_alloc_chain_link"); goto free; }
    chain->next = NULL;
    ngx_buf_t *buf = chain->buf = ngx_create_temp_buf(r->pool, output.len);
    if (!buf) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!ngx_create_temp_buf"); goto free; }
    buf->memory = 1;
    buf->last = ngx_copy(buf->last, output.data, output.len);
    if (buf->last != buf->end) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "buf->last != buf->end"); goto free; }
    buf->last_buf = (r == r->main) ? 1 : 0;
    buf->last_in_chain = 1;
    rc = ngx_http_next_body_filter(r, chain);
free:
    free(output.data);
json_object_put:
    json_object_put(object);
ret:
    return rc;
}

#if (NGX_THREADS)
static void ngx_http_mustach_thread_event_handler(ngx_event_t *ev) {
    ngx_http_request_t *r = ev->data;
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0, "%s", __func__);
    ngx_connection_t *c = r->connection;
    r->main->blocked--;
    r->aio = 0;
    if (r->done) c->write->handler(c->write); else {
        r->write_event_handler(r);
        ngx_http_run_posted_requests(c);
    }
}

static ngx_int_t ngx_http_mustach_thread_handler(ngx_thread_task_t *task, ngx_file_t *file) {
    ngx_http_request_t *r = file->thread_ctx;
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0, "%s", __func__);
    ngx_http_core_loc_conf_t *core_loc_conf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);
    ngx_thread_pool_t *thread_pool = core_loc_conf->thread_pool;
    if (!thread_pool) {
        ngx_str_t name;
        if (ngx_http_complex_value(r, core_loc_conf->thread_pool_value, &name) != NGX_OK) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "ngx_http_complex_value != NGX_OK"); return NGX_ERROR; }
        if (!(thread_pool = ngx_thread_pool_get((ngx_cycle_t *)ngx_cycle, &name))) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "thread pool \"%V\" not found", &name); return NGX_ERROR; }
    }
    task->event.data = r;
    task->event.handler = ngx_http_mustach_thread_event_handler;
    if (ngx_thread_task_post(thread_pool, task) != NGX_OK) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "ngx_thread_task_post != NGX_OK"); return NGX_ERROR; }
    r->main->blocked++;
    r->aio = 1;
    return NGX_OK;
}
#endif

static ngx_int_t ngx_http_mustach_body_filter(ngx_http_request_t *r, ngx_chain_t *in) {
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0, "%s", __func__);
    ngx_http_mustach_location_conf_t *location_conf = ngx_http_get_module_loc_conf(r, ngx_http_mustach_module);
    ngx_http_mustach_context_t *context = ngx_http_get_module_ctx(r, ngx_http_mustach_module);
    if (!location_conf->json && !(in && context->type.len >= sizeof("application/json") - 1 && !ngx_strncasecmp(context->type.data, (u_char *)"application/json", sizeof("application/json") - 1))) return ngx_http_next_body_filter(r, in);
    if (!location_conf->template) return ngx_http_next_body_filter(r, in);
    ngx_http_core_loc_conf_t *core_loc_conf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);
#if (NGX_THREADS)
    if (core_loc_conf->aio != NGX_HTTP_AIO_THREADS)
#endif
    return ngx_http_mustach_body_filter_internal(r, in);
#if (NGX_THREADS)
    ngx_output_chain_ctx_t *ctx = ngx_pcalloc(r->pool, sizeof(ngx_output_chain_ctx_t));
    if (!ctx) { ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "!ngx_pcalloc"); return NGX_ERROR; }
    ctx->pool = r->pool;
    ctx->output_filter = (ngx_output_chain_filter_pt)ngx_http_mustach_body_filter_internal;
    ctx->filter_ctx = r;
    ctx->thread_handler = ngx_http_mustach_thread_handler;
    ctx->aio = r->aio;
    return ngx_output_chain(ctx, in);
#endif
}

static ngx_int_t ngx_http_mustach_postconfiguration(ngx_conf_t *cf) {
    ngx_http_next_header_filter = ngx_http_top_header_filter;
    ngx_http_top_header_filter = ngx_http_mustach_header_filter;
    ngx_http_next_body_filter = ngx_http_top_body_filter;
    ngx_http_top_body_filter = ngx_http_mustach_body_filter;
    return NGX_OK;
}

static ngx_http_module_t ngx_http_mustach_ctx = {
    .preconfiguration = NULL,
    .postconfiguration = ngx_http_mustach_postconfiguration,
    .create_main_conf = NULL,
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
