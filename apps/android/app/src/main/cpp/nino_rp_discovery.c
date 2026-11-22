// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// PS5 bulma ve uyandırma. Arama yayınla değil, verilen adreslere tek tek ve 500 ms'de bir yinelenerek yapılır.
#include "nino_rp.h"

#include <chiaki/discovery.h>

#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define MAX_FOUND 32
#define RESEND_MS 500
#define FIELD 128

typedef struct {
	char addr[64];
	char name[FIELD];
	bool ready;
	char title_id[FIELD];
	char app_name[FIELD];
} Found;

typedef struct {
	pthread_mutex_t lock;
	Found items[MAX_FOUND];
	int count;
} FoundList;

static void copy_field(char *dst, const char *src)
{
	snprintf(dst, FIELD, "%s", src ? src : "");
}

static void on_host(ChiakiDiscoveryHost *host, void *user)
{
	FoundList *list = user;
	if(!host || !host->host_addr || !chiaki_discovery_host_is_ps5(host))
		return;
	pthread_mutex_lock(&list->lock);
	int slot = -1;
	for(int i = 0; i < list->count; i++)
		if(strcmp(list->items[i].addr, host->host_addr) == 0) { slot = i; break; }
	if(slot < 0 && list->count < MAX_FOUND)
		slot = list->count++;
	if(slot >= 0)
	{
		// Aynı adresten gelen son yanıt geçerli (PS5 uyanınca durumu değişir).
		Found *f = &list->items[slot];
		snprintf(f->addr, sizeof(f->addr), "%s", host->host_addr);
		copy_field(f->name, host->host_name && host->host_name[0] ? host->host_name : "PS5");
		f->ready = host->state == CHIAKI_DISCOVERY_HOST_STATE_READY;
		copy_field(f->title_id, host->running_app_titleid);
		copy_field(f->app_name, host->running_app_name);
	}
	pthread_mutex_unlock(&list->lock);
}

static void sleep_ms(uint64_t ms)
{
	struct timespec ts = { (time_t)(ms / 1000), (long)((ms % 1000) * 1000000L) };
	nanosleep(&ts, NULL);
}

// Dönüş: her PS5 için 5 alan (adres, ad, "1"/"0" uyanık, çalışan uygulama kimliği, adı).
JNIEXPORT jobjectArray JNICALL
Java_com_ninotranslator_mobile_remoteplay_RemotePlayNative_nativeDiscover(JNIEnv *env, jclass cls,
	jobjectArray addresses, jint timeout_ms)
{
	jclass str_cls = (*env)->FindClass(env, "java/lang/String");
	if(nino_lib_ready() != 0 || !addresses)
		return (*env)->NewObjectArray(env, 0, str_cls, NULL);

	jsize n = (*env)->GetArrayLength(env, addresses);
	struct sockaddr_in *targets = calloc(n > 0 ? (size_t)n : 1, sizeof(struct sockaddr_in));
	int target_count = 0;
	for(jsize i = 0; targets && i < n; i++)
	{
		jstring s = (jstring)(*env)->GetObjectArrayElement(env, addresses, i);
		if(!s)
			continue;
		const char *c = (*env)->GetStringUTFChars(env, s, NULL);
		struct sockaddr_in *a = &targets[target_count];
		memset(a, 0, sizeof(*a));
		a->sin_family = AF_INET;
		a->sin_port = htons(CHIAKI_DISCOVERY_PORT_PS5);
		if(c && inet_pton(AF_INET, c, &a->sin_addr) == 1)
			target_count++;
		if(c)
			(*env)->ReleaseStringUTFChars(env, s, c);
		(*env)->DeleteLocalRef(env, s);
	}

	FoundList list;
	memset(&list, 0, sizeof(list));
	pthread_mutex_init(&list.lock, NULL);

	NinoRpLog *log = nino_log_global();
	ChiakiDiscovery discovery;
	ChiakiDiscoveryThread thread;
	bool started = false;
	if(targets && target_count > 0 && chiaki_discovery_init(&discovery, &log->log, AF_INET) == CHIAKI_ERR_SUCCESS)
	{
		if(chiaki_discovery_thread_start(&thread, &discovery, on_host, &list) == CHIAKI_ERR_SUCCESS)
		{
			started = true;
			ChiakiDiscoveryPacket packet;
			memset(&packet, 0, sizeof(packet));
			packet.cmd = CHIAKI_DISCOVERY_CMD_SRCH;
			packet.protocol_version = CHIAKI_DISCOVERY_PROTOCOL_VERSION_PS5;
			uint64_t deadline = nino_now_ms() + (uint64_t)(timeout_ms > 0 ? timeout_ms : 0);
			do
			{
				for(int i = 0; i < target_count; i++)
					chiaki_discovery_send(&discovery, &packet, (struct sockaddr *)&targets[i], sizeof(targets[i]));
				uint64_t now = nino_now_ms();
				if(now >= deadline)
					break;
				uint64_t left = deadline - now;
				sleep_ms(left < RESEND_MS ? left : RESEND_MS);
			} while(nino_now_ms() < deadline);
			chiaki_discovery_thread_stop(&thread);
		}
		chiaki_discovery_fini(&discovery);
	}
	if(!started)
		nino_loge("PS5 araması başlatılamadı (%d adres)", target_count);
	free(targets);

	pthread_mutex_lock(&list.lock);
	jobjectArray out = (*env)->NewObjectArray(env, list.count * 5, str_cls, NULL);
	for(int i = 0; out && i < list.count; i++)
	{
		Found *f = &list.items[i];
		const char *fields[5] = { f->addr, f->name, f->ready ? "1" : "0", f->title_id, f->app_name };
		for(int k = 0; k < 5; k++)
		{
			jstring js = nino_jstring(env, fields[k]);
			(*env)->SetObjectArrayElement(env, out, i * 5 + k, js);
			(*env)->DeleteLocalRef(env, js);
		}
	}
	pthread_mutex_unlock(&list.lock);
	pthread_mutex_destroy(&list.lock);
	return out;
}

JNIEXPORT jint JNICALL
Java_com_ninotranslator_mobile_remoteplay_RemotePlayNative_nativeWakeup(JNIEnv *env, jclass cls,
	jstring host, jlong credential)
{
	if(nino_lib_ready() != 0 || !host)
		return CHIAKI_ERR_UNINITIALIZED;
	const char *h = (*env)->GetStringUTFChars(env, host, NULL);
	if(!h)
		return CHIAKI_ERR_MEMORY;
	ChiakiErrorCode err = chiaki_discovery_wakeup(&nino_log_global()->log, NULL, h, (uint64_t)credential, true);
	if(err != CHIAKI_ERR_SUCCESS)
		nino_loge("Uyandırma gönderilemedi: %s", chiaki_error_string(err));
	(*env)->ReleaseStringUTFChars(env, host, h);
	return (jint)err;
}
