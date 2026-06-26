struct VSInput {
    float3 Pos: POSITION;
};

struct PushConstants {
    float4x4 mvp;
};

[[vk::push_constant]]
ConstantBuffer<PushConstants> pc;

[shader("vertex")]
float4 vertMain(VSInput input) : SV_Position {
    return mul(pc.mvp, float4(input.Pos, 1.0));
}
