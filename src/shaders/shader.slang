

struct VSInput {
    float3 Pos: POSITION;
    float3 Normal: NORMAL;
    float2 UV : TEXCOORD0;
};

struct FrameUBO {
    float4x4 projection;
    float4x4 view;
};
struct PushConstants {
    float4x4 model;
    uint textureIndex;
};
struct VSOutput {
    float4 Pos: SV_Position;
    float3 Normal;
    float2 UV;
};
[[vk::binding(0,0)]]
ConstantBuffer<FrameUBO> ubo;
[[vk::binding(0, 1)]]
Sampler2D textures[];

[[vk::push_constant]]
ConstantBuffer<PushConstants> pc;

[shader("vertex")]
VSOutput vertMain(VSInput input) {
    VSOutput output;
    output.Pos = mul(ubo.projection, mul(ubo.view, mul(pc.model, float4(input.Pos, 1.0))));
    output.Normal = input.Normal;
    output.UV = input.UV;
    return output;
}

[shader("fragment")]
float4 fragMain(VSOutput input) : SV_Target {
    return textures[NonUniformResourceIndex(pc.textureIndex)].Sample(input.UV);
}