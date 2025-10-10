#include <SDL3/SDL.h>
#include <stdlib.h>
#include <dlfcn.h>

#define LIB_SYM(NAME) typeof(NAME) *NAME

typedef enum {
    KEY_NONE,

    // Keys
    KEY_0,
    KEY_1,
    KEY_2,
    KEY_3,
    KEY_4,
    KEY_5,
    KEY_6,
    KEY_7,
    KEY_8,
    KEY_9,

    KEY_A,
    KEY_B,
    KEY_C,
    KEY_D,
    KEY_E,
    KEY_F,
    KEY_G,
    KEY_H,
    KEY_I,
    KEY_J,
    KEY_K,
    KEY_L,
    KEY_M,
    KEY_N,
    KEY_O,
    KEY_P,
    KEY_Q,
    KEY_R,
    KEY_S,
    KEY_T,
    KEY_U,
    KEY_V,
    KEY_W,
    KEY_X,
    KEY_Y,
    KEY_Z,

    // Special Keys
    KEY_UP,
    KEY_DOWN,
    KEY_LEFT,
    KEY_RIGHT,
    KEY_SPACE,
    KEY_ESCAPE,

    // Mouse
    KEY_MOUSE_LEFT,
    KEY_MOUSE_MIDDLE,
    KEY_MOUSE_RIGHT,
    KEY_MOUSE_FORWARD,
    KEY_MOUSE_BACK,

    // Mods
    KEY_SHIFT,
    KEY_CONTROL,
    KEY_WIN,
    KEY_ALT,


    // Special Keys
    KEY_APP_QUIT,

    KEY_COUNT,
} Key;

typedef struct {
    // Handles
    SDL_Window *window;
    SDL_Renderer *renderer;
    SDL_Texture *texture;

    uint32_t width, height;
    uint32_t texture_width, texture_height;

    // Input
    uint8_t key_down[KEY_COUNT];
    uint8_t key_click[KEY_COUNT];

    // Dynamic library
    void *lib;
    LIB_SYM(SDL_InitSubSystem);
    LIB_SYM(SDL_Quit);
    LIB_SYM(SDL_CreateWindow);
    LIB_SYM(SDL_CreateRenderer);
    LIB_SYM(SDL_DestroyRenderer);
    LIB_SYM(SDL_DestroyTexture);
    LIB_SYM(SDL_CreateTexture);
    LIB_SYM(SDL_RenderPresent);
    LIB_SYM(SDL_RenderTexture);
    LIB_SYM(SDL_PollEvent);
    LIB_SYM(SDL_UpdateTexture);
    LIB_SYM(SDL_DelayPrecise);
    LIB_SYM(SDL_SetTextureScaleMode);
} Gfx_State;

static Gfx_State gfx;

static void gfx_emit_key(Key key, bool down) {
    bool was_up = !gfx.key_down[key];
    if(down && was_up) gfx.key_click[key] = 1;
    gfx.key_down[key] = down;
}

void gfx_init(const char *title, int width, int height) {
    if(gfx.window) return;
    gfx.lib = dlopen("libSDL3.so", RTLD_LOCAL | RTLD_NOW);

#define LIB_LOAD(NAME) gfx.NAME = dlsym(gfx.lib, #NAME)
    LIB_LOAD(SDL_InitSubSystem);
    LIB_LOAD(SDL_Quit);
    LIB_LOAD(SDL_CreateWindow);
    LIB_LOAD(SDL_CreateRenderer);
    LIB_LOAD(SDL_DestroyRenderer);
    LIB_LOAD(SDL_DestroyTexture);
    LIB_LOAD(SDL_CreateTexture);
    LIB_LOAD(SDL_RenderPresent);
    LIB_LOAD(SDL_RenderTexture);
    LIB_LOAD(SDL_PollEvent);
    LIB_LOAD(SDL_UpdateTexture);
    LIB_LOAD(SDL_DelayPrecise);
    LIB_LOAD(SDL_SetTextureScaleMode);
#undef LIB_LOAD

    gfx.SDL_InitSubSystem(SDL_INIT_EVENTS);
    gfx.SDL_InitSubSystem(SDL_INIT_AUDIO);
    gfx.SDL_InitSubSystem(SDL_INIT_VIDEO);
    gfx.SDL_InitSubSystem(SDL_INIT_GAMEPAD);
    gfx.width = width;
    gfx.height = height;
    gfx.window = gfx.SDL_CreateWindow(title, width, height, 0);
    gfx.renderer = gfx.SDL_CreateRenderer(gfx.window, NULL);
}

void gfx_poll(void) {
    SDL_Event event;

    // Reset click events
    for(Key key = 0; key < KEY_COUNT; ++key) {
        gfx.key_click[key] = 0;
    }
    while (gfx.SDL_PollEvent(&event)) {
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
    return gfx.key_click[key];
}

void gfx_draw(int width, int height, uint8_t *pixels) {
    if(!gfx.texture ||width != gfx.texture_width || height != gfx.texture_height) {
        if(gfx.texture) gfx.SDL_DestroyTexture(gfx.texture);
        gfx.texture_width = width;
        gfx.texture_height = height;
        gfx.texture = gfx.SDL_CreateTexture(gfx.renderer, SDL_PIXELFORMAT_RGB24, SDL_TEXTUREACCESS_STREAMING, width, height);
        gfx.SDL_SetTextureScaleMode(gfx.texture, SDL_SCALEMODE_NEAREST);
    }

    gfx.SDL_UpdateTexture(gfx.texture, NULL, pixels, width * 3);
    gfx.SDL_RenderTexture(gfx.renderer, gfx.texture, NULL, NULL);
    gfx.SDL_RenderPresent(gfx.renderer);
}

void gfx_sync(double interval) {
    uint64_t interval_us = interval * 1e6;
    gfx.SDL_DelayPrecise(interval_us * 1000);
}

void gfx_quit(void) {
    gfx.SDL_DestroyTexture(gfx.texture);
    gfx.SDL_DestroyRenderer(gfx.renderer);
    gfx.SDL_Quit();
}
