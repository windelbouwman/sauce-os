#pragma once
#include <stdint.h>
#include <stdbool.h>

typedef enum {
    KEY_NONE,

    // Normal Keys
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

// Create a window of a given size
void gfx_init(const char *title, int width, int height);

// Poll input
void gfx_poll(void);

// Check if a key or button is currently pressed down
bool gfx_input_down(Key key);

// Check if a key or button was pressed for the first time
bool gfx_input_click(Key key);

// Draw pixesl to the screen
// The image is scaled to fit the window
void gfx_draw(int width, int height, uint8_t *pixels);

// Play 16bit single channel audio samples
void gfx_play(int count, int16_t *samples);

// Wait for the next frame at the given interval
void gfx_sync(double interval);

// Close window
void gfx_quit(void);
