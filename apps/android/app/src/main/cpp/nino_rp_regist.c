// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// PS5 eşleme (kayıt): 8 haneli kod + 8 baytlık hesap kimliği → kayıt anahtarı, morning, takma ad.
#include "nino_rp.h"

#include <chiaki/regist.h>

#include <errno.h>
#include <stdio.h>
#include <string.h>

#define REGIST_TIMEOUT_MS 30000
#define STOP_WAIT_MS 10000

// Kotlin'deki sonuç kodlarıyla aynı.
enum { RESULT_SUCCESS = 0, RESULT_FAILED = 1, RESULT_NO_REPLY = 2, RESULT_NOT_STARTED = 3 };

typedef struct {
	pthread_mutex_t lock;
	pthread_cond_t cond;
	bool done;
	ChiakiRegistEventType type;
	ChiakiRegisteredHost host;
} RegistWait;

static void on_regist(ChiakiRegistEvent *event, void *user)
{
	RegistWait *w = user;
	pthread_mutex_lock(&w->lock);
	w->type = event->type;
	// İşaretçi yalnız bu çağrı süresince geçerli: kopyala.
	if(event->type == CHIAKI_REGIST_EVENT_TYPE_FINISHED_SUCCESS && event->registered_host)
		w->host = *event->registered_host;
	w->done = true;
	pthread_cond_broadcast(&w->cond);
	pthread_mutex_unlock(&w->lock);
}

// Kilit tutulurken çağrılır. true: olay geldi.
static bool wait_done(RegistWait *w, int ms)
{
	struct timespec ts;
	clock_gettime(CLOCK_REALTIME, &ts);
	ts.tv_sec += ms / 1000;
	ts.tv_nsec += (long)(ms % 1000) * 1000000L;
	if(ts.tv_nsec >= 1000000000L) { ts.tv_sec++; ts.tv_nsec -= 1000000000L; }
	while(!w->done)
		if(pthread_cond_timedwait(&w->cond, &w->lock, &ts) == ETIMEDOUT)
			break;
	return w->done;
}

static jbyteArray bytes(JNIEnv *env, const void *data, int n)
{
	jbyteArray a = (*env)->NewByteArray(env, n);
	if(a)
		(*env)->SetByteArrayRegion(env, a, 0, n, (const jbyte *)data);
	return a;
}

static jobject make_result(JNIEnv *env, int code, NinoRpLog *log, const ChiakiRegisteredHost *host)
{
	jclass cls = (*env)->FindClass(env, "com/ninotranslator/mobile/remoteplay/NativeRegistResult");
	if(!cls)
		return NULL;
	jmethodID ctor = (*env)->GetMethodID(env, cls, "<init>", "(IJ[Ljava/lang/String;Ljava/lang/String;[B[B)V");
	if(!ctor)
		return NULL;
	jobjectArray lines = nino_log_lines(env, log);
	jstring nick = NULL;
	jbyteArray key = NULL, morning = NULL;
	if(host)
	{
		char name[sizeof(host->server_nickname) + 1];
		memcpy(name, host->server_nickname, sizeof(host->server_nickname));
		name[sizeof(host->server_nickname)] = '\0';
		nick = nino_jstring(env, name);
		key = bytes(env, host->rp_regist_key, sizeof(host->rp_regist_key));
		morning = bytes(env, host->rp_key, sizeof(host->rp_key));
	}
	jobject r = (*env)->NewObject(env, cls, ctor, (jint)code, (jlong)nino_log_app_reason(log), lines, nick, key, morning);
	(*env)->DeleteLocalRef(env, cls);
	return r;
}

JNIEXPORT jobject JNICALL
Java_com_ninotranslator_mobile_remoteplay_RemotePlayNative_nativeRegister(JNIEnv *env, jclass cls,
	jstring host, jbyteArray account_id, jint pin)
{
	NinoRpLog log;
	nino_log_init(&log, "eşleme");
	jobject result = NULL;

	if(nino_lib_ready() != 0 || !host || !account_id
		|| (*env)->GetArrayLength(env, account_id) != CHIAKI_PSN_ACCOUNT_ID_SIZE)
	{
		result = make_result(env, RESULT_NOT_STARTED, &log, NULL);
		nino_log_fini(&log);
		return result;
	}

	const char *h = (*env)->GetStringUTFChars(env, host, NULL);
	ChiakiRegistInfo info;
	memset(&info, 0, sizeof(info));
	info.target = CHIAKI_TARGET_PS5_1;
	info.host = h;
	info.broadcast = false;
	info.psn_online_id = NULL;
	(*env)->GetByteArrayRegion(env, account_id, 0, CHIAKI_PSN_ACCOUNT_ID_SIZE, (jbyte *)info.psn_account_id);
	info.pin = (uint32_t)pin;
	info.console_pin = 0;
	info.holepunch_info = NULL;
	info.rudp = NULL;

	RegistWait w;
	memset(&w, 0, sizeof(w));
	pthread_mutex_init(&w.lock, NULL);
	pthread_cond_init(&w.cond, NULL);

	ChiakiRegist regist;
	ChiakiErrorCode err = h ? chiaki_regist_start(&regist, &log.log, &info, on_regist, &w) : CHIAKI_ERR_MEMORY;
	if(h)
		(*env)->ReleaseStringUTFChars(env, host, h);
	if(err != CHIAKI_ERR_SUCCESS)
	{
		nino_loge("Eşleme başlatılamadı: %s", chiaki_error_string(err));
		result = make_result(env, RESULT_NOT_STARTED, &log, NULL);
	}
	else
	{
		pthread_mutex_lock(&w.lock);
		bool finished = wait_done(&w, REGIST_TIMEOUT_MS);
		pthread_mutex_unlock(&w.lock);
		if(!finished)
		{
			nino_loge("Eşleme %d sn içinde bitmedi, durduruluyor", REGIST_TIMEOUT_MS / 1000);
			chiaki_regist_stop(&regist);
			pthread_mutex_lock(&w.lock);
			wait_done(&w, STOP_WAIT_MS);
			pthread_mutex_unlock(&w.lock);
		}
		chiaki_regist_fini(&regist);
		if(finished && w.type == CHIAKI_REGIST_EVENT_TYPE_FINISHED_SUCCESS)
			result = make_result(env, RESULT_SUCCESS, &log, &w.host);
		else if(finished && w.type == CHIAKI_REGIST_EVENT_TYPE_FINISHED_FAILED)
			result = make_result(env, RESULT_FAILED, &log, NULL);
		else
			result = make_result(env, RESULT_NO_REPLY, &log, NULL);
	}
	pthread_cond_destroy(&w.cond);
	pthread_mutex_destroy(&w.lock);
	nino_log_fini(&log);
	return result;
}
