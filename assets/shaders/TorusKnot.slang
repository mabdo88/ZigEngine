struct VSInput {
    float3 Pos: POSITION;
    float3 Color: COLOR;
};

// Only what you actually use
struct ShaderData {
    float time;  // Just 4 bytes
};

struct VSOutput {
    float4 Pos: SV_Position;
    float3 Color;
};

[[vk::push_constant]]
ConstantBuffer<ShaderData> shaderData;

[shader("vertex")]
VSOutput vertMain(uint vertexID: SV_VertexID) {
    VSOutput output;

    float2 positions[3] = {
        float2(0.0, -0.5 + sin(shaderData.time) * 0.2),
        float2(0.5 + cos(shaderData.time) * 0.1, 0.5),
        float2(-0.5 + sin(shaderData.time * 1.5) * 0.1, 0.5),
    };
    float3 colors[3] = {
        float3(1.0, 0.0, 0.0),
        float3(0.0, 1.0, 0.0),
        float3(0.0, 0.0, 1.0),
    };

    output.Pos = float4(positions[vertexID], 0.0, 1.0);
    output.Color = colors[vertexID];
    return output;
}

[shader("fragment")]
float4 fragMain(VSOutput input) : SV_Target {
    float pulse = sin(shaderData.time * 2.0) * 0.3 + 0.7;
    return float4(input.Color * pulse, 1.0);
}