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
    static const int COEFFS_LENGTH = 64;
    // Scaling coefficients from 'Interpolation (Sharp).txt' in https://github.com/MiSTer-devel/Filters_MiSTer
    static int4 coeffs[COEFFS_LENGTH] = {
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
    // Hacky way to determine which dimension we're scaling in, make this nicer later
    // Scale horizontally first, then vertically
    bool scale_vertical = target_width == source_width;

    // The output UV position mapped onto the original source image, pixel.uv.x and pixel.uv.y are [0,1]
    float mapped_x = pixel.uv.x * source_width;
    float mapped_y = pixel.uv.y * source_height;

    // Get the mapped pixel to interpolate
    float to_scale = mapped_x;
    if (scale_vertical) {
        to_scale = mapped_y;
    }

    // Get scaling coefficients for this pixel
    int4 coeffs = get_coeffs(to_scale);

    // 4 taps per phase, 64 phases
    int taps[4] = {
        to_scale - 1.5,
        to_scale - 0.5,
        to_scale + 0.5,
        to_scale + 1.5
    };

    // Determine which dimension to clamp with based on scaling direction
    int source_dimension = source_width;
    if (scale_vertical) {
        source_dimension = source_height;
    }

    // Clamp the tap values to be within the source dimensions
    if (taps[0] < 0) taps[0] = 0;
    if (taps[1] < 0) taps[1] = 0;
    if (taps[2] >= source_dimension) taps[2] = source_dimension - 1;
    if (taps[3] >= source_dimension) taps[3] = source_dimension - 1;

    // Grab the pixel for each tap from the source image
    float4 pixels[4] = {
        image.Load(int3(taps[0], mapped_y, 0)),
        image.Load(int3(taps[1], mapped_y, 0)),
        image.Load(int3(taps[2], mapped_y, 0)),
        image.Load(int3(taps[3], mapped_y, 0))
    };
    if (scale_vertical) {
        pixels[0] = image.Load(int3(mapped_x, taps[0], 0));
        pixels[1] = image.Load(int3(mapped_x, taps[1], 0));
        pixels[2] = image.Load(int3(mapped_x, taps[2], 0));
        pixels[3] = image.Load(int3(mapped_x, taps[3], 0));
    }

    // Weigh the colours from each source pixel based on the coefficients for this phase to generate the result colour for this rendered pixel
    float r = pixels[0].r * coeffs.x / 128 + pixels[1].r * coeffs.y / 128 + pixels[2].r * coeffs.z / 128 + pixels[3].r * coeffs.w / 128;
    float g = pixels[0].g * coeffs.x / 128 + pixels[1].g * coeffs.y / 128 + pixels[2].g * coeffs.z / 128 + pixels[3].g * coeffs.w / 128;
    float b = pixels[0].b * coeffs.x / 128 + pixels[1].b * coeffs.y / 128 + pixels[2].b * coeffs.z / 128 + pixels[3].b * coeffs.w / 128;

    // Clamp colours, maybe not required
    if (r < 0) r = 0;
    if (g < 0) g = 0;
    if (b < 0) b = 0;
    if (r > 1) r = 1;
    if (g > 1) g = 1;
    if (b > 1) b = 1;

    // Return result colour for this pixel
    return float4(r, g, b, 1);
}

technique Draw
{
    pass
    {
        vertex_shader = vertex_shader_240p_resize(vertex);
        pixel_shader = pixel_shader_240p_resize(pixel);
    }
}
