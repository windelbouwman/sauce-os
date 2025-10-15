#include "gfx.h"
#include <SDL3/SDL.h>
#include <dlfcn.h>
#include <stdio.h>

#define LIB_SYM(NAME) typeof(NAME) *NAME
#define ARRAY_COUNT(A) (sizeof(A) / sizeof(A[0]))

typedef struct {
    // Handles
    SDL_Window *window;
    SDL_Renderer *renderer;
    SDL_Texture *texture;

    uint32_t window_width, window_height;
    uint32_t texture_width, texture_height;

    // ordered list of samples
    SDL_AudioStream *audio_stream;
    uint32_t audio_count;
    int16_t audio_buffer[48000];

    // Down Events
    uint32_t key_click_count;
    Key key_click[16];

    // Down state
    uint8_t key_down[KEY_COUNT];
} Gfx_State;

static Gfx_State gfx;

static void gfx_emit_key(Key key, bool down) {
    bool was_up = !gfx.key_down[key];
    if(down && was_up && gfx.key_click_count < ARRAY_COUNT(gfx.key_click)) gfx.key_click[gfx.key_click_count++] = key;
    gfx.key_down[key] = down;
}

void gfx_init(const char *title, int width, int height) {
    if(gfx.window) return;

    // Load lib dynamically so that we don't have to link to sdl3 directly
    SDL_InitSubSystem(SDL_INIT_EVENTS);
    SDL_InitSubSystem(SDL_INIT_AUDIO);
    SDL_InitSubSystem(SDL_INIT_VIDEO);
    SDL_InitSubSystem(SDL_INIT_GAMEPAD);
    gfx.window_width = width;
    gfx.window_height = height;
    gfx.window = SDL_CreateWindow(title, width, height, 0);
    gfx.renderer = SDL_CreateRenderer(gfx.window, NULL);
}

void gfx_poll(void) {
    SDL_Event event;

    // Reset click events
    gfx.key_click_count = 0;
    while (SDL_PollEvent(&event)) {
        switch (event.type) {
            case SDL_EVENT_QUIT: {
                gfx_emit_key(KEY_APP_QUIT, true);
            } break;

            case SDL_EVENT_MOUSE_BUTTON_DOWN:
            case SDL_EVENT_MOUSE_BUTTON_UP: {
                Key key = KEY_NONE;
                if (event.button.button == SDL_BUTTON_LEFT) key = KEY_MOUSE_LEFT;
                if (event.button.button == SDL_BUTTON_MIDDLE) key = KEY_MOUSE_MIDDLE;
                if (event.button.button == SDL_BUTTON_RIGHT) key = KEY_MOUSE_RIGHT;
                if (event.button.button == SDL_BUTTON_X1) key = KEY_MOUSE_FORWARD;
                if (event.button.button == SDL_BUTTON_X2) key = KEY_MOUSE_BACK;
                if(key != KEY_NONE) gfx_emit_key(key, event.button.down);
            } break;

            case SDL_EVENT_KEY_DOWN:
            case SDL_EVENT_KEY_UP: {
                if (event.key.repeat) break;
                Key key = KEY_NONE;
                uint32_t sdlk = event.key.key;
                if (sdlk >= SDLK_A && sdlk <= SDLK_Z) key = sdlk - 'a' + KEY_A;
                if (sdlk >= SDLK_0 && sdlk <= SDLK_9) key = sdlk - '0' + KEY_0;
                if (sdlk == SDLK_SPACE) key = KEY_SPACE;
                if (sdlk == SDLK_ESCAPE) key = KEY_ESCAPE;
                if (sdlk == SDLK_LCTRL || sdlk == SDLK_RCTRL) key = KEY_CONTROL;
                if (sdlk == SDLK_LSHIFT || sdlk == SDLK_RSHIFT) key = KEY_SHIFT;
                if (sdlk == SDLK_LALT || sdlk == SDLK_RALT) key = KEY_ALT;
                if (sdlk == SDLK_LGUI || sdlk == SDLK_RGUI) key = KEY_WIN;
                if(key != KEY_NONE) gfx_emit_key(key, event.key.down);
            } break;
        }
    }
}

bool gfx_input_down(Key key) {
    return gfx.key_down[key];
}

bool gfx_input_click(Key key) {
    for (uint32_t i = 0; i < gfx.key_click_count; ++i) {
        if (gfx.key_click[i] == key) return true;
    }
    return false;
}

void gfx_draw(int width, int height, uint8_t *pixels) {
    if(!gfx.texture ||width != gfx.texture_width || height != gfx.texture_height) {
        if(gfx.texture) SDL_DestroyTexture(gfx.texture);
        gfx.texture_width = width;
        gfx.texture_height = height;
        gfx.texture = SDL_CreateTexture(gfx.renderer, SDL_PIXELFORMAT_RGB24, SDL_TEXTUREACCESS_STREAMING, width, height);
        SDL_SetTextureScaleMode(gfx.texture, SDL_SCALEMODE_NEAREST);
    }

    SDL_UpdateTexture(gfx.texture, NULL, pixels, width * 3);
    SDL_RenderTexture(gfx.renderer, gfx.texture, NULL, NULL);
    SDL_RenderPresent(gfx.renderer);
}

static void gfx_audio_callback(void *user, SDL_AudioStream *stream, int additional_amount, int total_amount) {
    SDL_LockAudioStream(stream);
    uint32_t count = additional_amount / sizeof(int16_t);
    if (count > gfx.audio_count)
        count = gfx.audio_count;
    if (count > 0) {
        SDL_PutAudioStreamData(stream, gfx.audio_buffer, count * sizeof(int16_t));
        uint32_t remaining = gfx.audio_count - count;
        memmove(gfx.audio_buffer, gfx.audio_buffer + count,
                remaining * sizeof(int16_t));
        gfx.audio_count = remaining;
    }
    SDL_UnlockAudioStream(stream);
}


void gfx_play(int count, int16_t *samples) {
    if(!gfx.audio_stream) {
        // Init audio
        SDL_AudioSpec audio_spec = {
            .format = SDL_AUDIO_S16,
            .channels = 1,
            .freq = 48000,
        };
        gfx.audio_stream = SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &audio_spec, gfx_audio_callback, 0);
        SDL_AudioDeviceID audio_device = SDL_GetAudioStreamDevice(gfx.audio_stream);
        SDL_ResumeAudioDevice(audio_device);
    }

    SDL_LockAudioStream(gfx.audio_stream);

    // Limit count
    if (count > ARRAY_COUNT(gfx.audio_buffer))
        count = ARRAY_COUNT(gfx.audio_buffer);

    // Reserve space for more samples if needed
    while (gfx.audio_count < count) {
        gfx.audio_buffer[gfx.audio_count++] = 0;
    }

    for (uint32_t i = 0; i < count; ++i) {
        gfx.audio_buffer[i] += samples[i];
    }

    SDL_UnlockAudioStream(gfx.audio_stream);
}

void gfx_sync(double interval) {
    uint64_t interval_us = interval * 1e6;
    SDL_DelayPrecise(interval_us * 1000);
}

void gfx_quit(void) {
    SDL_DestroyTexture(gfx.texture);
    SDL_DestroyRenderer(gfx.renderer);
    SDL_Quit();
}
