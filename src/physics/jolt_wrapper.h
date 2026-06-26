// extern "C" surface over Jolt Physics. Zig only ever sees this header (via @cImport) —
// no Jolt C++ type crosses the boundary. See jolt_wrapper.cpp for the implementation and
// collision_layers.zig for the ObjectLayer matrix this wrapper hard-codes.
#ifndef STRIFE_JOLT_WRAPPER_H
#define STRIFE_JOLT_WRAPPER_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct JoltCtx JoltCtx;
typedef struct JoltCharacter JoltCharacter;

// Object layers — fixed 5-layer matrix, see collision_layers.zig for the Zig-side enum.
enum {
    JOLT_LAYER_STATIC = 0,
    JOLT_LAYER_PLAYER = 1,
    JOLT_LAYER_ENEMY = 2,
    JOLT_LAYER_PROJECTILE = 3,
    JOLT_LAYER_TRIGGER = 4,
    JOLT_LAYER_COUNT = 5,
};

JoltCtx* jolt_init(void);
void jolt_deinit(JoltCtx* ctx);
void jolt_step(JoltCtx* ctx, float dt, int substeps);

// Bodies. inLayer is one of JOLT_LAYER_*; is_sensor=true creates a trigger volume
// (still goes through collision filtering but never gets a physical contact response).
uint32_t jolt_add_box(JoltCtx* ctx, float hw, float hh, float hd, float mass,
                       float px, float py, float pz, int layer, bool is_static, bool is_sensor);
void jolt_remove_body(JoltCtx* ctx, uint32_t body_id);

void jolt_get_position(JoltCtx* ctx, uint32_t body_id, float* out_xyz);
void jolt_get_rotation(JoltCtx* ctx, uint32_t body_id, float* out_xyzw);
void jolt_set_position(JoltCtx* ctx, uint32_t body_id, float px, float py, float pz);
void jolt_set_linear_velocity(JoltCtx* ctx, uint32_t body_id, float vx, float vy, float vz);
void jolt_get_linear_velocity(JoltCtx* ctx, uint32_t body_id, float* out_xyz);
bool jolt_is_active(JoltCtx* ctx, uint32_t body_id);

// Raycasts.
typedef struct {
    uint32_t body_id;
    float point[3];
    float normal[3];
    float fraction;
} JoltRayHit;

// Closest-hit cast. Returns false if nothing was hit.
bool jolt_raycast(JoltCtx* ctx, float ox, float oy, float oz, float dx, float dy, float dz,
                   float max_dist, JoltRayHit* out_hit);

// Multi-hit cast. Writes up to max_hits into out_hits, returns the number written.
int jolt_raycast_all(JoltCtx* ctx, float ox, float oy, float oz, float dx, float dy, float dz,
                      float max_dist, JoltRayHit* out_hits, int max_hits);

// Character controller (Jolt CharacterVirtual — kinematic, not a rigid body).
JoltCharacter* jolt_character_create(JoltCtx* ctx, float radius, float height,
                                      float px, float py, float pz);
void jolt_character_destroy(JoltCtx* ctx, JoltCharacter* ch);
void jolt_character_set_velocity(JoltCharacter* ch, float vx, float vy, float vz);
void jolt_character_get_velocity(JoltCharacter* ch, float* out_xyz);
// Applies gravity, resolves collisions/stairs/slopes, and integrates position by dt.
void jolt_character_update(JoltCtx* ctx, JoltCharacter* ch, float dt, float gravity_y);
void jolt_character_get_position(JoltCharacter* ch, float* out_xyz);
bool jolt_character_is_grounded(JoltCharacter* ch);

// Trigger events, drained from the contact-listener queue populated during jolt_step.
typedef struct {
    uint32_t trigger_body;
    uint32_t other_body;
    bool is_enter; // false = exit
} JoltTriggerEvent;

// Pops one queued trigger event into *out_event. Returns false when the queue is empty.
bool jolt_poll_trigger_event(JoltCtx* ctx, JoltTriggerEvent* out_event);

#ifdef __cplusplus
}
#endif

#endif // STRIFE_JOLT_WRAPPER_H
