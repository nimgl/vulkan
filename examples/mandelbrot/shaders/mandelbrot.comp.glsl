#version 450
#extension GL_EXT_debug_printf : require

// We set local workgroup size via Specialization Constants.
layout (local_size_x_id = 0, local_size_y_id = 1) in;

// Otherwise, we have to hard code the workgroup size in compute shader like
// below:
// layout (local_size_x = 32, local_size_y = 32) in;

// We access image data via storage buffer.
layout (std140, binding = 0) buffer buf {
  vec4 image[];
};

// The size of image is accessed via uniform buffer.
layout (binding = 1) uniform UBO {
  int width;
  int height;
} ubo;

vec3 palette(float t) {
  vec3 d = vec3(0.3f, 0.3f, 0.5f);
  vec3 e = vec3(-0.2f, -0.3f, -0.5f);
  vec3 f = vec3(2.1f, 2.0f, 3.0f);
  vec3 g = vec3(0.0f, 0.1f, 0.0f);

  return d + e * cos(6.28318f * (f * t + g));
}

void main() {
  // In order to fit the work into workgroups, some unnecessary invocations are
  // launched. We terminate those invocations here.
  if (gl_GlobalInvocationID.x >= ubo.width ||
      gl_GlobalInvocationID.y >= ubo.height) { return; }

  float x = float(gl_GlobalInvocationID.x) / float(ubo.width);
  float y = float(gl_GlobalInvocationID.y) / float(ubo.height);

  // Code for computing mandelbrot set.
  const vec2 uv = vec2(x, y - 0.5f) *
    vec2(1.0f, float(ubo.height) / float(ubo.width));
  const vec2 c = uv * 3.0f + vec2(-2.1f, 0.0f);
  vec2 z = vec2(0.0f);
  const int m = 128;
  int n = 0;
  for (int i = 0; i < m; ++i) {
    z = vec2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
    if (dot(z, z) > 4) { break; }
    ++n;
  }

  // We use a cosine palette to determine the color of pixels.
  vec4 color = vec4(palette(float(n) / float(m)), 1.0f);

  // Debug printf output
  if (gl_GlobalInvocationID == uvec3(0)) {
    debugPrintfEXT("Invocation ID: %u", 0);
  }
  // Store the color data into the storage buffer.
  image[ubo.width * gl_GlobalInvocationID.y + gl_GlobalInvocationID.x] = color;
}
