

struct VSInput {
    float3 Pos: POSITION;
    float3 Normal: NORMAL;
    float2 UV : TEXCOORD0;
    uint4 Joints : TEXCOORD1;
    float4 Weights : TEXCOORD2;
};

struct FrameUBO {
    float4x4 projection;
    float4x4 view;
    float4x4 lightViewProj;
    float4 lightDir;   // xyz = direction the light travels, w unused
    float4 lightColor; // xyz = color, w = ambient
    float4 cameraPos;  // xyz = world-space camera position, for specular
};
struct PushConstants {
    float4x4 model;
    uint materialIndex;
    // Absolute index into `skinMatrices` for joint 0 of this draw; unskinned
    // vertices have Weights = (1,0,0,0) so only skinMatrices[skinOffset] is
    // ever sampled, and that slot is always identity (see
    // zVulkanContext.SKIN_IDENTITY_SLOT) — same shader path either way.
    uint skinOffset;
};
struct MaterialData {
    float metallic;
    float roughness;
    uint albedoTextureIndex;
    uint _pad;
};
struct VSOutput {
    float4 Pos: SV_Position;
    float3 Normal;
    float2 UV;
    float4 LightSpacePos;
    float3 WorldPos;
};
[[vk::binding(0,0)]]
ConstantBuffer<FrameUBO> ubo;
[[vk::binding(1,0)]]
Sampler2D shadowMap;
[[vk::binding(0, 1)]]
Sampler2D textures[];
[[vk::binding(1, 1)]]
StructuredBuffer<MaterialData> materials;
[[vk::binding(2, 1)]]
StructuredBuffer<float4x4> skinMatrices;

[[vk::push_constant]]
ConstantBuffer<PushConstants> pc;

static const float SHADOW_MAP_TEXEL = 1.0 / 2048.0;
static const float SHADOW_BIAS = 0.005;

[shader("vertex")]
VSOutput vertMain(VSInput input) {
    VSOutput output;

    float4x4 skin =
        skinMatrices[pc.skinOffset + input.Joints.x] * input.Weights.x +
        skinMatrices[pc.skinOffset + input.Joints.y] * input.Weights.y +
        skinMatrices[pc.skinOffset + input.Joints.z] * input.Weights.z +
        skinMatrices[pc.skinOffset + input.Joints.w] * input.Weights.w;
    float4x4 modelSkin = mul(pc.model, skin);

    float4 worldPos = mul(modelSkin, float4(input.Pos, 1.0));
    output.Pos = mul(ubo.projection, mul(ubo.view, worldPos));
    output.Normal = mul((float3x3)modelSkin, input.Normal);
    output.UV = input.UV;
    output.LightSpacePos = mul(ubo.lightViewProj, worldPos);
    output.WorldPos = worldPos.xyz;
    return output;
}

float sampleShadow(float2 uv, float currentDepth) {
    float occluderDepth = shadowMap.Sample(uv).r;
    return (currentDepth - SHADOW_BIAS > occluderDepth) ? 0.0 : 1.0;
}

float pcfShadow(float3 lightSpacePos) {
    float2 uv = lightSpacePos.xy * 0.5 + 0.5;
    float currentDepth = lightSpacePos.z;

    float shadow = 0.0;
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            shadow += sampleShadow(uv + float2(x, y) * SHADOW_MAP_TEXEL, currentDepth);
        }
    }
    return shadow / 9.0;
}

[shader("fragment")]
float4 fragMain(VSOutput input) : SV_Target {
    MaterialData mat = materials[NonUniformResourceIndex(pc.materialIndex)];
    float4 albedo = textures[NonUniformResourceIndex(mat.albedoTextureIndex)].Sample(input.UV);

    float3 normal = normalize(input.Normal);
    float3 toLight = normalize(-ubo.lightDir.xyz);
    float ndotl = max(dot(normal, toLight), 0.0);

    float3 lightSpacePos = input.LightSpacePos.xyz / input.LightSpacePos.w;
    float shadow = pcfShadow(lightSpacePos);

    // Blinn-Phong specular, modulated by metallic/roughness: rougher surfaces
    // get a wider/dimmer highlight, metals tint the highlight with albedo
    // instead of staying white and lose their diffuse term.
    float3 viewDir = normalize(ubo.cameraPos.xyz - input.WorldPos);
    float3 halfVec = normalize(toLight + viewDir);
    float shininess = lerp(4.0, 256.0, 1.0 - mat.roughness);
    float specPower = pow(max(dot(normal, halfVec), 0.0), shininess);
    float3 specularTint = lerp(float3(1.0, 1.0, 1.0), albedo.rgb, mat.metallic);
    float3 specular = specularTint * specPower * shadow;

    float3 diffuse = albedo.rgb * (1.0 - mat.metallic) * shadow * ndotl;
    float3 ambient = albedo.rgb * ubo.lightColor.w;
    float3 lighting = ubo.lightColor.xyz * (ambient + diffuse + specular);
    return float4(lighting, albedo.a);
}
