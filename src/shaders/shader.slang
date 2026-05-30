

struct VSInput {
    float3 Pos: POSITION;
    float3 Color: COLOR;
};

struct ShaderData {
    float4x4 projection;
    float4x4 view;
    float4x4 model;
};

struct VSOutput {
    float4 Pos: SV_Position;
    float3 Color;
};

[[vk::push_constant]]
ConstantBuffer<ShaderData> shaderData;

[shader("vertex")]
VSOutput vertMain(VSInput input) {
    VSOutput output;
    output.Pos = mul(shaderData.projection, mul(shaderData.view, mul(shaderData.model, float4(input.Pos, 1.0))));
    output.Color = input.Color;
    return output;
}

[shader("fragment")]
float4 fragMain(VSOutput input) : SV_Target {
    return float4(input.Color, 1.0);
}