struct VSInput {
    float3 Pos: POSITION;
    float3 Color: COLOR0;
};

// Mirrors zVulkanContext.FrameUBO layout — same descriptor set as the main
// pass (set 0), so debug draw only needs projection/view out of it.
struct FrameUBO {
    float4x4 projection;
    float4x4 view;
    float4x4 lightViewProj;
    float4 lightDir;
    float4 lightColor;
    float4 cameraPos;
};

struct VSOutput {
    float4 Pos: SV_Position;
    float3 Color;
};

[[vk::binding(0,0)]]
ConstantBuffer<FrameUBO> ubo;

[shader("vertex")]
VSOutput vertMain(VSInput input) {
    VSOutput output;
    output.Pos = mul(ubo.projection, mul(ubo.view, float4(input.Pos, 1.0)));
    output.Color = input.Color;
    return output;
}

[shader("fragment")]
float4 fragMain(VSOutput input) : SV_Target {
    return float4(input.Color, 1.0);
}
