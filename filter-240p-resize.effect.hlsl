// Size of the source picture
uniform int source_width;
uniform int source_height;
uniform int target_width;
uniform int target_height;

// OBS-specific syntax adaptation to HLSL standard to avoid errors reported by the code editor
#define SamplerState sampler_state
#define Texture2D texture2d

// Uniform variables set by OBS (required)
uniform float4x4 ViewProj; // View-projection matrix used in the vertex shader
uniform Texture2D image;   // Texture containing the source picture

// Interpolation method and wrap mode for sampling a texture
SamplerState point_clamp
{
    Filter    = Point;      // Anisotropy / Point / Linear
    AddressU  = Clamp;      // Wrap / Clamp / Mirror / Border / MirrorOnce
    AddressV  = Clamp;      // Wrap / Clamp / Mirror / Border / MirrorOnce
    BorderColor = 00000000; // Used only with Border edges (optional)
};

// Data type of the input of the vertex shader
struct vertex_data
{
    float4 pos : POSITION;  // Homogeneous space coordinates XYZW
    float2 uv  : TEXCOORD0; // UV coordinates in the source picture
};

// Data type of the output returned by the vertex shader, and used as input 
// for the pixel shader after interpolation for each pixel
struct pixel_data
{
    float4 pos : POSITION;  // Homogeneous screen coordinates XYZW
    float2 uv  : TEXCOORD0; // UV coordinates in the source picture
};

// Vertex shader used to compute position of rendered pixels and pass UV
pixel_data vertex_shader_240p_resize(vertex_data vertex)
{
    pixel_data pixel;
    pixel.pos = mul(float4(vertex.pos.xyz, 1.0), ViewProj);
    pixel.uv  = vertex.uv;
    return pixel;
}

// Get the coefficients for this mapped X or Y value
int4 get_coeffs(float mapped)
{
    const int COEFFS_LENGTH = 64;
    // Scaling coefficients from 'Interpolation (Sharp).txt' in https://github.com/MiSTer-devel/Filters_MiSTer
    int4 coeffs[COEFFS_LENGTH] = {
        int4(0, 128,   0,   0),
        int4(0, 128,   0,   0),
        int4(0, 128,   0,   0),
        int4(0, 128,   0,   0),
        int4(0, 128,   0,   0),
        int4(0, 128,   0,   0),
        int4(0, 128,   0,   0),
        int4(0, 128,   0,   0),
        int4(0, 128,   0,   0),
        int4(0, 128,   0,   0),
        int4(0, 128,   0,   0),
        int4(0, 128,   0,   0),
        int4(0, 128,   0,   0),
        int4(0, 128,   0,   0),
        int4(0, 128,   0,   0),
        int4(0, 127,   1,   0),
        int4(0, 127,   1,   0),
        int4(0, 127,   1,   0),
        int4(0, 127,   1,   0),
        int4(0, 126,   2,   0),
        int4(0, 125,   3,   0),
        int4(0, 124,   4,   0),
        int4(0, 123,   5,   0),
        int4(0, 121,   7,   0),
        int4(0, 119,   9,   0),
        int4(0, 116,  12,   0),
        int4(0, 112,  16,   0),
        int4(0, 107,  21,   0),
        int4(0, 100,  28,   0),
        int4(0,  93,  35,   0),
        int4(0,  84,  44,   0),
        int4(0,  74,  54,   0),
        int4(0,  64,  64,   0),
        int4(0,  54,  74,   0),
        int4(0,  44,  84,   0),
        int4(0,  35,  93,   0),
        int4(0,  28, 100,   0),
        int4(0,  21, 107,   0),
        int4(0,  16, 112,   0),
        int4(0,  12, 116,   0),
        int4(0,   9, 119,   0),
        int4(0,   7, 121,   0),
        int4(0,   5, 123,   0),
        int4(0,   4, 124,   0),
        int4(0,   3, 125,   0),
        int4(0,   2, 126,   0),
        int4(0,   1, 127,   0),
        int4(0,   1, 127,   0),
        int4(0,   1, 127,   0),
        int4(0,   1, 127,   0),
        int4(0,   0, 128,   0),
        int4(0,   0, 128,   0),
        int4(0,   0, 128,   0),
        int4(0,   0, 128,   0),
        int4(0,   0, 128,   0),
        int4(0,   0, 128,   0),
        int4(0,   0, 128,   0),
        int4(0,   0, 128,   0),
        int4(0,   0, 128,   0),
        int4(0,   0, 128,   0),
        int4(0,   0, 128,   0),
        int4(0,   0, 128,   0),
        int4(0,   0, 128,   0),
        int4(0,   0, 128,   0)
    };
    float phase = COEFFS_LENGTH * ((mapped + 0.5) % 1);
    int4 coeff = coeffs[int(phase)];
    return coeff;
}

// Pixel shader used to compute an RGBA color at a given pixel position
float4 pixel_shader_240p_resize(pixel_data pixel) : TARGET
{
    // Scale of the output resolution relative to the input resolution
    float scale_x = target_width / source_width;
    float scale_y = target_height / source_height;

    // The output pixel position mapped onto the original source image based on the scale
    float mapped_x = pixel.uv.x / scale_x;
    float mapped_y = pixel.uv.y / scale_y;

    int4 coeffs_x = get_coeffs(mapped_x);
    int4 coeffs_y = get_coeffs(mapped_y);

    int taps_x[4] = {
        int(mapped_x - 1.5),
        int(mapped_x - 0.5),
        int(mapped_x + 0.5),
        int(mapped_x + 1.5)
    };

    int taps_y[4] = {
        int(mapped_y - 1.5),
        int(mapped_y - 0.5),
        int(mapped_y + 0.5),
        int(mapped_y + 1.5)
    };

    if (taps_x[0] < 0) taps_x[0] = 0;
    if (taps_x[1] < 0) taps_x[1] = 0;
    if (taps_x[2] >= source_width) taps_x[2] = source_width - 1;
    if (taps_x[3] >= source_width) taps_x[3] = source_width - 1;

    if (taps_y[0] < 0) taps_y[0] = 0;
    if (taps_y[1] < 0) taps_y[1] = 0;
    if (taps_y[2] >= source_height) taps_y[2] = source_height - 1;
    if (taps_y[3] >= source_height) taps_y[3] = source_height - 1;

    float4 pixels[4] = {
        image.Sample(point_clamp, float2(taps_x[0], taps_y[0])),
        image.Sample(point_clamp, float2(taps_x[1], taps_y[1])),
        image.Sample(point_clamp, float2(taps_x[2], taps_y[2])),
        image.Sample(point_clamp, float2(taps_x[3], taps_y[3]))
    };

    float4 source_sample = image.Sample(point_clamp, pixel.uv);
    float luminance = dot(source_sample.rgb, float3(0.299, 0.587, 0.114));
    return float4(luminance.xxx, source_sample.a);
}

technique Draw
{
    pass
    {
        vertex_shader = vertex_shader_240p_resize(vertex);
        pixel_shader = pixel_shader_240p_resize(pixel);
    }
}
