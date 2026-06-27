struct VSInput {
    float2 Pos: POSITION;
    float2 UV: TEXCOORD0;
    float4 Color: COLOR0;
};

struct UIProjUBO {
    float4x4 projection;
};

struct PushConstants {
    uint textureIndex;
};

struct VSOutput {
    float4 Pos: SV_Position;
    float2 UV;
    float4 Color;
};

[[vk::binding(0, 0)]]
ConstantBuffer<UIProjUBO> proj;
// Same bindless texture array binding (set 1, binding 0) the main pass
// declares in shader.slang — this pipeline only ever reads from it, never
// rebinds it, so reusing the layout needs no extra descriptor writes.
[[vk::binding(0, 1)]]
Sampler2D textures[];

[[vk::push_constant]]
ConstantBuffer<PushConstants> pc;

[shader("vertex")]
VSOutput vertMain(VSInput input) {
    VSOutput output;
    output.Pos = mul(proj.projection, float4(input.Pos, 0.0, 1.0));
    output.UV = input.UV;
    output.Color = input.Color;
    return output;
}

[shader("fragment")]
float4 fragMain(VSOutput input) : SV_Target {
    float4 texel = textures[NonUniformResourceIndex(pc.textureIndex)].Sample(input.UV);
    return texel * input.Color;
}
