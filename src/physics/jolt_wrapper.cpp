// extern "C" implementation over Jolt Physics — see jolt_wrapper.h for the surface Zig
// actually calls. Layer matrix follows the HelloWorld sample pattern (BPLayerInterfaceImpl
// etc.) but configured via Jolt's *Table helper classes instead of hand-written switches,
// since the engine's layer set (Static/Player/Enemy/Projectile/Trigger) is fixed up front.
#include <Jolt/Jolt.h>
#include <Jolt/RegisterTypes.h>
#include <Jolt/Core/Factory.h>
#include <Jolt/Core/TempAllocator.h>
#include <Jolt/Core/JobSystemThreadPool.h>
#include <Jolt/Physics/PhysicsSettings.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/Physics/Collision/ObjectLayerPairFilterTable.h>
#include <Jolt/Physics/Collision/BroadPhase/BroadPhaseLayerInterfaceTable.h>
#include <Jolt/Physics/Collision/BroadPhase/ObjectVsBroadPhaseLayerFilterTable.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/Collision/Shape/CapsuleShape.h>
#include <Jolt/Physics/Collision/Shape/RotatedTranslatedShape.h>
#include <Jolt/Physics/Collision/RayCast.h>
#include <Jolt/Physics/Collision/CastResult.h>
#include <Jolt/Physics/Collision/CollisionCollectorImpl.h>
#include <Jolt/Physics/Collision/CollideShape.h>
#include <Jolt/Physics/Collision/Shape/SphereShape.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Body/BodyActivationListener.h>
#include <Jolt/Physics/Character/CharacterVirtual.h>

#include <thread>
#include <vector>
#include <mutex>
#include <unordered_set>
#include <cstring>

#include "jolt_wrapper.h"

using namespace JPH;

namespace {

constexpr uint kNumBroadPhaseLayers = 2; // 0 = static, 1 = moving
constexpr BroadPhaseLayer kBPStatic(0);
constexpr BroadPhaseLayer kBPMoving(1);

ObjectLayerPairFilterTable* makeObjectLayerPairFilter() {
    auto* table = new ObjectLayerPairFilterTable(JOLT_LAYER_COUNT);
    // Documented matrix: Static collides with everything that moves; Trigger
    // (sensor) volumes never fire against Static or other Triggers, only the
    // dynamic gameplay layers; Projectile doesn't collide with itself.
    table->EnableCollision(JOLT_LAYER_STATIC, JOLT_LAYER_PLAYER);
    table->EnableCollision(JOLT_LAYER_STATIC, JOLT_LAYER_ENEMY);
    table->EnableCollision(JOLT_LAYER_STATIC, JOLT_LAYER_PROJECTILE);
    table->EnableCollision(JOLT_LAYER_PLAYER, JOLT_LAYER_ENEMY);
    table->EnableCollision(JOLT_LAYER_PLAYER, JOLT_LAYER_PROJECTILE);
    table->EnableCollision(JOLT_LAYER_PLAYER, JOLT_LAYER_TRIGGER);
    table->EnableCollision(JOLT_LAYER_ENEMY, JOLT_LAYER_PROJECTILE);
    table->EnableCollision(JOLT_LAYER_ENEMY, JOLT_LAYER_TRIGGER);
    table->EnableCollision(JOLT_LAYER_PROJECTILE, JOLT_LAYER_TRIGGER);
    return table;
}

BroadPhaseLayerInterfaceTable* makeBroadPhaseLayerInterface() {
    auto* table = new BroadPhaseLayerInterfaceTable(JOLT_LAYER_COUNT, kNumBroadPhaseLayers);
    table->MapObjectToBroadPhaseLayer(JOLT_LAYER_STATIC, kBPStatic);
    table->MapObjectToBroadPhaseLayer(JOLT_LAYER_PLAYER, kBPMoving);
    table->MapObjectToBroadPhaseLayer(JOLT_LAYER_ENEMY, kBPMoving);
    table->MapObjectToBroadPhaseLayer(JOLT_LAYER_PROJECTILE, kBPMoving);
    table->MapObjectToBroadPhaseLayer(JOLT_LAYER_TRIGGER, kBPMoving);
    return table;
}

struct TriggerListener final : public ContactListener {
    std::mutex mutex;
    std::vector<JoltTriggerEvent> queue;
    std::unordered_set<uint32_t> sensor_bodies;

    bool isSensor(const Body& b) const {
        return sensor_bodies.count(b.GetID().GetIndexAndSequenceNumber()) != 0;
    }

    void push(const Body& a, const Body& b, bool is_enter) {
        bool a_sensor = isSensor(a), b_sensor = isSensor(b);
        if (!a_sensor && !b_sensor) return;
        std::lock_guard<std::mutex> lock(mutex);
        if (a_sensor) queue.push_back({a.GetID().GetIndexAndSequenceNumber(), b.GetID().GetIndexAndSequenceNumber(), is_enter});
        if (b_sensor) queue.push_back({b.GetID().GetIndexAndSequenceNumber(), a.GetID().GetIndexAndSequenceNumber(), is_enter});
    }

    virtual void OnContactAdded(const Body& inBody1, const Body& inBody2, const ContactManifold&, ContactSettings&) override {
        push(inBody1, inBody2, true);
    }
    virtual void OnContactRemoved(const SubShapeIDPair& inPair) override {
        // Body lookup at removal time isn't reliable (bodies may already be gone),
        // so membership is tested purely against the sensor_bodies set we maintain.
        uint32_t id1 = inPair.GetBody1ID().GetIndexAndSequenceNumber();
        uint32_t id2 = inPair.GetBody2ID().GetIndexAndSequenceNumber();
        bool s1 = sensor_bodies.count(id1) != 0, s2 = sensor_bodies.count(id2) != 0;
        if (!s1 && !s2) return;
        std::lock_guard<std::mutex> lock(mutex);
        if (s1) queue.push_back({id1, id2, false});
        if (s2) queue.push_back({id2, id1, false});
    }
};

} // namespace

struct JoltCtx {
    BroadPhaseLayerInterfaceTable* bp_layer_interface;
    ObjectVsBroadPhaseLayerFilterTable* obj_vs_bp_filter;
    ObjectLayerPairFilterTable* obj_layer_pair_filter;
    PhysicsSystem physics_system;
    TempAllocatorImpl temp_allocator{10 * 1024 * 1024};
    JobSystemThreadPool job_system{cMaxPhysicsJobs, cMaxPhysicsBarriers,
        static_cast<int>(std::max(1u, std::thread::hardware_concurrency() - 1))};
    TriggerListener trigger_listener;
};

struct JoltCharacter {
    Ref<CharacterVirtual> character;
};

extern "C" {

JoltCtx* jolt_init(void) {
    static bool types_registered = false;
    if (!types_registered) {
        RegisterDefaultAllocator();
        Factory::sInstance = new Factory();
        RegisterTypes();
        types_registered = true;
    }

    auto* ctx = new JoltCtx();
    ctx->bp_layer_interface = makeBroadPhaseLayerInterface();
    ctx->obj_layer_pair_filter = makeObjectLayerPairFilter();
    ctx->obj_vs_bp_filter = new ObjectVsBroadPhaseLayerFilterTable(
        *ctx->bp_layer_interface, kNumBroadPhaseLayers,
        *ctx->obj_layer_pair_filter, JOLT_LAYER_COUNT);

    const uint cMaxBodies = 65536;
    const uint cNumBodyMutexes = 0;
    const uint cMaxBodyPairs = 65536;
    const uint cMaxContactConstraints = 10240;
    ctx->physics_system.Init(cMaxBodies, cNumBodyMutexes, cMaxBodyPairs, cMaxContactConstraints,
        *ctx->bp_layer_interface, *ctx->obj_vs_bp_filter, *ctx->obj_layer_pair_filter);
    ctx->physics_system.SetContactListener(&ctx->trigger_listener);
    return ctx;
}

void jolt_deinit(JoltCtx* ctx) {
    delete ctx->obj_vs_bp_filter;
    delete ctx->obj_layer_pair_filter;
    delete ctx->bp_layer_interface;
    delete ctx;
}

void jolt_step(JoltCtx* ctx, float dt, int substeps) {
    ctx->physics_system.Update(dt, substeps, &ctx->temp_allocator, &ctx->job_system);
}

uint32_t jolt_add_box(JoltCtx* ctx, float hw, float hh, float hd, float mass,
                       float px, float py, float pz, int layer, bool is_static, bool is_sensor) {
    BodyInterface& bi = ctx->physics_system.GetBodyInterface();
    BoxShapeSettings shape_settings(Vec3(hw, hh, hd));
    ShapeRefC shape = shape_settings.Create().Get();

    BodyCreationSettings settings(shape, RVec3(px, py, pz), Quat::sIdentity(),
        is_static ? EMotionType::Static : EMotionType::Dynamic, ObjectLayer(layer));
    settings.mIsSensor = is_sensor;
    if (!is_static && mass > 0.0f) {
        settings.mOverrideMassProperties = EOverrideMassProperties::CalculateInertia;
        settings.mMassPropertiesOverride.mMass = mass;
    }

    BodyID id = bi.CreateAndAddBody(settings, is_static ? EActivation::DontActivate : EActivation::Activate);
    if (is_sensor) {
        std::lock_guard<std::mutex> lock(ctx->trigger_listener.mutex);
        ctx->trigger_listener.sensor_bodies.insert(id.GetIndexAndSequenceNumber());
    }
    return id.GetIndexAndSequenceNumber();
}

void jolt_remove_body(JoltCtx* ctx, uint32_t body_id) {
    BodyID id(body_id);
    BodyInterface& bi = ctx->physics_system.GetBodyInterface();
    bi.RemoveBody(id);
    bi.DestroyBody(id);
    std::lock_guard<std::mutex> lock(ctx->trigger_listener.mutex);
    ctx->trigger_listener.sensor_bodies.erase(body_id);
}

void jolt_get_position(JoltCtx* ctx, uint32_t body_id, float* out_xyz) {
    RVec3 p = ctx->physics_system.GetBodyInterface().GetPosition(BodyID(body_id));
    out_xyz[0] = float(p.GetX());
    out_xyz[1] = float(p.GetY());
    out_xyz[2] = float(p.GetZ());
}

void jolt_get_rotation(JoltCtx* ctx, uint32_t body_id, float* out_xyzw) {
    Quat q = ctx->physics_system.GetBodyInterface().GetRotation(BodyID(body_id));
    out_xyzw[0] = q.GetX();
    out_xyzw[1] = q.GetY();
    out_xyzw[2] = q.GetZ();
    out_xyzw[3] = q.GetW();
}

void jolt_set_position(JoltCtx* ctx, uint32_t body_id, float px, float py, float pz) {
    ctx->physics_system.GetBodyInterface().SetPosition(BodyID(body_id), RVec3(px, py, pz), EActivation::Activate);
}

void jolt_set_linear_velocity(JoltCtx* ctx, uint32_t body_id, float vx, float vy, float vz) {
    ctx->physics_system.GetBodyInterface().SetLinearVelocity(BodyID(body_id), Vec3(vx, vy, vz));
}

void jolt_get_linear_velocity(JoltCtx* ctx, uint32_t body_id, float* out_xyz) {
    Vec3 v = ctx->physics_system.GetBodyInterface().GetLinearVelocity(BodyID(body_id));
    out_xyz[0] = v.GetX();
    out_xyz[1] = v.GetY();
    out_xyz[2] = v.GetZ();
}

bool jolt_is_active(JoltCtx* ctx, uint32_t body_id) {
    return ctx->physics_system.GetBodyInterface().IsActive(BodyID(body_id));
}

bool jolt_raycast(JoltCtx* ctx, float ox, float oy, float oz, float dx, float dy, float dz,
                   float max_dist, JoltRayHit* out_hit) {
    RRayCast ray(RVec3(ox, oy, oz), Vec3(dx, dy, dz) * max_dist);
    RayCastResult result;
    bool hit = ctx->physics_system.GetNarrowPhaseQuery().CastRay(ray, result);
    if (!hit) return false;

    out_hit->body_id = result.mBodyID.GetIndexAndSequenceNumber();
    out_hit->fraction = result.mFraction;
    RVec3 point = ray.GetPointOnRay(result.mFraction);
    out_hit->point[0] = float(point.GetX());
    out_hit->point[1] = float(point.GetY());
    out_hit->point[2] = float(point.GetZ());

    BodyLockRead lock(ctx->physics_system.GetBodyLockInterface(), result.mBodyID);
    if (lock.Succeeded()) {
        Vec3 n = lock.GetBody().GetWorldSpaceSurfaceNormal(result.mSubShapeID2, point);
        out_hit->normal[0] = n.GetX();
        out_hit->normal[1] = n.GetY();
        out_hit->normal[2] = n.GetZ();
    } else {
        out_hit->normal[0] = out_hit->normal[1] = out_hit->normal[2] = 0.0f;
    }
    return true;
}

int jolt_raycast_all(JoltCtx* ctx, float ox, float oy, float oz, float dx, float dy, float dz,
                      float max_dist, JoltRayHit* out_hits, int max_hits) {
    RRayCast ray(RVec3(ox, oy, oz), Vec3(dx, dy, dz) * max_dist);
    RayCastSettings settings;
    AllHitCollisionCollector<CastRayCollector> collector;
    ctx->physics_system.GetNarrowPhaseQuery().CastRay(ray, settings, collector);
    collector.Sort();

    int n = 0;
    for (const RayCastResult& result : collector.mHits) {
        if (n >= max_hits) break;
        JoltRayHit& out_hit = out_hits[n];
        out_hit.body_id = result.mBodyID.GetIndexAndSequenceNumber();
        out_hit.fraction = result.mFraction;
        RVec3 point = ray.GetPointOnRay(result.mFraction);
        out_hit.point[0] = float(point.GetX());
        out_hit.point[1] = float(point.GetY());
        out_hit.point[2] = float(point.GetZ());

        BodyLockRead lock(ctx->physics_system.GetBodyLockInterface(), result.mBodyID);
        if (lock.Succeeded()) {
            Vec3 norm = lock.GetBody().GetWorldSpaceSurfaceNormal(result.mSubShapeID2, point);
            out_hit.normal[0] = norm.GetX();
            out_hit.normal[1] = norm.GetY();
            out_hit.normal[2] = norm.GetZ();
        } else {
            out_hit.normal[0] = out_hit.normal[1] = out_hit.normal[2] = 0.0f;
        }
        ++n;
    }
    return n;
}

JoltCharacter* jolt_character_create(JoltCtx* ctx, float radius, float height,
                                      float px, float py, float pz) {
    Ref<Shape> shape = RotatedTranslatedShapeSettings(
        Vec3(0, 0.5f * height, 0), Quat::sIdentity(),
        new CapsuleShape(0.5f * height, radius)).Create().Get();

    CharacterVirtualSettings settings;
    settings.mShape = shape;
    settings.mMaxSlopeAngle = DegreesToRadians(45.0f);
    settings.mUp = Vec3::sAxisY();

    auto* ch = new JoltCharacter();
    ch->character = new CharacterVirtual(&settings, RVec3(px, py, pz), Quat::sIdentity(), &ctx->physics_system);
    return ch;
}

void jolt_character_destroy(JoltCtx*, JoltCharacter* ch) {
    delete ch;
}

void jolt_character_set_velocity(JoltCharacter* ch, float vx, float vy, float vz) {
    ch->character->SetLinearVelocity(Vec3(vx, vy, vz));
}

void jolt_character_get_velocity(JoltCharacter* ch, float* out_xyz) {
    Vec3 v = ch->character->GetLinearVelocity();
    out_xyz[0] = v.GetX();
    out_xyz[1] = v.GetY();
    out_xyz[2] = v.GetZ();
}

void jolt_character_update(JoltCtx* ctx, JoltCharacter* ch, float dt, float gravity_y) {
    ch->character->Update(dt, Vec3(0, gravity_y, 0),
        ctx->physics_system.GetDefaultBroadPhaseLayerFilter(ObjectLayer(JOLT_LAYER_PLAYER)),
        ctx->physics_system.GetDefaultLayerFilter(ObjectLayer(JOLT_LAYER_PLAYER)),
        {}, {}, ctx->temp_allocator);
}

void jolt_character_get_position(JoltCharacter* ch, float* out_xyz) {
    RVec3 p = ch->character->GetPosition();
    out_xyz[0] = float(p.GetX());
    out_xyz[1] = float(p.GetY());
    out_xyz[2] = float(p.GetZ());
}

bool jolt_character_is_grounded(JoltCharacter* ch) {
    return ch->character->IsSupported();
}

int jolt_overlap_sphere(JoltCtx* ctx, float cx, float cy, float cz, float radius,
                         uint32_t* out_body_ids, int max_hits) {
    SphereShape sphere_shape(radius);
    RMat44 com_transform = RMat44::sTranslation(RVec3(cx, cy, cz));

    CollideShapeSettings settings;
    AllHitCollisionCollector<CollideShapeCollector> collector;
    ctx->physics_system.GetNarrowPhaseQuery().CollideShape(
        &sphere_shape, Vec3::sReplicate(1.0f), com_transform, settings, RVec3(cx, cy, cz), collector);

    int n = 0;
    for (const CollideShapeResult& result : collector.mHits) {
        if (n >= max_hits) break;
        out_body_ids[n++] = result.mBodyID2.GetIndexAndSequenceNumber();
    }
    return n;
}

void jolt_apply_impulse(JoltCtx* ctx, uint32_t body_id, float ix, float iy, float iz) {
    ctx->physics_system.GetBodyInterface().AddImpulse(BodyID(body_id), Vec3(ix, iy, iz));
}

bool jolt_poll_trigger_event(JoltCtx* ctx, JoltTriggerEvent* out_event) {
    std::lock_guard<std::mutex> lock(ctx->trigger_listener.mutex);
    if (ctx->trigger_listener.queue.empty()) return false;
    *out_event = ctx->trigger_listener.queue.back();
    ctx->trigger_listener.queue.pop_back();
    return true;
}

} // extern "C"
