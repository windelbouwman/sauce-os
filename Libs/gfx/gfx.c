#include "gfx.h"
#include <SDL2/SDL.h>
#include <dlfcn.h>

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
    int audio_device;
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
    SDL_InitSubSystem(SDL_INIT_GAMECONTROLLER);
    gfx.window_width = width;
    gfx.window_height = height;
    gfx.window = SDL_CreateWindow(title, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, width, height, 0);
    gfx.renderer = SDL_CreateRenderer(gfx.window, -1, 0);
}

void gfx_poll(void) {
    SDL_Event event;

    // Reset click events
    gfx.key_click_count = 0;
    while (SDL_PollEvent(&event)) {
        switch (event.type) {
            case SDL_QUIT: {
                gfx_emit_key(KEY_APP_QUIT, true);
            } break;

            case SDL_MOUSEBUTTONDOWN:
            case SDL_MOUSEBUTTONUP: {
                Key key = KEY_NONE;
                if (event.button.button == SDL_BUTTON_LEFT) key = KEY_MOUSE_LEFT;
                if (event.button.button == SDL_BUTTON_MIDDLE) key = KEY_MOUSE_MIDDLE;
                if (event.button.button == SDL_BUTTON_RIGHT) key = KEY_MOUSE_RIGHT;
                if (event.button.button == SDL_BUTTON_X1) key = KEY_MOUSE_FORWARD;
                if (event.button.button == SDL_BUTTON_X2) key = KEY_MOUSE_BACK;
                if(key != KEY_NONE) gfx_emit_key(key, event.button.state == SDL_PRESSED);
            } break;

            case SDL_KEYDOWN:
            case SDL_KEYUP: {
                if (event.key.repeat) break;
                Key key = KEY_NONE;
                uint32_t sdlk = event.key.keysym.sym;
                if (sdlk >= SDLK_a && sdlk <= SDLK_z) key = sdlk - 'a' + KEY_A;
                if (sdlk >= SDLK_0 && sdlk <= SDLK_9) key = sdlk - '0' + KEY_0;
                if (sdlk == SDLK_SPACE) key = KEY_SPACE;
                if (sdlk == SDLK_ESCAPE) key = KEY_ESCAPE;
                if (sdlk == SDLK_LCTRL || sdlk == SDLK_RCTRL) key = KEY_CONTROL;
                if (sdlk == SDLK_LSHIFT || sdlk == SDLK_RSHIFT) key = KEY_SHIFT;
                if (sdlk == SDLK_LALT || sdlk == SDLK_RALT) key = KEY_ALT;
                if (sdlk == SDLK_LGUI || sdlk == SDLK_RGUI) key = KEY_WIN;
                if(key != KEY_NONE) gfx_emit_key(key, event.key.state == SDL_PRESSED);
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
        SDL_SetTextureScaleMode(gfx.texture, SDL_ScaleModeNearest);
    }

    SDL_UpdateTexture(gfx.texture, NULL, pixels, width * 3);
    SDL_RenderCopy(gfx.renderer, gfx.texture, NULL, NULL);
    SDL_RenderPresent(gfx.renderer);
}

static void gfx_audio_callback(void *user, uint8_t *stream, int len) {
    // Number of samples (one sample is 16 bit)
    uint32_t output_count = len / sizeof(int16_t);
    int16_t* output_buffer = (int16_t*)stream;

    uint32_t consumed_count = output_count;
    if (consumed_count > gfx.audio_count)
        consumed_count = gfx.audio_count;

    // Copy queued audio samples
    for (uint32_t i = 0; i < consumed_count; ++i) {
        output_buffer[i] = gfx.audio_buffer[i];
    }

    // Clear remaining output samples
    for(uint32_t i = consumed_count; i < output_count; ++i) {
        output_buffer[i] = 0;
    }

    // Update internal audio queue
    if (consumed_count == 0) {
        // Nothing consumed, so nothing to move
    } else if (consumed_count == gfx.audio_count) {
        // Everything is consumed, so no need to move
        gfx.audio_count = 0;
    } else {
        // Some samples are consumed,
        // remove them and move the remaining samples to the start
        uint32_t remaining_count = gfx.audio_count - consumed_count;
        for (uint32_t i = 0; i < remaining_count; ++i) {
            gfx.audio_buffer[i] = gfx.audio_buffer[i + consumed_count];
        }
        gfx.audio_count = remaining_count;
    }
}


void gfx_play(int count, int16_t *samples) {
    if(!gfx.audio_device) {
        // Init audio
        SDL_AudioSpec audio_spec = {
            .freq = 48000,
            .format = AUDIO_S16,
            .channels = 1,
            .callback = gfx_audio_callback,
        };
        gfx.audio_device = SDL_OpenAudioDevice(NULL, 0, &audio_spec, NULL, 0);
        SDL_PauseAudioDevice(gfx.audio_device, 0);
    }

    SDL_LockAudioDevice(gfx.audio_device);

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

    SDL_UnlockAudioDevice(gfx.audio_device);
}

void gfx_sync(double interval) {
    uint64_t interval_ms = interval * 1000;
    SDL_Delay(interval_ms);
}

void gfx_quit(void) {
    SDL_DestroyTexture(gfx.texture);
    SDL_DestroyRenderer(gfx.renderer);
    SDL_Quit();
}
