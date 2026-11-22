// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors
//
// PS5 oturumu: 1080p (ya da 720p) 30 kare H.264, ses kapalı, kumanda yok. Olaylar ve kareler Kotlin dinleyicisine.
#include "nino_rp.h"

#include <chiaki/session.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
	ChiakiSession session;
	NinoRpLog log;
	NinoDecoder *decoder;
	jobject listener;
	jmethodID on_connected;
	jmethodID on_pin;
	jmethodID on_quit;
	jmethodID on_frame;
} NinoSession;

static pthread_mutex_t error_lock = PTHREAD_MUTEX_INITIALIZER;
static char open_error[256];

static void set_open_error(const char *msg)
{
	pthread_mutex_lock(&error_lock);
	snprintf(open_error, sizeof(open_error), "%s", msg ? msg : "");
	pthread_mutex_unlock(&error_lock);
	if(msg && msg[0])
		nino_loge("Oturum açılamadı: %s", msg);
}

static void clear_exception(JNIEnv *env, const char *where)
{
	if((*env)->ExceptionCheck(env))
	{
		(*env)->ExceptionDescribe(env);
		(*env)->ExceptionClear(env);
		nino_loge("Kotlin dinleyicisi hata verdi: %s", where);
	}
}

// Çözücünün çıkış iş parçacığı. Arabellek yalnız çağrı süresince geçerli.
static void on_frame(void *user, uint8_t *data, size_t size, int width, int height, int color_format,
	bool has_chroma, int64_t pts)
{
	NinoSession *s = user;
	JNIEnv *env = nino_env();
	if(!env)
		return;
	jobject buf = (*env)->NewDirectByteBuffer(env, data, (jlong)size);
	if(!buf)
	{
		clear_exception(env, "ByteBuffer");
		return;
	}
	(*env)->CallVoidMethod(env, s->listener, s->on_frame, buf, (jint)width, (jint)height, (jint)width,
		(jint)color_format, (jboolean)has_chroma, (jlong)pts);
	clear_exception(env, "kare");
	(*env)->DeleteLocalRef(env, buf);
}

static bool on_video_sample(uint8_t *buf, size_t buf_size, int32_t frames_lost, bool frame_recovered, void *user)
{
	NinoSession *s = user;
	return nino_decoder_push(s->decoder, buf, buf_size);
}

// Kütüphanenin iş parçacığından, durum kilidi tutulurken gelir: burada oturuma dokunulmaz, yalnız haber verilir.
static void on_event(ChiakiEvent *event, void *user)
{
	NinoSession *s = user;
	JNIEnv *env = nino_env();
	if(!env)
		return;
	switch(event->type)
	{
		case CHIAKI_EVENT_CONNECTED:
			nino_logi("PS5'e bağlandı");
			(*env)->CallVoidMethod(env, s->listener, s->on_connected);
			clear_exception(env, "bağlandı");
			break;
		case CHIAKI_EVENT_LOGIN_PIN_REQUEST:
			nino_logi("PS5 giriş şifresi istedi (önceki yanlış: %d)", event->login_pin_request.pin_incorrect);
			(*env)->CallVoidMethod(env, s->listener, s->on_pin, (jboolean)event->login_pin_request.pin_incorrect);
			clear_exception(env, "giriş şifresi");
			break;
		case CHIAKI_EVENT_QUIT:
		{
			const char *text = chiaki_quit_reason_string(event->quit.reason);
			nino_logi("Oturum bitti: %s (%s)", text ? text : "", event->quit.reason_str ? event->quit.reason_str : "-");
			jstring js = nino_jstring(env, text ? text : "");
			(*env)->CallVoidMethod(env, s->listener, s->on_quit, (jint)event->quit.reason, js);
			clear_exception(env, "bitti");
			if(js)
				(*env)->DeleteLocalRef(env, js);
			break;
		}
		default:
			break;
	}
}

// PS5 korumalı içerik bildirince kütüphane bunu koşulsuz çağırır; atanmazsa süreç çöker. Yalnız günlüğe yazılır.
static void on_cant_display(void *user, bool cant_display)
{
	nino_logi("PS5 görüntü yayın kısıtı: %s", cant_display ? "var" : "yok");
}

static bool copy_bytes(JNIEnv *env, jbyteArray src, void *dst, int size, bool exact)
{
	memset(dst, 0, (size_t)size);
	if(!src)
		return false;
	jsize n = (*env)->GetArrayLength(env, src);
	if(exact ? n != size : (n <= 0 || n > size))
		return false;
	(*env)->GetByteArrayRegion(env, src, 0, n, (jbyte *)dst);
	return true;
}

static void free_session(JNIEnv *env, NinoSession *s)
{
	if(s->decoder)
		nino_decoder_destroy(s->decoder);
	if(s->listener)
		(*env)->DeleteGlobalRef(env, s->listener);
	nino_log_fini(&s->log);
	free(s);
}

JNIEXPORT jlong JNICALL
Java_com_ninotranslator_mobile_remoteplay_RemotePlayNative_nativeOpenSession(JNIEnv *env, jclass cls,
	jstring host, jbyteArray regist_key, jbyteArray morning, jbyteArray account_id, jint width, jint height,
	jboolean software, jint min_frame_interval_ms, jobject listener)
{
	set_open_error("");
	if(nino_lib_ready() != 0)
	{
		set_open_error("Remote Play library not initialized");
		return 0;
	}
	if(!host || !listener)
	{
		set_open_error("missing host or listener");
		return 0;
	}
	NinoSession *s = calloc(1, sizeof(*s));
	if(!s)
	{
		set_open_error("out of memory");
		return 0;
	}
	nino_log_init(&s->log, "oturum");
	jclass lcls = (*env)->GetObjectClass(env, listener);
	s->on_connected = (*env)->GetMethodID(env, lcls, "onConnected", "()V");
	s->on_pin = (*env)->GetMethodID(env, lcls, "onLoginPinRequest", "(Z)V");
	s->on_quit = (*env)->GetMethodID(env, lcls, "onQuit", "(ILjava/lang/String;)V");
	s->on_frame = (*env)->GetMethodID(env, lcls, "onFrame", "(Ljava/nio/ByteBuffer;IIIIZJ)V");
	(*env)->DeleteLocalRef(env, lcls);
	if(!s->on_connected || !s->on_pin || !s->on_quit || !s->on_frame)
	{
		(*env)->ExceptionClear(env);
		free_session(env, s);
		set_open_error("listener methods missing");
		return 0;
	}
	s->listener = (*env)->NewGlobalRef(env, listener);

	ChiakiConnectInfo info;
	memset(&info, 0, sizeof(info));
	info.ps5 = true;
	if(!copy_bytes(env, regist_key, info.regist_key, sizeof(info.regist_key), false)
		|| !copy_bytes(env, morning, info.morning, sizeof(info.morning), true)
		|| !copy_bytes(env, account_id, info.psn_account_id, sizeof(info.psn_account_id), true))
	{
		free_session(env, s);
		set_open_error("invalid registration data");
		return 0;
	}

	// Çözücü oturumdan önce kurulur; kurulamazsa oturum açılmaz.
	s->decoder = nino_decoder_create(width, height, software, min_frame_interval_ms, on_frame, s);
	if(!s->decoder)
	{
		free_session(env, s);
		set_open_error("failed to open the H.264 decoder");
		return 0;
	}

	chiaki_connect_video_profile_preset(&info.video_profile,
		height >= 1080 ? CHIAKI_VIDEO_RESOLUTION_PRESET_1080p : CHIAKI_VIDEO_RESOLUTION_PRESET_720p,
		CHIAKI_VIDEO_FPS_PRESET_30);
	info.video_profile.codec = CHIAKI_CODEC_H264;
	info.video_profile_auto_downgrade = true;
	info.enable_keyboard = false;
	info.enable_dualsense = false;
	info.audio_video_disabled = CHIAKI_AUDIO_DISABLED;
	info.auto_regist = false;
	info.holepunch_session = NULL;
	info.rudp_sock = NULL;
	info.packet_loss_max = 0.05;
	info.enable_idr_on_fec_failure = true;

	const char *h = (*env)->GetStringUTFChars(env, host, NULL);
	info.host = h;
	ChiakiErrorCode err = h ? chiaki_session_init(&s->session, &info, &s->log.log) : CHIAKI_ERR_MEMORY;
	if(h)
		(*env)->ReleaseStringUTFChars(env, host, h);
	if(err != CHIAKI_ERR_SUCCESS)
	{
		char msg[128];
		snprintf(msg, sizeof(msg), "session init failed: %s", chiaki_error_string(err));
		free_session(env, s);
		set_open_error(msg);
		return 0;
	}
	chiaki_session_set_event_cb(&s->session, on_event, s);
	chiaki_session_set_video_sample_cb(&s->session, on_video_sample, s);
	ChiakiCtrlDisplaySink sink = { .user = s, .cantdisplay_cb = on_cant_display };
	chiaki_session_ctrl_set_display_sink(&s->session, &sink);
	err = chiaki_session_start(&s->session);
	if(err != CHIAKI_ERR_SUCCESS)
	{
		char msg[128];
		snprintf(msg, sizeof(msg), "session start failed: %s", chiaki_error_string(err));
		chiaki_session_fini(&s->session);
		free_session(env, s);
		set_open_error(msg);
		return 0;
	}
	nino_logi("Oturum başlatıldı (%dx%d, %s çözücü)", width, height, software ? "yazılım" : "donanım");
	return (jlong)(intptr_t)s;
}

JNIEXPORT jstring JNICALL
Java_com_ninotranslator_mobile_remoteplay_RemotePlayNative_nativeOpenError(JNIEnv *env, jclass cls)
{
	pthread_mutex_lock(&error_lock);
	char copy[sizeof(open_error)];
	memcpy(copy, open_error, sizeof(copy));
	pthread_mutex_unlock(&error_lock);
	return copy[0] ? nino_jstring(env, copy) : NULL;
}

// Her oturum için bir kez, geri çağrının dışından çağrılır. Dönünce bir daha olay ya da kare gelmez.
JNIEXPORT void JNICALL
Java_com_ninotranslator_mobile_remoteplay_RemotePlayNative_nativeCloseSession(JNIEnv *env, jclass cls, jlong handle)
{
	NinoSession *s = (NinoSession *)(intptr_t)handle;
	if(!s)
		return;
	chiaki_session_stop(&s->session);
	chiaki_session_join(&s->session);
	chiaki_session_fini(&s->session);
	free_session(env, s);
	nino_logi("Oturum kapandı");
}

JNIEXPORT jint JNICALL
Java_com_ninotranslator_mobile_remoteplay_RemotePlayNative_nativeSetLoginPin(JNIEnv *env, jclass cls, jlong handle,
	jbyteArray pin)
{
	NinoSession *s = (NinoSession *)(intptr_t)handle;
	if(!s || !pin)
		return CHIAKI_ERR_INVALID_DATA;
	jsize n = (*env)->GetArrayLength(env, pin);
	uint8_t buf[16];
	if(n <= 0 || n > (jsize)sizeof(buf))
		return CHIAKI_ERR_INVALID_DATA;
	(*env)->GetByteArrayRegion(env, pin, 0, n, (jbyte *)buf);
	return (jint)chiaki_session_set_login_pin(&s->session, buf, (size_t)n);
}

JNIEXPORT jobjectArray JNICALL
Java_com_ninotranslator_mobile_remoteplay_RemotePlayNative_nativeSessionErrors(JNIEnv *env, jclass cls, jlong handle)
{
	NinoSession *s = (NinoSession *)(intptr_t)handle;
	if(!s)
	{
		jclass str = (*env)->FindClass(env, "java/lang/String");
		return (*env)->NewObjectArray(env, 0, str, NULL);
	}
	return nino_log_lines(env, &s->log);
}

JNIEXPORT jlong JNICALL
Java_com_ninotranslator_mobile_remoteplay_RemotePlayNative_nativeSessionFrames(JNIEnv *env, jclass cls, jlong handle)
{
	NinoSession *s = (NinoSession *)(intptr_t)handle;
	return s ? (jlong)nino_decoder_frames(s->decoder) : 0;
}

JNIEXPORT jboolean JNICALL
Java_com_ninotranslator_mobile_remoteplay_RemotePlayNative_nativeSessionSoftware(JNIEnv *env, jclass cls, jlong handle)
{
	NinoSession *s = (NinoSession *)(intptr_t)handle;
	return s ? (jboolean)nino_decoder_is_software(s->decoder) : JNI_FALSE;
}
