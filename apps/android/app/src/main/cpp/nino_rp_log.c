// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// chiaki günlüğünü Android günlüğüne aktarır, hata satırlarını ve PS5 red kodunu biriktirir.
#include "nino_rp.h"

#include <android/log.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char REASON_MARK[] = "Reported Application Reason:";

static void log_cb(ChiakiLogLevel level, const char *msg, void *user)
{
	NinoRpLog *l = user;
	int prio = ANDROID_LOG_DEBUG;
	switch(level)
	{
		case CHIAKI_LOG_ERROR: prio = ANDROID_LOG_ERROR; break;
		case CHIAKI_LOG_WARNING: prio = ANDROID_LOG_WARN; break;
		case CHIAKI_LOG_INFO: prio = ANDROID_LOG_INFO; break;
		default: break;
	}
	__android_log_print(prio, NINO_TAG, "[%s] %s", l && l->what ? l->what : "rp", msg ? msg : "");
	if(!l || !msg || level != CHIAKI_LOG_ERROR)
		return;
	pthread_mutex_lock(&l->lock);
	int slot;
	if(l->line_count < NINO_LOG_LINES)
		slot = (l->line_start + l->line_count++) % NINO_LOG_LINES;
	else
	{
		slot = l->line_start;
		l->line_start = (l->line_start + 1) % NINO_LOG_LINES;
	}
	snprintf(l->lines[slot], NINO_LOG_LINE_MAX, "%s", msg);
	const char *r = strstr(msg, REASON_MARK);
	if(r)
	{
		r += sizeof(REASON_MARK) - 1;
		unsigned long code = strtoul(r, NULL, 16);
		if(code)
			l->app_reason = (uint32_t)code;
	}
	pthread_mutex_unlock(&l->lock);
}

void nino_log_init(NinoRpLog *l, const char *what)
{
	memset(l, 0, sizeof(*l));
	pthread_mutex_init(&l->lock, NULL);
	l->what = what;
	chiaki_log_init(&l->log, CHIAKI_LOG_ERROR | CHIAKI_LOG_WARNING | CHIAKI_LOG_INFO, log_cb, l);
}

void nino_log_fini(NinoRpLog *l)
{
	pthread_mutex_destroy(&l->lock);
}

void nino_log_clear(NinoRpLog *l)
{
	pthread_mutex_lock(&l->lock);
	l->line_count = 0;
	l->line_start = 0;
	l->app_reason = 0;
	pthread_mutex_unlock(&l->lock);
}

jobjectArray nino_log_lines(JNIEnv *env, NinoRpLog *l)
{
	jclass str = (*env)->FindClass(env, "java/lang/String");
	pthread_mutex_lock(&l->lock);
	int n = l->line_count;
	char copy[NINO_LOG_LINES][NINO_LOG_LINE_MAX];
	for(int i = 0; i < n; i++)
		memcpy(copy[i], l->lines[(l->line_start + i) % NINO_LOG_LINES], NINO_LOG_LINE_MAX);
	pthread_mutex_unlock(&l->lock);
	jobjectArray arr = (*env)->NewObjectArray(env, n, str, NULL);
	for(int i = 0; arr && i < n; i++)
	{
		jstring s = nino_jstring(env, copy[i]);
		(*env)->SetObjectArrayElement(env, arr, i, s);
		(*env)->DeleteLocalRef(env, s);
	}
	(*env)->DeleteLocalRef(env, str);
	return arr;
}

uint32_t nino_log_app_reason(NinoRpLog *l)
{
	pthread_mutex_lock(&l->lock);
	uint32_t r = l->app_reason;
	pthread_mutex_unlock(&l->lock);
	return r;
}

static NinoRpLog global_log;
static pthread_once_t global_once = PTHREAD_ONCE_INIT;
static void global_init(void) { nino_log_init(&global_log, "genel"); }

NinoRpLog *nino_log_global(void)
{
	pthread_once(&global_once, global_init);
	return &global_log;
}

static void vlog(int prio, const char *fmt, va_list ap)
{
	__android_log_vprint(prio, NINO_TAG, fmt, ap);
}

void nino_logi(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	vlog(ANDROID_LOG_INFO, fmt, ap);
	va_end(ap);
}

void nino_loge(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	vlog(ANDROID_LOG_ERROR, fmt, ap);
	va_end(ap);
}
