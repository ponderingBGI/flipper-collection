#include <furi.h>
#include <furi_hal.h>
#include <gui/gui.h>
#include <input/input.h>
#include <notification/notification_messages.h>
#include <furi_hal_usb_hid.h>

#define TAG "MouseKeyboardJiggler"

typedef enum {
    MouseJigglerEventTypeTick,
    MouseJigglerEventTypeKey,
} MouseJigglerEventType;

typedef struct {
    MouseJigglerEventType type;
    InputEvent input;
} MouseJigglerEvent;

typedef enum {
    ModeMouseJiggle,
    ModeWASDKeys,
    ModeBoth
} OperationMode;

typedef struct {
    bool running;
    OperationMode mode;
    uint32_t tick_count;
    uint32_t wasd_count;
    uint32_t mouse_count;
    FuriMutex* mutex;
    NotificationApp* notifications;
} MouseJigglerState;

// WASD key codes for HID
static const uint8_t wasd_keys[] = {
    HID_KEYBOARD_W,
    HID_KEYBOARD_A, 
    HID_KEYBOARD_S,
    HID_KEYBOARD_D
};

static void mousejiggler_render_callback(Canvas* canvas, void* ctx) {
    MouseJigglerState* state = ctx;
    furi_mutex_acquire(state->mutex, FuriWaitForever);

    canvas_clear(canvas);
    
    // Header
    canvas_set_font(canvas, FontPrimary);
    canvas_draw_str(canvas, 6, 12, "Mouse and keyboard Jiggler");
    
    // Status indicator
    canvas_set_font(canvas, FontSecondary);
    if(state->running) {
        canvas_draw_str(canvas, 2, 10, "ACTIVE");
        
        // Mode display with icons
        canvas_draw_str(canvas, 2, 25, "Mode:");
        switch(state->mode) {
            case ModeMouseJiggle:
                canvas_draw_str(canvas, 35, 25, "🖱️ Mouse Only");
                break;
            case ModeWASDKeys:
                canvas_draw_str(canvas, 35, 25, "⌨️ WASD Only");
                break;
            case ModeBoth:
                canvas_draw_str(canvas, 35, 25, "🖱️⌨️ Both");
                break;
        }
        
        // Statistics
        char stats_str[32];
        snprintf(stats_str, sizeof(stats_str), "Mouse: %lu", state->mouse_count);
        canvas_draw_str(canvas, 2, 37, stats_str);
        
        snprintf(stats_str, sizeof(stats_str), "WASD: %lu", state->wasd_count);
        canvas_draw_str(canvas, 2, 47, stats_str);
        
        snprintf(stats_str, sizeof(stats_str), "Uptime: %lu s", state->tick_count / 10);
        canvas_draw_str(canvas, 2, 57, stats_str);
        
    } else {
        canvas_draw_str(canvas, 2, 10, "STOPPED");
        
        canvas_draw_str(canvas, 2, 25, "Press OK to start");
        canvas_draw_str(canvas, 2, 37, "Left/Right: Change mode");
        canvas_draw_str(canvas, 2, 47, "Back: Exit");
    }
    
    // Mode indicator at bottom
    canvas_draw_line(canvas, 0, 52, 128, 52);
    const char* mode_text = "";
    switch(state->mode) {
        case ModeMouseJiggle: mode_text = "🖱️ MOUSE"; break;
        case ModeWASDKeys: mode_text = "⌨️ WASD"; break;
        case ModeBoth: mode_text = "🖱️⌨️ COMBO"; break;
    }
    canvas_draw_str_aligned(canvas, 64, 60, AlignCenter, AlignCenter, mode_text);

    furi_mutex_release(state->mutex);
}

static void mousejiggler_input_callback(InputEvent* input_event, void* ctx) {
    FuriMessageQueue* event_queue = ctx;
    MouseJigglerEvent event = {.type = MouseJigglerEventTypeKey, .input = *input_event};
    furi_message_queue_put(event_queue, &event, FuriWaitForever);
}

static void mousejiggler_perform_mouse_jiggle(void) {
    // Random small mouse movements
    int8_t dx = (furi_hal_random_get() % 5) - 2; // -2 to +2
    int8_t dy = (furi_hal_random_get() % 5) - 2; // -2 to +2
    
    if(dx != 0 || dy != 0) {
        furi_hal_hid_mouse_move(dx, dy);
        furi_delay_ms(10);
        furi_hal_hid_mouse_move(-dx, -dy); // Return to original position
    }
}

static void mousejiggler_perform_wasd_press(void) {
    // Select random WASD key
    uint8_t key_index = furi_hal_random_get() % 4;
    uint8_t key = wasd_keys[key_index];
    
    // Press and release key
    furi_hal_hid_kb_press(key);
    furi_delay_ms(50);
    furi_hal_hid_kb_release(key);
}

static void mousejiggler_timer_cb(void* ctx) {
    FuriMessageQueue* queue = ctx;
    MouseJigglerEvent event = {.type = MouseJigglerEventTypeTick};
    furi_message_queue_put(queue, &event, 0);
}

int32_t mousejiggler_app(void* p) {
    UNUSED(p);
    
    // Initialize state
    MouseJigglerState* state = malloc(sizeof(MouseJigglerState));
    state->running = false;
    state->mode = ModeBoth;
    state->tick_count = 0;
    state->wasd_count = 0;
    state->mouse_count = 0;
    state->mutex = furi_mutex_alloc(FuriMutexTypeNormal);
    state->notifications = furi_record_open(RECORD_NOTIFICATION);
    
    // Create event queue
    FuriMessageQueue* event_queue = furi_message_queue_alloc(8, sizeof(MouseJigglerEvent));
    
    // Create timer
    FuriTimer* timer = furi_timer_alloc(
        mousejiggler_timer_cb,
        FuriTimerTypePeriodic,
        event_queue
    );
    
    // Setup GUI
    Gui* gui = furi_record_open(RECORD_GUI);
    ViewPort* view_port = view_port_alloc();
    view_port_draw_callback_set(view_port, mousejiggler_render_callback, state);
    view_port_input_callback_set(view_port, mousejiggler_input_callback, event_queue);
    gui_add_view_port(gui, view_port, GuiLayerFullscreen);
    
    // Enable USB HID
    furi_hal_usb_set_config(&usb_hid, NULL);
    
    // Main event loop
    MouseJigglerEvent event;
    bool running = true;
    
    while(running) {
        FuriStatus event_status = furi_message_queue_get(event_queue, &event, 100);
        
        if(event_status == FuriStatusOk) {
            if(event.type == MouseJigglerEventTypeKey) {
                if(event.input.type == InputTypePress) {
                    switch(event.input.key) {
                        case InputKeyOk:
                            furi_mutex_acquire(state->mutex, FuriWaitForever);
                            state->running = !state->running;
                            if(state->running) {
                                furi_timer_start(timer, 100); // 100ms intervals
                                notification_message(state->notifications, &sequence_success);
                            } else {
                                furi_timer_stop(timer);
                                notification_message(state->notifications, &sequence_error);
                            }
                            furi_mutex_release(state->mutex);
                            break;
                            
                        case InputKeyLeft:
                            furi_mutex_acquire(state->mutex, FuriWaitForever);
                            if(state->mode == ModeMouseJiggle) {
                                state->mode = ModeBoth;
                            } else if(state->mode == ModeWASDKeys) {
                                state->mode = ModeMouseJiggle;
                            } else {
                                state->mode = ModeWASDKeys;
                            }
                            notification_message(state->notifications, &sequence_success);
                            furi_mutex_release(state->mutex);
                            break;
                            
                        case InputKeyRight:
                            furi_mutex_acquire(state->mutex, FuriWaitForever);
                            if(state->mode == ModeMouseJiggle) {
                                state->mode = ModeWASDKeys;
                            } else if(state->mode == ModeWASDKeys) {
                                state->mode = ModeBoth;
                            } else {
                                state->mode = ModeMouseJiggle;
                            }
                            notification_message(state->notifications, &sequence_success);
                            furi_mutex_release(state->mutex);
                            break;
                            
                        case InputKeyBack:
                            running = false;
                            break;
                            
                        default:
                            break;
                    }
                }
            } else if(event.type == MouseJigglerEventTypeTick) {
                furi_mutex_acquire(state->mutex, FuriWaitForever);
                if(state->running) {
                    state->tick_count++;
                    
                    // Perform actions based on mode (every 1-3 seconds randomly)
                    if(state->tick_count % (10 + (furi_hal_random_get() % 20)) == 0) {
                        if(state->mode == ModeMouseJiggle || state->mode == ModeBoth) {
                            mousejiggler_perform_mouse_jiggle();
                            state->mouse_count++;
                        }
                        
                        if(state->mode == ModeWASDKeys || state->mode == ModeBoth) {
                            mousejiggler_perform_wasd_press();
                            state->wasd_count++;
                        }
                    }
                }
                furi_mutex_release(state->mutex);
            }
        }
        
        view_port_update(view_port);
    }
    
    // Cleanup
    furi_timer_free(timer);
    gui_remove_view_port(gui, view_port);
    view_port_free(view_port);
    furi_record_close(RECORD_GUI);
    furi_record_close(RECORD_NOTIFICATION);
    furi_message_queue_free(event_queue);
    furi_mutex_free(state->mutex);
    free(state);
    
    return 0;
}
