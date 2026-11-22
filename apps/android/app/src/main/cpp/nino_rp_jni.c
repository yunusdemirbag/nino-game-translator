// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// JNI girişi: JVM'e bağlanma, dize dönüşümü ve kütüphanenin bir kez başlatılması.
#include "nino_rp.h"

#include <chiaki/common.h>
#include <stdlib.h>
#include <string.h>

static JavaVM *jvm;
static pthread_key_t env_key;
static pthread_once_t lib_once = PTHREAD_ONCE_INIT;
static int lib_result = -1;

static void detach_thread(void *value)
{
	if(value && jvm)
		(*jvm)->DetachCurrentThread(jvm);
}

JNIEXPORT jint JNI_OnLoad(JavaVM *vm, void *reserved)
{
	jvm = vm;
	pthread_key_create(&env_key, detach_thread);
	return JNI_VERSION_1_6;
}

JNIEnv *nino_env(void)
{
	if(!jvm)
		return NULL;
	JNIEnv *env = NULL;
	if((*jvm)->GetEnv(jvm, (void **)&env, JNI_VERSION_1_6) == JNI_OK)
		return env;
	JavaVMAttachArgs args = { JNI_VERSION_1_6, "nino-rp", NULL };
	if((*jvm)->AttachCurrentThread(jvm, &env, &args) != JNI_OK)
		return NULL;
	// Yalnız bizim bağladığımız iş parçacıkları çıkışta ayrılır.
	pthread_setspecific(env_key, env);
	return env;
}

jstring nino_jstring(JNIEnv *env, const char *s)
{
	if(!s)
		return NULL;
	size_t n = strlen(s);
	char *clean = malloc(n + 1);
	if(!clean)
		return NULL;
	for(size_t i = 0; i < n; i++)
	{
		unsigned char c = (unsigned char)s[i];
		if(c == '\n' || c == '\r')
			clean[i] = ' ';
		else
			clean[i] = (c >= 0x20 && c < 0x7f) ? (char)c : '?';
	}
	clean[n] = '\0';
	jstring r = (*env)->NewStringUTF(env, clean);
	free(clean);
	return r;
}

static void lib_init_once(void)
{
	lib_result = (int)chiaki_lib_init();
	if(lib_result != CHIAKI_ERR_SUCCESS)
		nino_loge("Remote Play kütüphanesi başlatılamadı: %s", chiaki_error_string(lib_result));
}

int nino_lib_ready(void)
{
	pthread_once(&lib_once, lib_init_once);
	return lib_result;
}

JNIEXPORT jint JNICALL
Java_com_ninotranslator_mobile_remoteplay_RemotePlayNative_nativeInit(JNIEnv *env, jclass cls)
{
	return nino_lib_ready();
}
