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
    static const int4 coeffs[COEFFS_LENGTH] = {
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
    // Swap width/height/x/y if scaling vertically
    bool vertical = target_width == source_width;
    int width = vertical ? source_height : source_width;
    int height = vertical ? target_width : source_height;
    float x = vertical ? pixel.uv.y : pixel.uv.x;
    float y = vertical ? pixel.uv.x : pixel.uv.y;

    // The output UV position mapped onto the original source image
    float mapped_x = x * width;
    int mapped_y = y * height;

    // Get scaling coefficients for this pixel
    int4 coeffs = get_coeffs(mapped_x);

    // 2 taps per phase, 64 phases
    int taps[2] = {
        mapped_x - 0.5,
        mapped_x + 0.5
    };

    // Clamp the tap values to be within the source dimensions
    if (taps[0] < 0) taps[0] = 0;
    if (taps[1] >= width) taps[1] = width - 1;

    // Grab the pixel for each tap from the source image
    float4 pixels[2] = {
        image.Load(vertical ? int3(mapped_y, taps[0], 0) : int3(taps[0], mapped_y, 0)),
        image.Load(vertical ? int3(mapped_y, taps[1], 0) : int3(taps[1], mapped_y, 0))
    };

    // Weigh the colours from each source pixel based on the coefficients for this phase to generate the result colour for this rendered pixel
    float r = (pixels[0].r * coeffs.y + pixels[1].r * coeffs.z) / 128;
    float g = (pixels[0].g * coeffs.y + pixels[1].g * coeffs.z) / 128;
    float b = (pixels[0].b * coeffs.y + pixels[1].b * coeffs.z) / 128;

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
