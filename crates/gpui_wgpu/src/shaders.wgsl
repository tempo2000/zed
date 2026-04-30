/* Functions useful for debugging:

// A heat map color for debugging (blue -> cyan -> green -> yellow -> red).
fn heat_map_color(value: f32, minValue: f32, maxValue: f32, position: vec2<f32>) -> vec4<f32> {
    // Normalize value to 0-1 range
    let t = clamp((value - minValue) / (maxValue - minValue), 0.0, 1.0);

    // Heat map color calculation
    let r = t * t;
    let g = 4.0 * t * (1.0 - t);
    let b = (1.0 - t) * (1.0 - t);
    let heat_color = vec3<f32>(r, g, b);

    // Create a checkerboard pattern (black and white)
    let sum = floor(position.x / 3) + floor(position.y / 3);
    let is_odd = fract(sum * 0.5); // 0.0 for even, 0.5 for odd
    let checker_value = is_odd * 2.0; // 0.0 for even, 1.0 for odd
    let checker_color = vec3<f32>(checker_value);

    // Determine if value is in range (1.0 if in range, 0.0 if out of range)
    let in_range = step(minValue, value) * step(value, maxValue);

    // Mix checkerboard and heat map based on whether value is in range
    let final_color = mix(checker_color, heat_color, in_range);

    return vec4<f32>(final_color, 1.0);
}

*/

// Contrast and gamma correction adapted from https://github.com/microsoft/terminal/blob/1283c0f5b99a2961673249fa77c6b986efb5086c/src/renderer/atlas/dwrite.hlsl
// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.
fn color_brightness(color: vec3<f32>) -> f32 {
    // REC. 601 luminance coefficients for perceived brightness
    return dot(color, vec3<f32>(0.30, 0.59, 0.11));
}

fn light_on_dark_contrast(enhancedContrast: f32, color: vec3<f32>) -> f32 {
    let brightness = color_brightness(color);
    let multiplier = saturate(4.0 * (0.75 - brightness));
    return enhancedContrast * multiplier;
}

fn enhance_contrast(alpha: f32, k: f32) -> f32 {
    return alpha * (k + 1.0) / (alpha * k + 1.0);
}

fn enhance_contrast3(alpha: vec3<f32>, k: f32) -> vec3<f32> {
    return alpha * (k + 1.0) / (alpha * k + 1.0);
}

fn apply_alpha_correction(a: f32, b: f32, g: vec4<f32>) -> f32 {
    let brightness_adjustment = g.x * b + g.y;
    let correction = brightness_adjustment * a + (g.z * b + g.w);
    return a + a * (1.0 - a) * correction;
}

fn apply_alpha_correction3(a: vec3<f32>, b: vec3<f32>, g: vec4<f32>) -> vec3<f32> {
    let brightness_adjustment = g.x * b + g.y;
    let correction = brightness_adjustment * a + (g.z * b + g.w);
    return a + a * (1.0 - a) * correction;
}

fn apply_contrast_and_gamma_correction(sample: f32, color: vec3<f32>, enhanced_contrast_factor: f32, gamma_ratios: vec4<f32>) -> f32 {
    let enhanced_contrast = light_on_dark_contrast(enhanced_contrast_factor, color);
    let brightness = color_brightness(color);

    let contrasted = enhance_contrast(sample, enhanced_contrast);
    return apply_alpha_correction(contrasted, brightness, gamma_ratios);
}

fn apply_contrast_and_gamma_correction3(sample: vec3<f32>, color: vec3<f32>, enhanced_contrast_factor: f32, gamma_ratios: vec4<f32>) -> vec3<f32> {
    let enhanced_contrast = light_on_dark_contrast(enhanced_contrast_factor, color);

    let contrasted = enhance_contrast3(sample, enhanced_contrast);
    return apply_alpha_correction3(contrasted, color, gamma_ratios);
}

struct GlobalParams {
    viewport_size: vec2<f32>,
    premultiplied_alpha: u32,
    pad: u32,
}

struct GammaParams {
    gamma_ratios: vec4<f32>,
    grayscale_enhanced_contrast: f32,
    subpixel_enhanced_contrast: f32,
    is_bgr: u32,
    pad: u32,
}

@group(0) @binding(0) var<uniform> globals: GlobalParams;
@group(0) @binding(1) var<uniform> gamma_params: GammaParams;
@group(1) @binding(1) var t_sprite: texture_2d<f32>;
@group(1) @binding(2) var s_sprite: sampler;

const M_PI_F: f32 = 3.1415926;
const GRAYSCALE_FACTORS: vec3<f32> = vec3<f32>(0.2126, 0.7152, 0.0722);

struct Bounds {
    origin: vec2<f32>,
    size: vec2<f32>,
}

struct Corners {
    top_left: f32,
    top_right: f32,
    bottom_right: f32,
    bottom_left: f32,
}

struct Edges {
    top: f32,
    right: f32,
    bottom: f32,
    left: f32,
}

struct Hsla {
    h: f32,
    s: f32,
    l: f32,
    a: f32,
}

struct LinearColorStop {
    color: Hsla,
    percentage: f32,
}

struct Background {
    // 0u is Solid
    // 1u is LinearGradient
    // 2u is PatternSlash
    // 3u is Checkerboard
    tag: u32,
    // 0u is sRGB linear color
    // 1u is Oklab color
    color_space: u32,
    solid: Hsla,
    gradient_angle_or_pattern_height: f32,
    colors: array<LinearColorStop, 2>,
    pad: u32,
}

struct AtlasTextureId {
    index: u32,
    kind: u32,
}

struct AtlasBounds {
    origin: vec2<i32>,
    size: vec2<i32>,
}

struct AtlasTile {
    texture_id: AtlasTextureId,
    tile_id: u32,
    padding: u32,
    bounds: AtlasBounds,
}

struct TransformationMatrix {
    rotation_scale: mat2x2<f32>,
    translation: vec2<f32>,
}

fn to_device_position_impl(position: vec2<f32>) -> vec4<f32> {
    let device_position = position / globals.viewport_size * vec2<f32>(2.0, -2.0) + vec2<f32>(-1.0, 1.0);
    return vec4<f32>(device_position, 0.0, 1.0);
}

fn to_device_position(unit_vertex: vec2<f32>, bounds: Bounds) -> vec4<f32> {
    let position = unit_vertex * vec2<f32>(bounds.size) + bounds.origin;
    return to_device_position_impl(position);
}

fn to_device_position_transformed(unit_vertex: vec2<f32>, bounds: Bounds, transform: TransformationMatrix) -> vec4<f32> {
    let position = unit_vertex * vec2<f32>(bounds.size) + bounds.origin;
    //Note: Rust side stores it as row-major, so transposing here
    let transformed = transpose(transform.rotation_scale) * position + transform.translation;
    return to_device_position_impl(transformed);
}

fn to_tile_position(unit_vertex: vec2<f32>, tile: AtlasTile) -> vec2<f32> {
  let atlas_size = vec2<f32>(textureDimensions(t_sprite, 0));
  return (vec2<f32>(tile.bounds.origin) + unit_vertex * vec2<f32>(tile.bounds.size)) / atlas_size;
}

fn distance_from_clip_rect_impl(position: vec2<f32>, clip_bounds: Bounds) -> vec4<f32> {
    let tl = position - clip_bounds.origin;
    let br = clip_bounds.origin + clip_bounds.size - position;
    return vec4<f32>(tl.x, br.x, tl.y, br.y);
}

fn distance_from_clip_rect(unit_vertex: vec2<f32>, bounds: Bounds, clip_bounds: Bounds) -> vec4<f32> {
    let position = unit_vertex * vec2<f32>(bounds.size) + bounds.origin;
    return distance_from_clip_rect_impl(position, clip_bounds);
}

fn distance_from_clip_rect_transformed(unit_vertex: vec2<f32>, bounds: Bounds, clip_bounds: Bounds, transform: TransformationMatrix) -> vec4<f32> {
    let position = unit_vertex * vec2<f32>(bounds.size) + bounds.origin;
    let transformed = transpose(transform.rotation_scale) * position + transform.translation;
    return distance_from_clip_rect_impl(transformed, clip_bounds);
}

// https://gamedev.stackexchange.com/questions/92015/optimized-linear-to-srgb-glsl
fn srgb_to_linear(srgb: vec3<f32>) -> vec3<f32> {
    let cutoff = srgb < vec3<f32>(0.04045);
    let higher = pow((srgb + vec3<f32>(0.055)) / vec3<f32>(1.055), vec3<f32>(2.4));
    let lower = srgb / vec3<f32>(12.92);
    return select(higher, lower, cutoff);
}

fn srgb_to_linear_component(a: f32) -> f32 {
    let cutoff = a < 0.04045;
    let higher = pow((a + 0.055) / 1.055, 2.4);
    let lower = a / 12.92;
    return select(higher, lower, cutoff);
}

fn linear_to_srgb(linear: vec3<f32>) -> vec3<f32> {
    let cutoff = linear < vec3<f32>(0.0031308);
    let higher = vec3<f32>(1.055) * pow(linear, vec3<f32>(1.0 / 2.4)) - vec3<f32>(0.055);
    let lower = linear * vec3<f32>(12.92);
    return select(higher, lower, cutoff);
}

/// Convert a linear color to sRGBA space.
fn linear_to_srgba(color: vec4<f32>) -> vec4<f32> {
    return vec4<f32>(linear_to_srgb(color.rgb), color.a);
}

/// Convert a sRGBA color to linear space.
fn srgba_to_linear(color: vec4<f32>) -> vec4<f32> {
    return vec4<f32>(srgb_to_linear(color.rgb), color.a);
}

/// Hsla to linear RGBA conversion.
fn hsla_to_rgba(hsla: Hsla) -> vec4<f32> {
    let h = hsla.h * 6.0; // Now, it's an angle but scaled in [0, 6) range
    let s = hsla.s;
    let l = hsla.l;
    let a = hsla.a;

    let c = (1.0 - abs(2.0 * l - 1.0)) * s;
    let x = c * (1.0 - abs(h % 2.0 - 1.0));
    let m = l - c / 2.0;
    var color = vec3<f32>(m);

    if (h >= 0.0 && h < 1.0) {
        color.r += c;
        color.g += x;
    } else if (h >= 1.0 && h < 2.0) {
        color.r += x;
        color.g += c;
    } else if (h >= 2.0 && h < 3.0) {
        color.g += c;
        color.b += x;
    } else if (h >= 3.0 && h < 4.0) {
        color.g += x;
        color.b += c;
    } else if (h >= 4.0 && h < 5.0) {
        color.r += x;
        color.b += c;
    } else {
        color.r += c;
        color.b += x;
    }

    return vec4<f32>(color, a);
}

/// Convert a linear sRGB to Oklab space.
/// Reference: https://bottosson.github.io/posts/oklab/#converting-from-linear-srgb-to-oklab
fn linear_srgb_to_oklab(color: vec4<f32>) -> vec4<f32> {
	let l = 0.4122214708 * color.r + 0.5363325363 * color.g + 0.0514459929 * color.b;
	let m = 0.2119034982 * color.r + 0.6806995451 * color.g + 0.1073969566 * color.b;
	let s = 0.0883024619 * color.r + 0.2817188376 * color.g + 0.6299787005 * color.b;

	let l_ = pow(l, 1.0 / 3.0);
	let m_ = pow(m, 1.0 / 3.0);
	let s_ = pow(s, 1.0 / 3.0);

	return vec4<f32>(
		0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
		1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
		0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
		color.a
	);
}

/// Convert an Oklab color to linear sRGB space.
fn oklab_to_linear_srgb(color: vec4<f32>) -> vec4<f32> {
	let l_ = color.r + 0.3963377774 * color.g + 0.2158037573 * color.b;
	let m_ = color.r - 0.1055613458 * color.g - 0.0638541728 * color.b;
	let s_ = color.r - 0.0894841775 * color.g - 1.2914855480 * color.b;

	let l = l_ * l_ * l_;
	let m = m_ * m_ * m_;
	let s = s_ * s_ * s_;

	return vec4<f32>(
		4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
		-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
		-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
		color.a
	);
}

fn over(below: vec4<f32>, above: vec4<f32>) -> vec4<f32> {
    let alpha = above.a + below.a * (1.0 - above.a);
    let color = (above.rgb * above.a + below.rgb * below.a * (1.0 - above.a)) / alpha;
    return vec4<f32>(color, alpha);
}

// A standard gaussian function, used for weighting samples
fn gaussian(x: f32, sigma: f32) -> f32{
    return exp(-(x * x) / (2.0 * sigma * sigma)) / (sqrt(2.0 * M_PI_F) * sigma);
}

// This approximates the error function, needed for the gaussian integral
fn erf(v: vec2<f32>) -> vec2<f32> {
    let s = sign(v);
    let a = abs(v);
    let r1 = 1.0 + (0.278393 + (0.230389 + (0.000972 + 0.078108 * a) * a) * a) * a;
    let r2 = r1 * r1;
    return s - s / (r2 * r2);
}

fn blur_along_x(x: f32, y: f32, sigma: f32, corner: f32, half_size: vec2<f32>) -> f32 {
  let delta = min(half_size.y - corner - abs(y), 0.0);
  let curved = half_size.x - corner + sqrt(max(0.0, corner * corner - delta * delta));
  let integral = 0.5 + 0.5 * erf((x + vec2<f32>(-curved, curved)) * (sqrt(0.5) / sigma));
  return integral.y - integral.x;
}

// Selects corner radius based on quadrant.
fn pick_corner_radius(center_to_point: vec2<f32>, radii: Corners) -> f32 {
    if (center_to_point.x < 0.0) {
        if (center_to_point.y < 0.0) {
            return radii.top_left;
        } else {
            return radii.bottom_left;
        }
    } else {
        if (center_to_point.y < 0.0) {
            return radii.top_right;
        } else {
            return radii.bottom_right;
        }
    }
}

// Signed distance of the point to the quad's border - positive outside the
// border, and negative inside.
//
// See comments on similar code using `quad_sdf_impl` in `fs_quad` for
// explanation.
fn quad_sdf(point: vec2<f32>, bounds: Bounds, corner_radii: Corners) -> f32 {
    let half_size = bounds.size / 2.0;
    let center = bounds.origin + half_size;
    let center_to_point = point - center;
    let corner_radius = pick_corner_radius(center_to_point, corner_radii);
    let corner_to_point = abs(center_to_point) - half_size;
    let corner_center_to_point = corner_to_point + corner_radius;
    return quad_sdf_impl(corner_center_to_point, corner_radius);
}

fn quad_sdf_impl(corner_center_to_point: vec2<f32>, corner_radius: f32) -> f32 {
    if (corner_radius == 0.0) {
        // Fast path for unrounded corners.
        return max(corner_center_to_point.x, corner_center_to_point.y);
    } else {
        // Signed distance of the point from a quad that is inset by corner_radius.
        // It is negative inside this quad, and positive outside.
        let signed_distance_to_inset_quad =
            // 0 inside the inset quad, and positive outside.
            length(max(vec2<f32>(0.0), corner_center_to_point)) +
            // 0 outside the inset quad, and negative inside.
            min(0.0, max(corner_center_to_point.x, corner_center_to_point.y));

        return signed_distance_to_inset_quad - corner_radius;
    }
}

// Abstract away the final color transformation based on the
// target alpha compositing mode.
fn blend_color(color: vec4<f32>, alpha_factor: f32) -> vec4<f32> {
    let alpha = color.a * alpha_factor;
    let multiplier = select(1.0, alpha, globals.premultiplied_alpha != 0u);
    return vec4<f32>(color.rgb * multiplier, alpha);
}


struct GradientColor {
    solid: vec4<f32>,
    color0: vec4<f32>,
    color1: vec4<f32>,
}

fn prepare_gradient_color(tag: u32, color_space: u32,
    solid: Hsla, colors: array<LinearColorStop, 2>) -> GradientColor {
    var result = GradientColor();

    if (tag == 0u || tag == 2u || tag == 3u) {
        result.solid = hsla_to_rgba(solid);
    } else if (tag == 1u) {
        // The hsla_to_rgba is returns a linear sRGB color
        result.color0 = hsla_to_rgba(colors[0].color);
        result.color1 = hsla_to_rgba(colors[1].color);

        // Prepare color space in vertex for avoid conversion
        // in fragment shader for performance reasons
        if (color_space == 0u) {
            // sRGB
            result.color0 = linear_to_srgba(result.color0);
            result.color1 = linear_to_srgba(result.color1);
        } else if (color_space == 1u) {
            // Oklab
            result.color0 = linear_srgb_to_oklab(result.color0);
            result.color1 = linear_srgb_to_oklab(result.color1);
        }
    }

    return result;
}

fn gradient_color(background: Background, position: vec2<f32>, bounds: Bounds,
    solid_color: vec4<f32>, color0: vec4<f32>, color1: vec4<f32>) -> vec4<f32> {
    var background_color = vec4<f32>(0.0);

    switch (background.tag) {
        default: {
            return solid_color;
        }
        case 1u: {
            // Linear gradient background.
            // -90 degrees to match the CSS gradient angle.
            let angle = background.gradient_angle_or_pattern_height;
            let radians = (angle % 360.0 - 90.0) * M_PI_F / 180.0;
            var direction = vec2<f32>(cos(radians), sin(radians));
            let stop0_percentage = background.colors[0].percentage;
            let stop1_percentage = background.colors[1].percentage;

            // Expand the short side to be the same as the long side
            if (bounds.size.x > bounds.size.y) {
                direction.y *= bounds.size.y / bounds.size.x;
            } else {
                direction.x *= bounds.size.x / bounds.size.y;
            }

            // Get the t value for the linear gradient with the color stop percentages.
            let half_size = bounds.size / 2.0;
            let center = bounds.origin + half_size;
            let center_to_point = position - center;
            var t = dot(center_to_point, direction) / length(direction);
            // Check the direct to determine the use x or y
            if (abs(direction.x) > abs(direction.y)) {
                t = (t + half_size.x) / bounds.size.x;
            } else {
                t = (t + half_size.y) / bounds.size.y;
            }

            // Adjust t based on the stop percentages
            t = (t - stop0_percentage) / (stop1_percentage - stop0_percentage);
            t = clamp(t, 0.0, 1.0);

            switch (background.color_space) {
                default: {
                    background_color = srgba_to_linear(mix(color0, color1, t));
                }
                case 1u: {
                    let oklab_color = mix(color0, color1, t);
                    background_color = oklab_to_linear_srgb(oklab_color);
                }
            }
        }
        case 2u: {
            // pattern slash
            let gradient_angle_or_pattern_height = background.gradient_angle_or_pattern_height;
            let pattern_width = (gradient_angle_or_pattern_height / 65535.0f) / 255.0f;
            let pattern_interval = (gradient_angle_or_pattern_height % 65535.0f) / 255.0f;
            let pattern_height = pattern_width + pattern_interval;
            let stripe_angle = M_PI_F / 4.0;
            let pattern_period = pattern_height * sin(stripe_angle);
            let rotation = mat2x2<f32>(
                cos(stripe_angle), -sin(stripe_angle),
                sin(stripe_angle), cos(stripe_angle)
            );
            let relative_position = position - bounds.origin;
            let rotated_point = rotation * relative_position;
            let pattern = rotated_point.x % pattern_period;
            let distance = min(pattern, pattern_period - pattern) - pattern_period * (pattern_width / pattern_height) /  2.0f;
            background_color = solid_color;
            background_color.a *= saturate(0.5 - distance);
        }
        case 3u: {
            // checkerboard
            let size = background.gradient_angle_or_pattern_height;
            let relative_position = position - bounds.origin;

            let x_index = floor(relative_position.x / size);
            let y_index = floor(relative_position.y / size);
            let should_be_colored = (x_index + y_index) % 2.0;

            background_color = solid_color;
            background_color.a *= saturate(should_be_colored);
        }
    }

    return background_color;
}

// --- quads --- //

struct Quad {
    order: u32,
    border_style: u32,
    bounds: Bounds,
    content_mask: Bounds,
    background: Background,
    border_color: Hsla,
    corner_radii: Corners,
    border_widths: Edges,
}
@group(1) @binding(0) var<storage, read> b_quads: array<Quad>;

struct QuadVarying {
    @builtin(position) position: vec4<f32>,
    @location(0) @interpolate(flat) border_color: vec4<f32>,
    @location(1) @interpolate(flat) quad_id: u32,
    // TODO: use `clip_distance` once Naga supports it
    @location(2) clip_distances: vec4<f32>,
    @location(3) @interpolate(flat) background_solid: vec4<f32>,
    @location(4) @interpolate(flat) background_color0: vec4<f32>,
    @location(5) @interpolate(flat) background_color1: vec4<f32>,
}

@vertex
fn vs_quad(@builtin(vertex_index) vertex_id: u32, @builtin(instance_index) instance_id: u32) -> QuadVarying {
    let unit_vertex = vec2<f32>(f32(vertex_id & 1u), 0.5 * f32(vertex_id & 2u));
    let quad = b_quads[instance_id];

    var out = QuadVarying();
    out.position = to_device_position(unit_vertex, quad.bounds);

    let gradient = prepare_gradient_color(
        quad.background.tag,
        quad.background.color_space,
        quad.background.solid,
        quad.background.colors
    );
    out.background_solid = gradient.solid;
    out.background_color0 = gradient.color0;
    out.background_color1 = gradient.color1;
    out.border_color = hsla_to_rgba(quad.border_color);
    out.quad_id = instance_id;
    out.clip_distances = distance_from_clip_rect(unit_vertex, quad.bounds, quad.content_mask);
    return out;
}

@fragment
fn fs_quad(input: QuadVarying) -> @location(0) vec4<f32> {
    // Alpha clip first, since we don't have `clip_distance`.
    if (any(input.clip_distances < vec4<f32>(0.0))) {
        return vec4<f32>(0.0);
    }

    let quad = b_quads[input.quad_id];

    let background_color = gradient_color(quad.background, input.position.xy, quad.bounds,
        input.background_solid, input.background_color0, input.background_color1);

    let unrounded = quad.corner_radii.top_left == 0.0 &&
        quad.corner_radii.bottom_left == 0.0 &&
        quad.corner_radii.top_right == 0.0 &&
        quad.corner_radii.bottom_right == 0.0;

    // Fast path when the quad is not rounded and doesn't have any border
    if (quad.border_widths.top == 0.0 &&
            quad.border_widths.left == 0.0 &&
            quad.border_widths.right == 0.0 &&
            quad.border_widths.bottom == 0.0 &&
            unrounded) {
        return blend_color(background_color, 1.0);
    }

    let size = quad.bounds.size;
    let half_size = size / 2.0;
    let point = input.position.xy - quad.bounds.origin;
    let center_to_point = point - half_size;

    // Signed distance field threshold for inclusion of pixels. 0.5 is the
    // minimum distance between the center of the pixel and the edge.
    let antialias_threshold = 0.5;

    // Radius of the nearest corner
    let corner_radius = pick_corner_radius(center_to_point, quad.corner_radii);

    // Width of the nearest borders
    let border = vec2<f32>(
        select(
            quad.border_widths.right,
            quad.border_widths.left,
            center_to_point.x < 0.0),
        select(
            quad.border_widths.bottom,
            quad.border_widths.top,
            center_to_point.y < 0.0));

    // 0-width borders are reduced so that `inner_sdf >= antialias_threshold`.
    // The purpose of this is to not draw antialiasing pixels in this case.
    let reduced_border =
        vec2<f32>(select(border.x, -antialias_threshold, border.x == 0.0),
                  select(border.y, -antialias_threshold, border.y == 0.0));

    // Vector from the corner of the quad bounds to the point, after mirroring
    // the point into the bottom right quadrant. Both components are <= 0.
    let corner_to_point = abs(center_to_point) - half_size;

    // Vector from the point to the center of the rounded corner's circle, also
    // mirrored into bottom right quadrant.
    let corner_center_to_point = corner_to_point + corner_radius;

    // Whether the nearest point on the border is rounded
    let is_near_rounded_corner =
            corner_center_to_point.x >= 0 &&
            corner_center_to_point.y >= 0;

    // Vector from straight border inner corner to point.
    let straight_border_inner_corner_to_point = corner_to_point + reduced_border;

    // Whether the point is beyond the inner edge of the straight border.
    let is_beyond_inner_straight_border =
            straight_border_inner_corner_to_point.x > 0 ||
            straight_border_inner_corner_to_point.y > 0;

    // Whether the point is far enough inside the quad, such that the pixels are
    // not affected by the straight border.
    let is_within_inner_straight_border =
        straight_border_inner_corner_to_point.x < -antialias_threshold &&
        straight_border_inner_corner_to_point.y < -antialias_threshold;

    // Fast path for points that must be part of the background.
    //
    // This could be optimized further for large rounded corners by including
    // points in an inscribed rectangle, or some other quick linear check.
    // However, that might negatively impact performance in the case of
    // reasonable sizes for rounded corners.
    if (is_within_inner_straight_border && !is_near_rounded_corner) {
        return blend_color(background_color, 1.0);
    }

    // Signed distance of the point to the outside edge of the quad's border. It
    // is positive outside this edge, and negative inside.
    let outer_sdf = quad_sdf_impl(corner_center_to_point, corner_radius);

    // Approximate signed distance of the point to the inside edge of the quad's
    // border. It is negative outside this edge (within the border), and
    // positive inside.
    //
    // This is not always an accurate signed distance:
    // * The rounded portions with varying border width use an approximation of
    //   nearest-point-on-ellipse.
    // * When it is quickly known to be outside the edge, -1.0 is used.
    var inner_sdf = 0.0;
    if (corner_center_to_point.x <= 0 || corner_center_to_point.y <= 0) {
        // Fast paths for straight borders.
        inner_sdf = -max(straight_border_inner_corner_to_point.x,
                         straight_border_inner_corner_to_point.y);
    } else if (is_beyond_inner_straight_border) {
        // Fast path for points that must be outside the inner edge.
        inner_sdf = -1.0;
    } else if (reduced_border.x == reduced_border.y) {
        // Fast path for circular inner edge.
        inner_sdf = -(outer_sdf + reduced_border.x);
    } else {
        let ellipse_radii = max(vec2<f32>(0.0), corner_radius - reduced_border);
        inner_sdf = quarter_ellipse_sdf(corner_center_to_point, ellipse_radii);
    }

    // Negative when inside the border
    let border_sdf = max(inner_sdf, outer_sdf);

    var color = background_color;
    if (border_sdf < antialias_threshold) {
        var border_color = input.border_color;

        // Dashed border logic when border_style == 1
        if (quad.border_style == 1) {
            // Position along the perimeter in "dash space", where each dash
            // period has length 1
            var t = 0.0;

            // Total number of dash periods, so that the dash spacing can be
            // adjusted to evenly divide it
            var max_t = 0.0;

            // Border width is proportional to dash size. This is the behavior
            // used by browsers, but also avoids dashes from different segments
            // overlapping when dash size is smaller than the border width.
            //
            // Dash pattern: (2 * border width) dash, (1 * border width) gap
            let dash_length_per_width = 2.0;
            let dash_gap_per_width = 1.0;
            let dash_period_per_width = dash_length_per_width + dash_gap_per_width;

            // Since the dash size is determined by border width, the density of
            // dashes varies. Multiplying a pixel distance by this returns a
            // position in dash space - it has units (dash period / pixels). So
            // a dash velocity of (1 / 10) is 1 dash every 10 pixels.
            var dash_velocity = 0.0;

            // Dividing this by the border width gives the dash velocity
            let dv_numerator = 1.0 / dash_period_per_width;

            if (unrounded) {
                // When corners aren't rounded, the dashes are separately laid
                // out on each straight line, rather than around the whole
                // perimeter. This way each line starts and ends with a dash.
                let is_horizontal =
                        corner_center_to_point.x <
                        corner_center_to_point.y;

                // When applying dashed borders to just some, not all, the sides.
                // The way we chose border widths above sometimes comes with a 0 width value.
                // So we choose again to avoid division by zero.
                // TODO: A better solution exists taking a look at the whole file.
                // this does not fix single dashed borders at the corners
                let dashed_border = vec2<f32>(
                        max(
                            quad.border_widths.bottom,
                            quad.border_widths.top,
                        ),
                        max(
                            quad.border_widths.right,
                            quad.border_widths.left,
                        )
                   );

                let border_width = select(dashed_border.y, dashed_border.x, is_horizontal);
                dash_velocity = dv_numerator / border_width;
                t = select(point.y, point.x, is_horizontal) * dash_velocity;
                max_t = select(size.y, size.x, is_horizontal) * dash_velocity;
            } else {
                // When corners are rounded, the dashes are laid out clockwise
                // around the whole perimeter.

                let r_tr = quad.corner_radii.top_right;
                let r_br = quad.corner_radii.bottom_right;
                let r_bl = quad.corner_radii.bottom_left;
                let r_tl = quad.corner_radii.top_left;

                let w_t = quad.border_widths.top;
                let w_r = quad.border_widths.right;
                let w_b = quad.border_widths.bottom;
                let w_l = quad.border_widths.left;

                // Straight side dash velocities
                let dv_t = select(dv_numerator / w_t, 0.0, w_t <= 0.0);
                let dv_r = select(dv_numerator / w_r, 0.0, w_r <= 0.0);
                let dv_b = select(dv_numerator / w_b, 0.0, w_b <= 0.0);
                let dv_l = select(dv_numerator / w_l, 0.0, w_l <= 0.0);

                // Straight side lengths in dash space
                let s_t = (size.x - r_tl - r_tr) * dv_t;
                let s_r = (size.y - r_tr - r_br) * dv_r;
                let s_b = (size.x - r_br - r_bl) * dv_b;
                let s_l = (size.y - r_bl - r_tl) * dv_l;

                let corner_dash_velocity_tr = corner_dash_velocity(dv_t, dv_r);
                let corner_dash_velocity_br = corner_dash_velocity(dv_b, dv_r);
                let corner_dash_velocity_bl = corner_dash_velocity(dv_b, dv_l);
                let corner_dash_velocity_tl = corner_dash_velocity(dv_t, dv_l);

                // Corner lengths in dash space
                let c_tr = r_tr * (M_PI_F / 2.0) * corner_dash_velocity_tr;
                let c_br = r_br * (M_PI_F / 2.0) * corner_dash_velocity_br;
                let c_bl = r_bl * (M_PI_F / 2.0) * corner_dash_velocity_bl;
                let c_tl = r_tl * (M_PI_F / 2.0) * corner_dash_velocity_tl;

                // Cumulative dash space upto each segment
                let upto_tr = s_t;
                let upto_r = upto_tr + c_tr;
                let upto_br = upto_r + s_r;
                let upto_b = upto_br + c_br;
                let upto_bl = upto_b + s_b;
                let upto_l = upto_bl + c_bl;
                let upto_tl = upto_l + s_l;
                max_t = upto_tl + c_tl;

                if (is_near_rounded_corner) {
                    let radians = atan2(corner_center_to_point.y,
                                        corner_center_to_point.x);
                    let corner_t = radians * corner_radius;

                    if (center_to_point.x >= 0.0) {
                        if (center_to_point.y < 0.0) {
                            dash_velocity = corner_dash_velocity_tr;
                            // Subtracted because radians is pi/2 to 0 when
                            // going clockwise around the top right corner,
                            // since the y axis has been flipped
                            t = upto_r - corner_t * dash_velocity;
                        } else {
                            dash_velocity = corner_dash_velocity_br;
                            // Added because radians is 0 to pi/2 when going
                            // clockwise around the bottom-right corner
                            t = upto_br + corner_t * dash_velocity;
                        }
                    } else {
                        if (center_to_point.y >= 0.0) {
                            dash_velocity = corner_dash_velocity_bl;
                            // Subtracted because radians is pi/2 to 0 when
                            // going clockwise around the bottom-left corner,
                            // since the x axis has been flipped
                            t = upto_l - corner_t * dash_velocity;
                        } else {
                            dash_velocity = corner_dash_velocity_tl;
                            // Added because radians is 0 to pi/2 when going
                            // clockwise around the top-left corner, since both
                            // axis were flipped
                            t = upto_tl + corner_t * dash_velocity;
                        }
                    }
                } else {
                    // Straight borders
                    let is_horizontal =
                            corner_center_to_point.x <
                            corner_center_to_point.y;
                    if (is_horizontal) {
                        if (center_to_point.y < 0.0) {
                            dash_velocity = dv_t;
                            t = (point.x - r_tl) * dash_velocity;
                        } else {
                            dash_velocity = dv_b;
                            t = upto_bl - (point.x - r_bl) * dash_velocity;
                        }
                    } else {
                        if (center_to_point.x < 0.0) {
                            dash_velocity = dv_l;
                            t = upto_tl - (point.y - r_tl) * dash_velocity;
                        } else {
                            dash_velocity = dv_r;
                            t = upto_r + (point.y - r_tr) * dash_velocity;
                        }
                    }
                }
            }

            let dash_length = dash_length_per_width / dash_period_per_width;
            let desired_dash_gap = dash_gap_per_width / dash_period_per_width;

            // Straight borders should start and end with a dash, so max_t is
            // reduced to cause this.
            max_t -= select(0.0, dash_length, unrounded);
            if (max_t >= 1.0) {
                // Adjust dash gap to evenly divide max_t.
                let dash_count = floor(max_t);
                let dash_period = max_t / dash_count;
                border_color.a *= dash_alpha(
                    t,
                    dash_period,
                    dash_length,
                    dash_velocity,
                    antialias_threshold);
            } else if (unrounded) {
                // When there isn't enough space for the full gap between the
                // two start / end dashes of a straight border, reduce gap to
                // make them fit.
                let dash_gap = max_t - dash_length;
                if (dash_gap > 0.0) {
                    let dash_period = dash_length + dash_gap;
                    border_color.a *= dash_alpha(
                        t,
                        dash_period,
                        dash_length,
                        dash_velocity,
                        antialias_threshold);
                }
            }
        }

        // Blend the border on top of the background and then linearly interpolate
        // between the two as we slide inside the background.
        let blended_border = over(background_color, border_color);
        color = mix(background_color, blended_border,
                    saturate(antialias_threshold - inner_sdf));
    }

    return blend_color(color, saturate(antialias_threshold - outer_sdf));
}

// Layout mirrors `ShaderQuadPrimitive` in `wgpu_renderer.rs`. We use only
// scalar fields so WGSL alignment matches Rust `#[repr(C)]` without padding
// surprises (vec3/vec4 storage members would otherwise round up to 16 bytes).
struct ShaderQuad {
    bounds: Bounds,
    content_mask: Bounds,
    corner_radius_tl: f32,
    corner_radius_tr: f32,
    corner_radius_br: f32,
    corner_radius_bl: f32,
    opacity: f32,
    variant: u32,
    // Supersample multiplier (1, 2, or 4). Heavy variants may multiply
    // ALU per pixel by sampling the underlying scene `supersample^2` times
    // and averaging, trading frametime for crispness / GPU load.
    supersample: u32,
    pad1: u32,

    // Shadertoy-style globals.
    iResolution_x: f32,
    iResolution_y: f32,
    iResolution_z: f32,
    iTime: f32,

    iTimeDelta: f32,
    iFrame: f32,
    iMouse_x: f32,
    iMouse_y: f32,

    iMouse_z: f32,
    iMouse_w: f32,
    iDate_x: f32,
    iDate_y: f32,

    iDate_z: f32,
    iDate_w: f32,
    pad2: f32,
    pad3: f32,

    // Sixteen app-provided scalars (mirrors `ShaderMaterial.params`). Built-in
    // variants typically read `param_0..param_3` as a `vec4` palette /
    // animation hint; the audio_reactive variant reads all sixteen.
    param_0: f32,
    param_1: f32,
    param_2: f32,
    param_3: f32,
    param_4: f32,
    param_5: f32,
    param_6: f32,
    param_7: f32,
    param_8: f32,
    param_9: f32,
    param_10: f32,
    param_11: f32,
    param_12: f32,
    param_13: f32,
    param_14: f32,
    param_15: f32,
}
@group(1) @binding(0) var<storage, read> b_shader_quads: array<ShaderQuad>;

const SHADER_QUAD_PLASMA: u32 = 0u;
const SHADER_QUAD_RIBBON: u32 = 1u;
const SHADER_QUAD_WAVE_GRID: u32 = 2u;
const SHADER_QUAD_SPECTRUM_BARS: u32 = 3u;
const SHADER_QUAD_WARP_FIELD: u32 = 4u;
const SHADER_QUAD_CAMERA: u32 = 5u;
const SHADER_QUAD_VOLUMETRIC_CLOUDS: u32 = 6u;
const SHADER_QUAD_MANDELBULB: u32 = 7u;
const SHADER_QUAD_KIFS_TEMPLE: u32 = 8u;
const SHADER_QUAD_TUNNEL_WARP: u32 = 9u;
const SHADER_QUAD_BLACK_HOLE: u32 = 10u;
const SHADER_QUAD_HYPERSPACE_JUMP: u32 = 11u;
const SHADER_QUAD_FERROFLUID: u32 = 12u;
const SHADER_QUAD_APOLLONIAN_GASKET: u32 = 13u;
const SHADER_QUAD_AUDIO_REACTIVE: u32 = 14u;

fn shader_quad_corner_radii(shader_quad: ShaderQuad) -> Corners {
    return Corners(
        shader_quad.corner_radius_tl,
        shader_quad.corner_radius_tr,
        shader_quad.corner_radius_br,
        shader_quad.corner_radius_bl,
    );
}

fn shader_quad_resolution(shader_quad: ShaderQuad) -> vec3<f32> {
    return vec3<f32>(shader_quad.iResolution_x, shader_quad.iResolution_y, shader_quad.iResolution_z);
}

// First four user-supplied scalars as a vec4. Heavy variants accept this
// as a "palette / intensity / speed / detail" hint.
fn shader_quad_params4(shader_quad: ShaderQuad) -> vec4<f32> {
    return vec4<f32>(
        shader_quad.param_0,
        shader_quad.param_1,
        shader_quad.param_2,
        shader_quad.param_3,
    );
}

// Returns the i-th of the sixteen user-supplied scalars. Used by
// audio_reactive to walk a per-band spectrum without exposing a 16-wide
// signature on every variant.
fn shader_quad_param(shader_quad: ShaderQuad, i: i32) -> f32 {
    switch i {
        case 0: { return shader_quad.param_0; }
        case 1: { return shader_quad.param_1; }
        case 2: { return shader_quad.param_2; }
        case 3: { return shader_quad.param_3; }
        case 4: { return shader_quad.param_4; }
        case 5: { return shader_quad.param_5; }
        case 6: { return shader_quad.param_6; }
        case 7: { return shader_quad.param_7; }
        case 8: { return shader_quad.param_8; }
        case 9: { return shader_quad.param_9; }
        case 10: { return shader_quad.param_10; }
        case 11: { return shader_quad.param_11; }
        case 12: { return shader_quad.param_12; }
        case 13: { return shader_quad.param_13; }
        case 14: { return shader_quad.param_14; }
        default: { return shader_quad.param_15; }
    }
}

struct ShaderQuadVarying {
    @builtin(position) position: vec4<f32>,
    @location(0) @interpolate(flat) shader_quad_id: u32,
    @location(1) clip_distances: vec4<f32>,
}

@vertex
fn vs_shader_quad(@builtin(vertex_index) vertex_id: u32, @builtin(instance_index) instance_id: u32) -> ShaderQuadVarying {
    let unit_vertex = vec2<f32>(f32(vertex_id & 1u), 0.5 * f32(vertex_id & 2u));
    let shader_quad = b_shader_quads[instance_id];

    // Vertex displacement, scoped per variant so the rasterized quad can ripple.
    var displaced = unit_vertex;
    if (shader_quad.variant == SHADER_QUAD_WARP_FIELD) {
        let edge = unit_vertex * 2.0 - vec2<f32>(1.0);
        let amount = 0.025;
        displaced = displaced + vec2<f32>(
            sin(shader_quad.iTime * 1.7 + edge.y * 6.2832) * amount,
            cos(shader_quad.iTime * 1.3 + edge.x * 6.2832) * amount,
        );
    }

    var out = ShaderQuadVarying();
    out.position = to_device_position(displaced, shader_quad.bounds);
    out.shader_quad_id = instance_id;
    out.clip_distances = distance_from_clip_rect(displaced, shader_quad.bounds, shader_quad.content_mask);
    return out;
}

fn shader_quad_plasma(uv: vec2<f32>, time: f32) -> vec3<f32> {
    let wave = 0.5 + 0.5 * sin((uv.x * 12.0) + (uv.y * 6.0) + time * 2.5);
    let pulse = 0.5 + 0.5 * sin(time + uv.x * 4.0);
    return vec3<f32>(uv.x * 0.65 + pulse * 0.35, uv.y * 0.6 + wave * 0.4, 1.0 - uv.x * 0.5);
}

// Procedural rotating mesh that emulates a Shadertoy-style "Image" pass with
// a moving camera. The mesh is the union of a centered sphere and a torus,
// raymarched in shader_quad-local space and shaded with a directional light.
fn camera_rotation(angle: f32) -> mat3x3<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat3x3<f32>(
        vec3<f32>(c, 0.0, -s),
        vec3<f32>(0.0, 1.0, 0.0),
        vec3<f32>(s, 0.0, c),
    );
}

fn camera_sd_torus(p: vec3<f32>, major: f32, minor: f32) -> f32 {
    let q = vec2<f32>(length(p.xz) - major, p.y);
    return length(q) - minor;
}

fn camera_scene_sdf(p: vec3<f32>) -> f32 {
    let sphere = length(p) - 0.55;
    let torus = camera_sd_torus(p, 0.95, 0.18);
    return min(sphere, torus);
}

fn camera_scene_normal(p: vec3<f32>) -> vec3<f32> {
    let h = 0.0015;
    let dx = camera_scene_sdf(p + vec3<f32>(h, 0.0, 0.0))
           - camera_scene_sdf(p - vec3<f32>(h, 0.0, 0.0));
    let dy = camera_scene_sdf(p + vec3<f32>(0.0, h, 0.0))
           - camera_scene_sdf(p - vec3<f32>(0.0, h, 0.0));
    let dz = camera_scene_sdf(p + vec3<f32>(0.0, 0.0, h))
           - camera_scene_sdf(p - vec3<f32>(0.0, 0.0, h));
    return normalize(vec3<f32>(dx, dy, dz));
}

fn shader_quad_camera(uv: vec2<f32>, resolution: vec2<f32>, time: f32) -> vec3<f32> {
    let aspect = resolution.x / max(resolution.y, 1.0);
    let centered = (uv * 2.0 - vec2<f32>(1.0)) * vec2<f32>(aspect, 1.0);

    let yaw = time * 0.5;
    let pitch = sin(time * 0.35) * 0.35;
    let camera_distance = 3.0;

    var ray_origin = vec3<f32>(0.0, 0.0, camera_distance);
    let pitch_matrix = mat3x3<f32>(
        vec3<f32>(1.0, 0.0, 0.0),
        vec3<f32>(0.0, cos(pitch), -sin(pitch)),
        vec3<f32>(0.0, sin(pitch), cos(pitch)),
    );
    ray_origin = pitch_matrix * ray_origin;
    ray_origin = camera_rotation(yaw) * ray_origin;

    var ray_direction = normalize(vec3<f32>(centered, -1.7));
    ray_direction = pitch_matrix * ray_direction;
    ray_direction = camera_rotation(yaw) * ray_direction;

    var t = 0.0;
    var hit = false;
    var hit_position = vec3<f32>(0.0);
    for (var i = 0; i < 64; i = i + 1) {
        hit_position = ray_origin + ray_direction * t;
        let distance_to_scene = camera_scene_sdf(hit_position);
        if (distance_to_scene < 0.0015) {
            hit = true;
            break;
        }
        t = t + distance_to_scene;
        if (t > 8.0) {
            break;
        }
    }

    let background = mix(
        vec3<f32>(0.04, 0.05, 0.10),
        vec3<f32>(0.10, 0.18, 0.32),
        clamp(uv.y, 0.0, 1.0),
    );
    if (!hit) {
        return background;
    }

    let normal = camera_scene_normal(hit_position);
    let light_dir = normalize(vec3<f32>(0.6, 0.85, 0.5));
    let diffuse = clamp(dot(normal, light_dir), 0.0, 1.0);
    let view_dir = normalize(ray_origin - hit_position);
    let halfway = normalize(light_dir + view_dir);
    let specular = pow(clamp(dot(normal, halfway), 0.0, 1.0), 48.0);

    let warm = vec3<f32>(1.0, 0.62, 0.28);
    let cool = vec3<f32>(0.25, 0.65, 1.0);
    let base_color = mix(cool, warm, 0.5 + 0.5 * normal.y);
    let lit = base_color * (0.18 + 0.82 * diffuse) + vec3<f32>(1.0) * specular * 0.65;
    let depth_fade = clamp(1.0 - t * 0.18, 0.4, 1.0);
    return mix(background, lit, depth_fade);
}

fn shader_quad_ribbon(uv: vec2<f32>, time: f32) -> vec3<f32> {
    let centered = uv * 2.0 - vec2<f32>(1.0);
    let wave = sin(centered.x * 5.5 + time * 1.7) * 0.45;
    let band = exp(-pow((centered.y - wave) * 4.5, 2.0));
    let glow = exp(-pow((centered.y - wave) * 2.0, 2.0)) * 0.6;
    let palette = vec3<f32>(0.95, 0.45, 0.85) * band + vec3<f32>(0.25, 0.85, 1.0) * glow;
    return palette;
}

fn shader_quad_wave_grid(uv: vec2<f32>, time: f32) -> vec3<f32> {
    let cells = vec2<f32>(18.0, 9.0);
    let cell = uv * cells;
    let cell_center = abs(fract(cell) - vec2<f32>(0.5));
    let line = smoothstep(0.45, 0.5, max(cell_center.x, cell_center.y));
    let pulse = 0.5 + 0.5 * sin(uv.x * 6.0 - time * 2.0);
    let warm = vec3<f32>(1.0, 0.5 + pulse * 0.4, 0.2);
    let cool = vec3<f32>(0.15, 0.6, 1.0);
    return mix(cool, warm, line);
}

fn shader_quad_spectrum_bars(uv: vec2<f32>, time: f32) -> vec3<f32> {
    let bars = 24.0;
    let column = floor(uv.x * bars);
    let column_uv = fract(uv.x * bars);
    let phase = column / bars * 6.2832;
    let height = 0.45 + 0.45 * sin(time * 1.6 + phase) + 0.2 * sin(time * 4.0 + phase * 1.5);
    let bar_mask = step(column_uv, 0.85) * step(1.0 - height, uv.y);
    let palette = mix(
        vec3<f32>(0.0, 0.7, 1.0),
        vec3<f32>(1.0, 0.45, 0.7),
        clamp(uv.y * 1.2, 0.0, 1.0),
    );
    return palette * bar_mask;
}

fn shader_quad_warp_field(uv: vec2<f32>, time: f32) -> vec3<f32> {
    let centered = uv * 2.0 - vec2<f32>(1.0);
    let radius = length(centered);
    let angle = atan2(centered.y, centered.x);
    let stripes = 0.5 + 0.5 * sin(8.0 * radius - time * 2.5 + angle * 3.0);
    let palette = mix(
        vec3<f32>(0.05, 0.1, 0.35),
        vec3<f32>(0.95, 0.85, 0.4),
        stripes,
    );
    return palette;
}

// ---- New extreme built-in shaders. ----------------------------------------
// Each function returns linear RGB in [0, 1]^3. They receive normalized
// `uv` in [0, 1] (origin top-left), the quad pixel `resolution`, and the
// shared `time` global so they can match Shadertoy "Image" semantics.

fn shader_quad_volumetric_clouds(
    uv: vec2<f32>,
    resolution: vec2<f32>,
    time: f32,
) -> vec3<f32> {
    // Aspect-correct screen coords with origin at the center, y up.
    let aspect = max(resolution.x, 1.0) / max(resolution.y, 1.0);
    var p = vec2<f32>((uv.x - 0.5) * 2.0 * aspect, (0.5 - uv.y) * 2.0);

    // Camera with a subtle bob so the scene feels alive.
    let t = time;
    let bob = sin(t * 0.35) * 0.08;
    let cam_pos = vec3<f32>(0.0, 1.2 + bob, t * 0.6);
    // Look slightly upward into the cloud layer.
    let look_pitch = 0.18 + sin(t * 0.21) * 0.02;
    let cp = cos(look_pitch);
    let sp = sin(look_pitch);

    // Build a forward ray from the screen point. Forward is +z.
    var rd = normalize(vec3<f32>(p.x, p.y * 1.0, 1.4));
    // Apply pitch (rotate around X axis).
    rd = vec3<f32>(rd.x, rd.y * cp - rd.z * sp, rd.y * sp + rd.z * cp);
    rd = normalize(rd);

    // Sun direction (high-ish, slightly to the right, in front of camera).
    let sun_dir = normalize(vec3<f32>(0.55, 0.45, 0.7));

    // ----- Sky gradient with sun glow ----------------------------------
    let horizon = clamp(rd.y * 0.5 + 0.5, 0.0, 1.0);
    let sky_top = vec3<f32>(0.18, 0.36, 0.72);
    let sky_horizon = vec3<f32>(0.78, 0.82, 0.88);
    var sky = mix(sky_horizon, sky_top, pow(horizon, 1.2));
    let sun_d = max(dot(rd, sun_dir), 0.0);
    let sun_disk = pow(sun_d, 1200.0);
    let sun_bloom = pow(sun_d, 6.0) * 0.45 + pow(sun_d, 32.0) * 0.55;
    let sun_color = vec3<f32>(1.0, 0.92, 0.78);
    sky = sky + sun_color * sun_bloom;
    sky = sky + sun_color * sun_disk * 4.0;

    // If we're looking down (under the cloud layer base), darken slightly so
    // the lower edge of the tile reads as ground haze rather than sky.
    let ground_haze = smoothstep(0.0, -0.25, rd.y);
    sky = mix(sky, vec3<f32>(0.55, 0.55, 0.6), ground_haze * 0.5);

    // ----- Volumetric clouds -------------------------------------------
    // Cloud slab from y = 1.5 to y = 4.0 in world units. Only march if the
    // ray actually points upward enough to cross it. (Avoid div-by-zero.)
    let cloud_base: f32 = 1.5;
    let cloud_top: f32 = 4.0;
    var color = sky;

    if (rd.y > 0.02) {
        let inv_ry = 1.0 / max(rd.y, 1e-3);
        let t_enter = (cloud_base - cam_pos.y) * inv_ry;
        let t_exit = (cloud_top - cam_pos.y) * inv_ry;
        let t_start = max(t_enter, 0.0);
        let t_end = max(t_exit, t_start);
        let span = max(t_end - t_start, 0.0);

        // Step count adapts a bit with horizon; capped at 48.
        let step_count: i32 = 40;
        let inv_steps = 1.0 / f32(step_count);
        let dt = span * inv_steps;

        // Wind: scroll the volume so clouds drift.
        let wind = vec3<f32>(t * 0.6, 0.0, t * 0.25);

        // Front-to-back accumulation.
        var transmittance: f32 = 1.0;
        var scattered: vec3<f32> = vec3<f32>(0.0);

        // Small dither to break up banding (cheap hash on screen pos).
        let dither_seed = fract(sin(dot(uv * resolution, vec2<f32>(12.9898, 78.233))) * 43758.5453);
        var t_ray = t_start + dt * dither_seed;

        for (var i: i32 = 0; i < 48; i = i + 1) {
            if (i >= step_count) { break; }
            if (transmittance < 0.02) { break; }

            let pos = cam_pos + rd * t_ray + wind;

            // ---- 4-octave value-noise fbm (fully inlined) ----
            // Each octave: smooth interpolation of a hash at integer lattice.
            var amp: f32 = 0.5;
            var freq: f32 = 0.35;
            var fbm: f32 = 0.0;
            var fp = pos;
            for (var o: i32 = 0; o < 4; o = o + 1) {
                let q = fp * freq;
                let qi = floor(q);
                let qf = q - qi;
                let w = qf * qf * (3.0 - 2.0 * qf);

                // 8 hashed corners.
                let n000 = fract(sin(dot(qi + vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
                let n100 = fract(sin(dot(qi + vec3<f32>(1.0, 0.0, 0.0), vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
                let n010 = fract(sin(dot(qi + vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
                let n110 = fract(sin(dot(qi + vec3<f32>(1.0, 1.0, 0.0), vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
                let n001 = fract(sin(dot(qi + vec3<f32>(0.0, 0.0, 1.0), vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
                let n101 = fract(sin(dot(qi + vec3<f32>(1.0, 0.0, 1.0), vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
                let n011 = fract(sin(dot(qi + vec3<f32>(0.0, 1.0, 1.0), vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
                let n111 = fract(sin(dot(qi + vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);

                let nx00 = mix(n000, n100, w.x);
                let nx10 = mix(n010, n110, w.x);
                let nx01 = mix(n001, n101, w.x);
                let nx11 = mix(n011, n111, w.x);
                let nxy0 = mix(nx00, nx10, w.y);
                let nxy1 = mix(nx01, nx11, w.y);
                let n = mix(nxy0, nxy1, w.z);

                fbm = fbm + amp * n;
                amp = amp * 0.5;
                freq = freq * 2.05;
                fp = fp * 1.03;
            }
            // Normalize fbm roughly into [0, 1].
            let fbm_n = clamp(fbm / 0.9375, 0.0, 1.0);

            // Vertical falloff so clouds are puffy in the middle of the slab.
            let h = clamp((pos.y - cloud_base) / max(cloud_top - cloud_base, 1e-3), 0.0, 1.0);
            let shape = smoothstep(0.0, 0.25, h) * smoothstep(1.0, 0.55, h);

            // Density: erode lower frequencies with a threshold for crisp shapes.
            var density = clamp((fbm_n - 0.42) * 1.7, 0.0, 1.0) * shape;
            density = density * 1.15;

            if (density > 0.001) {
                // ---- Light march toward the sun (5 short steps) ----
                var light_t: f32 = 0.0;
                var light_density: f32 = 0.0;
                let l_step: f32 = 0.18;
                for (var ls: i32 = 0; ls < 5; ls = ls + 1) {
                    light_t = light_t + l_step;
                    let lp = pos + sun_dir * light_t + wind;

                    // Cheaper 3-octave fbm for shadow rays.
                    var lamp: f32 = 0.5;
                    var lfreq: f32 = 0.35;
                    var lfbm: f32 = 0.0;
                    var lfp = lp;
                    for (var lo: i32 = 0; lo < 3; lo = lo + 1) {
                        let lq = lfp * lfreq;
                        let lqi = floor(lq);
                        let lqf = lq - lqi;
                        let lw = lqf * lqf * (3.0 - 2.0 * lqf);
                        let m000 = fract(sin(dot(lqi + vec3<f32>(0.0, 0.0, 0.0), vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
                        let m100 = fract(sin(dot(lqi + vec3<f32>(1.0, 0.0, 0.0), vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
                        let m010 = fract(sin(dot(lqi + vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
                        let m110 = fract(sin(dot(lqi + vec3<f32>(1.0, 1.0, 0.0), vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
                        let m001 = fract(sin(dot(lqi + vec3<f32>(0.0, 0.0, 1.0), vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
                        let m101 = fract(sin(dot(lqi + vec3<f32>(1.0, 0.0, 1.0), vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
                        let m011 = fract(sin(dot(lqi + vec3<f32>(0.0, 1.0, 1.0), vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
                        let m111 = fract(sin(dot(lqi + vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453);
                        let mx00 = mix(m000, m100, lw.x);
                        let mx10 = mix(m010, m110, lw.x);
                        let mx01 = mix(m001, m101, lw.x);
                        let mx11 = mix(m011, m111, lw.x);
                        let mxy0 = mix(mx00, mx10, lw.y);
                        let mxy1 = mix(mx01, mx11, lw.y);
                        let mn = mix(mxy0, mxy1, lw.z);
                        lfbm = lfbm + lamp * mn;
                        lamp = lamp * 0.5;
                        lfreq = lfreq * 2.05;
                        lfp = lfp * 1.03;
                    }
                    let lfbm_n = clamp(lfbm / 0.875, 0.0, 1.0);
                    let lh = clamp((lp.y - cloud_base) / max(cloud_top - cloud_base, 1e-3), 0.0, 1.0);
                    let lshape = smoothstep(0.0, 0.25, lh) * smoothstep(1.0, 0.55, lh);
                    let ldens = clamp((lfbm_n - 0.42) * 1.7, 0.0, 1.0) * lshape;
                    light_density = light_density + ldens * l_step;
                }

                // Beer-Lambert toward the sun.
                let sun_t = exp(-light_density * 4.0);
                // Henyey-Greenstein-ish forward scattering toward the sun.
                let cos_theta = dot(rd, sun_dir);
                let hg = 0.6 + 0.4 * pow(max(cos_theta * 0.5 + 0.5, 1e-4), 4.0);

                // Color: white-hot rim from sun_t, cool ambient from sky.
                let ambient = mix(vec3<f32>(0.35, 0.42, 0.55), vec3<f32>(0.78, 0.80, 0.85), h);
                let direct = sun_color * sun_t * hg * 1.6;
                let cloud_col = ambient + direct;

                // Step transmittance and accumulate.
                let step_density = density * dt;
                let step_t = exp(-step_density * 2.4);
                let absorbed = (1.0 - step_t) * transmittance;
                scattered = scattered + cloud_col * absorbed;
                transmittance = transmittance * step_t;
            }

            t_ray = t_ray + dt;
        }

        // Composite clouds over sky.
        color = sky * transmittance + scattered;
    }

    // Mild atmospheric tint near the bottom (haze pickup).
    let bottom = smoothstep(0.0, 0.4, 1.0 - uv.y);
    color = mix(vec3<f32>(0.82, 0.84, 0.88) * 0.9, color, 0.2 + 0.8 * bottom);

    // Tone map (Reinhard-ish) and gamma-ish soft curve.
    color = color / (1.0 + color);
    color = pow(max(color, vec3<f32>(0.0)), vec3<f32>(0.85));

    return clamp(color, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn shader_quad_mandelbulb(
    uv: vec2<f32>,
    resolution: vec2<f32>,
    time: f32,
) -> vec3<f32> {
    // Map uv (origin top-left) to NDC with correct aspect, y-up.
    let aspect = max(resolution.x, 1.0) / max(resolution.y, 1.0);
    let p = vec2<f32>(
        (uv.x * 2.0 - 1.0) * aspect,
        (1.0 - uv.y * 2.0),
    );

    // Slow orbit camera around the bulb with a slight tilt.
    let t = time * 0.18;
    let cam_radius = 2.6;
    let cam_height = 0.55 + 0.15 * sin(time * 0.21);
    let cx = cos(t) * cam_radius;
    let cz = sin(t) * cam_radius;
    let ro = vec3<f32>(cx, cam_height, cz);
    let look_at = vec3<f32>(0.0, 0.0, 0.0);

    // Build orthonormal camera basis (right, up, forward).
    let world_up = vec3<f32>(0.0, 1.0, 0.0);
    let fwd = normalize(look_at - ro);
    let right = normalize(cross(fwd, world_up));
    let up = cross(right, fwd);

    // Perspective ray (focal length ~1.4 -> moderately tight FOV).
    let focal = 1.4;
    let rd = normalize(right * p.x + up * p.y + fwd * focal);

    // Directional sun light.
    let light_dir = normalize(vec3<f32>(0.55, 0.75, -0.35));

    // Background: subtle space gradient + faint star/dust speckle.
    // Vertical gradient from deep indigo to near-black.
    let bg_top = vec3<f32>(0.015, 0.018, 0.045);
    let bg_bot = vec3<f32>(0.002, 0.004, 0.012);
    let bg_mix = clamp(0.5 + 0.5 * rd.y, 0.0, 1.0);
    var background = mix(bg_bot, bg_top, bg_mix);
    // Hash-based star speckle on the ray direction.
    let star_seed = floor(rd.xy * 280.0 + vec2<f32>(rd.z * 53.0, rd.z * 91.0));
    let star_h = fract(sin(dot(star_seed, vec2<f32>(127.1, 311.7))) * 43758.5453);
    let star_h2 = fract(sin(dot(star_seed, vec2<f32>(269.5, 183.3))) * 23421.631);
    let star_mask = step(0.997, star_h);
    let star_intensity = star_mask * pow(star_h2, 2.0) * 0.9;
    background = background + vec3<f32>(star_intensity);
    // Faint dust band.
    let dust = exp(-abs(rd.y + 0.05) * 6.0) * 0.04;
    background = background + vec3<f32>(dust * 0.6, dust * 0.5, dust * 1.0);

    // Raymarch the Mandelbulb DE.
    let max_steps: i32 = 96;
    let max_dist = 6.0;
    let mb_iters: i32 = 8;
    let bailout = 2.0;
    let power = 8.0;

    var total_dist = 0.0;
    var hit = false;
    var steps_used: i32 = 0;
    var orbit_trap = 1.0e9;

    for (var i: i32 = 0; i < max_steps; i = i + 1) {
        let pos = ro + rd * total_dist;

        // Inline Mandelbulb DE computation.
        var z = pos;
        var dr = 1.0;
        var r = 0.0;
        var local_trap = 1.0e9;
        for (var j: i32 = 0; j < mb_iters; j = j + 1) {
            r = length(z);
            if (r > bailout) {
                break;
            }
            // Track orbit trap as min |z| across iterations.
            local_trap = min(local_trap, r);

            // Convert to polar (clamp to avoid NaN in acos).
            let r_safe = max(r, 1e-4);
            let theta = acos(clamp(z.z / r_safe, -1.0, 1.0));
            let phi = atan2(z.y, z.x);

            // Running derivative for distance estimator.
            dr = pow(max(r, 1e-4), power - 1.0) * power * dr + 1.0;

            // Scale and rotate.
            let zr = pow(max(r, 1e-4), power);
            let theta_n = theta * power;
            let phi_n = phi * power;
            let sin_t = sin(theta_n);
            z = zr * vec3<f32>(
                sin_t * cos(phi_n),
                sin_t * sin(phi_n),
                cos(theta_n),
            );
            z = z + pos;
        }
        let r_final = max(length(z), 1e-4);
        // Distance estimator.
        var de = 0.5 * log(r_final) * r_final / max(dr, 1e-4);

        // Adaptive epsilon: tighten with distance traveled but keep small.
        let eps = max(0.0008, 0.0006 * total_dist);

        if (de < eps) {
            hit = true;
            orbit_trap = local_trap;
            steps_used = i;
            break;
        }

        total_dist = total_dist + de;
        if (total_dist > max_dist) {
            steps_used = i;
            break;
        }
    }

    var color = background;

    if (hit) {
        let hit_pos = ro + rd * total_dist;

        // Compute normal via 4-tap tetrahedral gradient of DE.
        let h = 0.0015;
        let k0 = vec3<f32>(1.0, -1.0, -1.0);
        let k1 = vec3<f32>(-1.0, -1.0, 1.0);
        let k2 = vec3<f32>(-1.0, 1.0, -1.0);
        let k3 = vec3<f32>(1.0, 1.0, 1.0);

        // Helper inline: evaluate DE at a point.
        // Sample 1
        var de0 = 0.0;
        {
            let pos = hit_pos + k0 * h;
            var z = pos;
            var dr = 1.0;
            var r = 0.0;
            for (var j: i32 = 0; j < mb_iters; j = j + 1) {
                r = length(z);
                if (r > bailout) { break; }
                let r_safe = max(r, 1e-4);
                let theta = acos(clamp(z.z / r_safe, -1.0, 1.0));
                let phi = atan2(z.y, z.x);
                dr = pow(max(r, 1e-4), power - 1.0) * power * dr + 1.0;
                let zr = pow(max(r, 1e-4), power);
                let st = sin(theta * power);
                z = zr * vec3<f32>(st * cos(phi * power), st * sin(phi * power), cos(theta * power)) + pos;
            }
            let rf = max(length(z), 1e-4);
            de0 = 0.5 * log(rf) * rf / max(dr, 1e-4);
        }
        var de1 = 0.0;
        {
            let pos = hit_pos + k1 * h;
            var z = pos;
            var dr = 1.0;
            var r = 0.0;
            for (var j: i32 = 0; j < mb_iters; j = j + 1) {
                r = length(z);
                if (r > bailout) { break; }
                let r_safe = max(r, 1e-4);
                let theta = acos(clamp(z.z / r_safe, -1.0, 1.0));
                let phi = atan2(z.y, z.x);
                dr = pow(max(r, 1e-4), power - 1.0) * power * dr + 1.0;
                let zr = pow(max(r, 1e-4), power);
                let st = sin(theta * power);
                z = zr * vec3<f32>(st * cos(phi * power), st * sin(phi * power), cos(theta * power)) + pos;
            }
            let rf = max(length(z), 1e-4);
            de1 = 0.5 * log(rf) * rf / max(dr, 1e-4);
        }
        var de2 = 0.0;
        {
            let pos = hit_pos + k2 * h;
            var z = pos;
            var dr = 1.0;
            var r = 0.0;
            for (var j: i32 = 0; j < mb_iters; j = j + 1) {
                r = length(z);
                if (r > bailout) { break; }
                let r_safe = max(r, 1e-4);
                let theta = acos(clamp(z.z / r_safe, -1.0, 1.0));
                let phi = atan2(z.y, z.x);
                dr = pow(max(r, 1e-4), power - 1.0) * power * dr + 1.0;
                let zr = pow(max(r, 1e-4), power);
                let st = sin(theta * power);
                z = zr * vec3<f32>(st * cos(phi * power), st * sin(phi * power), cos(theta * power)) + pos;
            }
            let rf = max(length(z), 1e-4);
            de2 = 0.5 * log(rf) * rf / max(dr, 1e-4);
        }
        var de3 = 0.0;
        {
            let pos = hit_pos + k3 * h;
            var z = pos;
            var dr = 1.0;
            var r = 0.0;
            for (var j: i32 = 0; j < mb_iters; j = j + 1) {
                r = length(z);
                if (r > bailout) { break; }
                let r_safe = max(r, 1e-4);
                let theta = acos(clamp(z.z / r_safe, -1.0, 1.0));
                let phi = atan2(z.y, z.x);
                dr = pow(max(r, 1e-4), power - 1.0) * power * dr + 1.0;
                let zr = pow(max(r, 1e-4), power);
                let st = sin(theta * power);
                z = zr * vec3<f32>(st * cos(phi * power), st * sin(phi * power), cos(theta * power)) + pos;
            }
            let rf = max(length(z), 1e-4);
            de3 = 0.5 * log(rf) * rf / max(dr, 1e-4);
        }
        let n_raw = k0 * de0 + k1 * de1 + k2 * de2 + k3 * de3;
        let normal = normalize(n_raw + vec3<f32>(1e-6, 0.0, 0.0));

        // Lambert diffuse.
        let n_dot_l = max(dot(normal, light_dir), 0.0);

        // Soft shadow: short march toward the light using DE.
        var shadow = 1.0;
        {
            var sh_t = 0.02;
            let sh_max = 1.2;
            let sh_steps: i32 = 16;
            let sk = 12.0;
            let shadow_origin = hit_pos + normal * 0.004;
            for (var s: i32 = 0; s < sh_steps; s = s + 1) {
                let sp = shadow_origin + light_dir * sh_t;
                var z = sp;
                var dr = 1.0;
                var r = 0.0;
                for (var j: i32 = 0; j < mb_iters; j = j + 1) {
                    r = length(z);
                    if (r > bailout) { break; }
                    let r_safe = max(r, 1e-4);
                    let theta = acos(clamp(z.z / r_safe, -1.0, 1.0));
                    let phi = atan2(z.y, z.x);
                    dr = pow(max(r, 1e-4), power - 1.0) * power * dr + 1.0;
                    let zr = pow(max(r, 1e-4), power);
                    let st = sin(theta * power);
                    z = zr * vec3<f32>(st * cos(phi * power), st * sin(phi * power), cos(theta * power)) + sp;
                }
                let rf = max(length(z), 1e-4);
                let de_s = 0.5 * log(rf) * rf / max(dr, 1e-4);
                shadow = min(shadow, sk * de_s / max(sh_t, 1e-4));
                if (de_s < 0.0008) {
                    shadow = 0.0;
                    break;
                }
                sh_t = sh_t + max(de_s, 0.01);
                if (sh_t > sh_max) {
                    break;
                }
            }
            shadow = clamp(shadow, 0.0, 1.0);
        }

        // Rim term: highlight grazing angles relative to the view.
        let view_dir = normalize(ro - hit_pos);
        let rim = pow(1.0 - max(dot(normal, view_dir), 0.0), 3.0);

        // Color from orbit trap: warm-to-cool palette, modulated by trap depth.
        let trap = clamp(orbit_trap, 0.0, 2.0);
        let palette_a = vec3<f32>(0.85, 0.45, 0.15);
        let palette_b = vec3<f32>(0.18, 0.42, 0.95);
        let palette_c = vec3<f32>(0.95, 0.85, 0.55);
        let mix1 = clamp(trap * 0.7, 0.0, 1.0);
        let surface_col = mix(palette_a, palette_b, mix1)
            + palette_c * 0.18 * pow(1.0 - mix1, 2.0);

        // Ambient occlusion proxy: more steps to converge -> deeper crevice.
        let ao = clamp(1.0 - f32(steps_used) / f32(max_steps) * 0.9, 0.05, 1.0);

        let ambient = vec3<f32>(0.06, 0.07, 0.11);
        let diffuse = surface_col * (n_dot_l * shadow * 1.05);
        let rim_col = vec3<f32>(0.55, 0.7, 1.0) * rim * 0.45;

        var lit = ambient * ao + diffuse + rim_col;

        // Distance fog blend toward background.
        let fog = 1.0 - exp(-total_dist * 0.18);
        lit = mix(lit, background, clamp(fog * 0.35, 0.0, 1.0));

        color = lit;
    }

    // Subtle vignette.
    let vc = uv - vec2<f32>(0.5);
    let vig = 1.0 - dot(vc, vc) * 0.6;
    color = color * clamp(vig, 0.0, 1.0);

    return clamp(color, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn shader_quad_kifs_temple(
    uv: vec2<f32>,
    resolution: vec2<f32>,
    time: f32,
) -> vec3<f32> {
    // Map uv [0,1] (top-left origin) to NDC-ish coords with aspect correction.
    let aspect = max(resolution.x, 1.0) / max(resolution.y, 1.0);
    var ndc = vec2<f32>(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    ndc.x = ndc.x * aspect;

    // Camera: slow forward dolly + subtle yaw bob.
    let t = time * 0.35;
    let yaw = sin(time * 0.18) * 0.18;
    let cam_pos = vec3<f32>(sin(t * 0.4) * 0.25, 0.05 + cos(t * 0.3) * 0.05, -3.2 + t * 0.55);
    let cam_target = cam_pos + vec3<f32>(sin(yaw), -0.05, cos(yaw));

    // Build camera basis.
    let world_up = vec3<f32>(0.0, 1.0, 0.0);
    let cam_fwd_raw = cam_target - cam_pos;
    let cam_fwd = cam_fwd_raw / max(length(cam_fwd_raw), 1e-4);
    let cam_right_raw = cross(cam_fwd, world_up);
    let cam_right = cam_right_raw / max(length(cam_right_raw), 1e-4);
    let cam_up = cross(cam_right, cam_fwd);

    // Primary ray.
    let focal = 1.25;
    let rd_raw = cam_right * ndc.x + cam_up * ndc.y + cam_fwd * focal;
    let rd = rd_raw / max(length(rd_raw), 1e-4);

    // Raymarch state.
    let max_steps: i32 = 96;
    let max_dist: f32 = 12.0;
    var total_dist: f32 = 0.0;
    var ray_pos = cam_pos;
    var hit: bool = false;
    var steps_taken: i32 = 0;
    var deepest_iter: f32 = 0.0;
    var orbit_trap: f32 = 1e9;

    for (var i: i32 = 0; i < max_steps; i = i + 1) {
        steps_taken = i;
        let p_world = cam_pos + rd * total_dist;

        // Inline KIFS distance estimator.
        var p = p_world;
        // Soft scene rotation so the temple drifts slowly.
        let ca = cos(time * 0.07);
        let sa = sin(time * 0.07);
        let pxz = vec2<f32>(p.x * ca - p.z * sa, p.x * sa + p.z * ca);
        p = vec3<f32>(pxz.x, p.y, pxz.y);

        let scale: f32 = 1.85;
        let offset = vec3<f32>(1.15, 1.55, 0.55);
        var scale_accum: f32 = 1.0;
        var iter_trap: f32 = 1e9;
        var de_iter: f32 = 0.0;

        let iters: i32 = 8;
        for (var k: i32 = 0; k < iters; k = k + 1) {
            // abs() folds across the principal planes.
            p = vec3<f32>(abs(p.x), abs(p.y), abs(p.z));

            // Plane reflection across n1 = (0,1,0).
            let n1 = vec3<f32>(0.0, 1.0, 0.0);
            let d1 = dot(p, n1);
            if (d1 < 0.0) {
                p = p - 2.0 * d1 * n1;
            }

            // Plane reflection across n2 = (0.7071, 0.7071, 0.0).
            let n2 = vec3<f32>(0.7071, 0.7071, 0.0);
            let d2 = dot(p, n2);
            if (d2 < 0.0) {
                p = p - 2.0 * d2 * n2;
            }

            // Plane reflection across n3 = (0.0, 0.7071, 0.7071) for richer temple structure.
            let n3 = vec3<f32>(0.0, 0.7071, 0.7071);
            let d3 = dot(p, n3);
            if (d3 < 0.0) {
                p = p - 2.0 * d3 * n3;
            }

            // Uniform scale + translate (the KIFS contraction).
            p = p * scale - offset * (scale - 1.0);
            scale_accum = scale_accum * scale;

            // Track orbit trap (closest approach to origin in folded space).
            let r2 = dot(p, p);
            if (r2 < iter_trap) {
                iter_trap = r2;
                de_iter = f32(k);
            }
        }

        // Final primitive: a small sphere in folded space.
        let radius: f32 = 1.1;
        let de = (length(p) - radius) / max(scale_accum, 1e-4);

        if (de < iter_trap) {
            // keep orbit trap as squared length already tracked
        }
        if (iter_trap < orbit_trap) {
            orbit_trap = iter_trap;
            deepest_iter = de_iter;
        }

        // Adaptive epsilon scales with travel distance to fight aliasing far out.
        let eps = max(0.0008 * (1.0 + total_dist * 0.5), 1e-4);

        if (de < eps) {
            ray_pos = p_world;
            hit = true;
            break;
        }

        total_dist = total_dist + max(de, eps * 0.5);
        if (total_dist > max_dist) {
            break;
        }
    }

    // Background / fog color (cool dusky cathedral interior).
    let sky_lo = vec3<f32>(0.04, 0.05, 0.09);
    let sky_hi = vec3<f32>(0.22, 0.18, 0.28);
    let sky_t = clamp(0.5 + 0.5 * rd.y, 0.0, 1.0);
    let bg = mix(sky_lo, sky_hi, sky_t);

    if (!hit) {
        return clamp(bg, vec3<f32>(0.0), vec3<f32>(1.0));
    }

    // Normal via 4-tap tetrahedral gradient.
    let h: f32 = max(0.0015 * (1.0 + total_dist * 0.4), 1e-4);

    // Helper-less: re-evaluate DE inline four times.
    // Sample 1: e1 = (1, -1, -1)
    let e1 = vec3<f32>(1.0, -1.0, -1.0);
    let e2 = vec3<f32>(-1.0, -1.0, 1.0);
    let e3 = vec3<f32>(-1.0, 1.0, -1.0);
    let e4 = vec3<f32>(1.0, 1.0, 1.0);

    var de_samples = vec4<f32>(0.0);

    for (var s: i32 = 0; s < 4; s = s + 1) {
        var sp = ray_pos;
        if (s == 0) { sp = sp + e1 * h; }
        else if (s == 1) { sp = sp + e2 * h; }
        else if (s == 2) { sp = sp + e3 * h; }
        else { sp = sp + e4 * h; }

        // Same scene rotation as DE.
        let ca = cos(time * 0.07);
        let sa = sin(time * 0.07);
        let pxz = vec2<f32>(sp.x * ca - sp.z * sa, sp.x * sa + sp.z * ca);
        var p = vec3<f32>(pxz.x, sp.y, pxz.y);

        let scale: f32 = 1.85;
        let offset = vec3<f32>(1.15, 1.55, 0.55);
        var scale_accum: f32 = 1.0;

        let iters: i32 = 8;
        for (var k: i32 = 0; k < iters; k = k + 1) {
            p = vec3<f32>(abs(p.x), abs(p.y), abs(p.z));
            let n1 = vec3<f32>(0.0, 1.0, 0.0);
            let d1 = dot(p, n1);
            if (d1 < 0.0) { p = p - 2.0 * d1 * n1; }
            let n2 = vec3<f32>(0.7071, 0.7071, 0.0);
            let d2 = dot(p, n2);
            if (d2 < 0.0) { p = p - 2.0 * d2 * n2; }
            let n3 = vec3<f32>(0.0, 0.7071, 0.7071);
            let d3 = dot(p, n3);
            if (d3 < 0.0) { p = p - 2.0 * d3 * n3; }
            p = p * scale - offset * (scale - 1.0);
            scale_accum = scale_accum * scale;
        }
        let radius: f32 = 1.1;
        let de = (length(p) - radius) / max(scale_accum, 1e-4);

        if (s == 0) { de_samples.x = de; }
        else if (s == 1) { de_samples.y = de; }
        else if (s == 2) { de_samples.z = de; }
        else { de_samples.w = de; }
    }

    let n_raw = e1 * de_samples.x + e2 * de_samples.y + e3 * de_samples.z + e4 * de_samples.w;
    let n_len = max(length(n_raw), 1e-4);
    let normal = n_raw / n_len;

    // Shading.
    let key_dir_raw = vec3<f32>(0.45, 0.85, -0.25);
    let key_dir = key_dir_raw / max(length(key_dir_raw), 1e-4);
    let fill_dir_raw = vec3<f32>(-0.5, 0.3, 0.6);
    let fill_dir = fill_dir_raw / max(length(fill_dir_raw), 1e-4);

    let key = max(dot(normal, key_dir), 0.0);
    let fill = max(dot(normal, fill_dir), 0.0);
    let ambient: f32 = 0.18;

    // Cheap AO from raymarch step count.
    let ao = 1.0 - clamp(f32(steps_taken) / f32(max_steps), 0.0, 1.0);
    let ao_curve = pow(clamp(ao, 0.0, 1.0), 1.4);

    // Color from orbit trap + iteration index, mixing two rich palettes.
    let trap_norm = clamp(sqrt(max(orbit_trap, 0.0)) * 0.5, 0.0, 1.0);
    let iter_norm = clamp(deepest_iter / 8.0, 0.0, 1.0);

    // Palette A: warm gilded sandstone.
    let pal_a_lo = vec3<f32>(0.18, 0.07, 0.04);
    let pal_a_hi = vec3<f32>(1.00, 0.78, 0.42);
    let pal_a = mix(pal_a_lo, pal_a_hi, iter_norm);

    // Palette B: cold cathedral teal/violet.
    let pal_b_lo = vec3<f32>(0.05, 0.10, 0.18);
    let pal_b_hi = vec3<f32>(0.55, 0.40, 0.95);
    let pal_b = mix(pal_b_lo, pal_b_hi, trap_norm);

    let palette_blend = clamp(0.5 + 0.5 * sin(time * 0.2 + iter_norm * 3.14159), 0.0, 1.0);
    let surface_color = mix(pal_a, pal_b, palette_blend);

    let key_color = vec3<f32>(1.0, 0.92, 0.78);
    let fill_color = vec3<f32>(0.35, 0.55, 0.95);

    var lit = surface_color * (ambient + key * 0.95) * ao_curve
        + surface_color * fill_color * fill * 0.35 * ao_curve
        + key_color * pow(max(key, 0.0), 8.0) * 0.15;

    // Rim light along grazing angles for that gilded edge feel.
    let view = -rd;
    let rim = pow(clamp(1.0 - max(dot(normal, view), 0.0), 0.0, 1.0), 3.0);
    lit = lit + vec3<f32>(0.8, 0.55, 0.25) * rim * 0.25 * ao_curve;

    // Atmospheric fog with depth falloff.
    let fog_t = 1.0 - exp(-max(total_dist, 0.0) * 0.18);
    let fog_color = mix(bg, vec3<f32>(0.10, 0.08, 0.14), 0.4);
    lit = mix(lit, fog_color, clamp(fog_t, 0.0, 1.0));

    return clamp(lit, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn shader_quad_tunnel_warp(
    uv: vec2<f32>,
    resolution: vec2<f32>,
    time: f32,
) -> vec3<f32> {
    // Centered, aspect-corrected screen coordinate. y up.
    let aspect = max(resolution.x, 1.0) / max(resolution.y, 1.0);
    var p = vec2<f32>((uv.x - 0.5) * 2.0 * aspect, (0.5 - uv.y) * 2.0);

    // Gentle camera roll.
    let roll = sin(time * 0.35) * 0.25 + time * 0.08;
    let cr = cos(roll);
    let sr = sin(roll);
    p = vec2<f32>(p.x * cr - p.y * sr, p.x * sr + p.y * cr);

    // Polar coordinates of the rotated XY plane.
    let r2d = max(length(p), 1e-4);
    let a = atan2(p.y, p.x);

    // Closed-form tunnel: walls at fixed radius, depth z = 1 / r2d.
    // Larger r2d (toward edge) -> smaller z (close); smaller r2d (center) -> large z (far).
    let z = 1.0 / r2d;

    // Travel speed along -Z plus twist that depends on z and time.
    let travel = time * 1.6;
    let twist = z * 0.4 + time * 0.6;
    var theta = a + twist;

    // Wrap theta into [-pi, pi] for stable striping.
    let two_pi = 6.2831853;
    theta = theta - floor((theta + 3.1415927) / two_pi) * two_pi;

    // Tunnel "panel" coordinate along length. 8 panels around, smooth walls along z.
    let panels = 8.0;
    let u_wall = theta * (panels / two_pi); // ~ -4..4
    let v_wall = z + travel;

    // Subtle radial wall undulation (used for shading & stripe phase).
    let wall_wave = sin(v_wall * 0.7 + theta * 3.0) * 0.5 + sin(theta * 4.0 - v_wall * 0.4) * 0.5;

    // ---------- Panel grid ----------
    // Distance to nearest panel seam (in u) and nearest depth ring (in v).
    let u_seam = abs(fract(u_wall) - 0.5) * 2.0;       // 0 at seam, 1 at panel center
    let v_seam = abs(fract(v_wall * 0.5) - 0.5) * 2.0; // depth rings every 2 units of v
    let seam_u_glow = pow(1.0 - clamp(u_seam, 0.0, 1.0), 12.0);
    let seam_v_glow = pow(1.0 - clamp(v_seam, 0.0, 1.0), 16.0);

    // ---------- Neon stripes ----------
    // Multiple stripe families along z, modulated by theta.
    let s1 = sin(v_wall * 3.2 + theta * 2.0 + wall_wave * 0.6);
    let s2 = sin(v_wall * 1.7 - theta * 1.3 + time * 1.2);
    let s3 = sin(v_wall * 6.4 + theta * 5.0 - time * 0.8);
    let stripe_a = pow(clamp(s1, 0.0, 1.0), 18.0);
    let stripe_b = pow(clamp(s2, 0.0, 1.0), 10.0);
    let stripe_c = pow(clamp(s3, 0.0, 1.0), 24.0);

    // ---------- Sparkles ----------
    // Pseudo-random highlights keyed off panel cell.
    let cell = vec2<f32>(floor(u_wall), floor(v_wall * 0.5));
    let rand = fract(sin(dot(cell, vec2<f32>(127.1, 311.7))) * 43758.547);
    let twinkle = 0.5 + 0.5 * sin(time * (3.0 + rand * 5.0) + rand * 17.0);
    let in_cell_u = fract(u_wall) - 0.5;
    let in_cell_v = fract(v_wall * 0.5) - 0.5;
    let cell_d = length(vec2<f32>(in_cell_u, in_cell_v));
    let sparkle_mask = step(0.85, rand) * twinkle;
    let sparkle = exp(-cell_d * 28.0) * sparkle_mask;

    // ---------- Color palette (synthwave) ----------
    let c_magenta = vec3<f32>(1.0, 0.18, 0.75);
    let c_cyan = vec3<f32>(0.20, 0.95, 1.0);
    let c_violet = vec3<f32>(0.55, 0.25, 1.0);
    let c_amber = vec3<f32>(1.0, 0.65, 0.25);

    // Hue varies along the tunnel length and around theta.
    let hue_mix = 0.5 + 0.5 * sin(v_wall * 0.25 + theta * 0.6 + time * 0.3);
    let base_neon = mix(c_magenta, c_cyan, hue_mix);
    let accent_neon = mix(c_violet, c_amber, 0.5 + 0.5 * sin(v_wall * 0.4 - time * 0.4));

    // ---------- Wall shading ----------
    // Darker base with subtle panel shading via wall_wave.
    let wall_shade = 0.04 + 0.10 * (0.5 + 0.5 * wall_wave);
    var color = vec3<f32>(0.02, 0.015, 0.04) + vec3<f32>(wall_shade) * vec3<f32>(0.5, 0.4, 0.7);

    // Add seam glow (panel edges) and stripes.
    color = color + base_neon * (seam_u_glow * 0.9 + stripe_a * 1.2);
    color = color + accent_neon * (seam_v_glow * 0.7 + stripe_b * 0.6);
    color = color + c_cyan * stripe_c * 1.0;

    // Specular along stripes: extra punch where two stripe families overlap.
    let spec = stripe_a * stripe_c;
    color = color + vec3<f32>(1.0, 0.95, 1.0) * spec * 0.8;

    // Sparkles (additive).
    color = color + vec3<f32>(1.0, 0.9, 1.0) * sparkle * 1.4;

    // ---------- Depth fog ----------
    // Distant (large z) fades to dark teal/magenta haze.
    let fog_t = clamp(z / 18.0, 0.0, 1.0);
    let fog_color = mix(vec3<f32>(0.04, 0.10, 0.12), vec3<f32>(0.10, 0.02, 0.10), 0.5 + 0.5 * sin(time * 0.2));
    color = mix(color, fog_color, fog_t);

    // Vignette toward the very center (the "vanishing point") to hide singularity.
    let vignette = smoothstep(0.0, 0.18, r2d);
    color = color * vignette;

    // Slight outer glow boost near edges (close walls).
    let near_boost = smoothstep(0.6, 1.6, r2d);
    color = color + base_neon * near_boost * 0.08;

    return clamp(color, vec3<f32>(0.0), vec3<f32>(1.0));
}

// ---- Second wave of extreme built-ins. ------------------------------------
// Same contract as the first wave: `uv` in [0, 1] (origin top-left),
// `resolution` in pixels, `time` from the shared shadertoy-style global.
// Returns linear RGB in [0, 1]^3. Stubbed bodies are filled in by parallel
// authors; each function owns its own body and inlines all helpers.

fn shader_quad_black_hole(
    uv: vec2<f32>,
    resolution: vec2<f32>,
    time: f32,
) -> vec3<f32> {
    // Aspect-corrected screen coords centered on the BH. Flip Y so positive
    // is up; uv comes in top-left origin.
    let aspect = max(resolution.x, 1.0) / max(resolution.y, 1.0);
    var screen = vec2<f32>(
        (uv.x - 0.5) * 2.0 * aspect,
        (0.5 - uv.y) * 2.0,
    );

    // Subtle camera dolly + slow drift so the field feels alive.
    let dolly = 1.0 + 0.06 * sin(time * 0.17);
    screen = screen * dolly;
    let drift = vec2<f32>(0.04 * sin(time * 0.11), 0.03 * cos(time * 0.09));
    screen = screen - drift;

    // Schwarzschild radius in screen units. Photon sphere at ~1.5 R_s.
    let r_s = 0.34;
    let photon_r = r_s * 1.5;

    // --- Iterative 2D gravitational deflection of the view direction ---
    // We treat `screen` as the impact-parameter vector; integrate small
    // angular bends toward the center to warp the apparent sky direction.
    var dir = screen;
    let steps = 14;
    let dt_step = 0.045;
    for (var i: i32 = 0; i < steps; i = i + 1) {
        let b = max(length(dir), 1e-3);
        // Deflection angle ~ R_s / b per step. Pull direction radially inward
        // by an amount that scales like R_s^2 / b so far rays bend much less.
        let bend = (r_s * r_s / max(b * b, r_s * r_s * 0.25)) * dt_step;
        let inward = -normalize(dir) * bend;
        dir = dir + inward;
    }

    let r = length(screen);
    var color = vec3<f32>(0.0);

    // --- Procedural starfield in the deflected direction ---
    // Slight chromatic offset gives stars a parallax-arc tint near the edge.
    let chroma = clamp((photon_r / max(r, 1e-3)) * 0.015, 0.0, 0.05);
    let dir_n = normalize(vec2<f32>(dir.x, dir.y) + vec2<f32>(1e-5, 0.0));
    let star_dir_r = dir + dir_n * chroma;
    let star_dir_g = dir;
    let star_dir_b = dir - dir_n * chroma;

    // Sample stars via integer-grid hashing of a polar-ish projection of the
    // deflected direction. Project onto a virtual sky plane.
    let sky_scale = 22.0;
    let star_uv_r = star_dir_r * sky_scale + vec2<f32>(13.7, 4.1);
    let star_uv_g = star_dir_g * sky_scale + vec2<f32>(13.7, 4.1);
    let star_uv_b = star_dir_b * sky_scale + vec2<f32>(13.7, 4.1);

    // Inline a small starfield evaluator: for each channel, hash a 3x3
    // neighborhood and accumulate a bright spike where a star sits.
    var star_rgb = vec3<f32>(0.0);
    for (var ci: i32 = 0; ci < 3; ci = ci + 1) {
        var s_uv = star_uv_g;
        if (ci == 0) { s_uv = star_uv_r; }
        if (ci == 2) { s_uv = star_uv_b; }
        let cell = floor(s_uv);
        let frac_uv = s_uv - cell;
        var acc_star = 0.0;
        for (var jy: i32 = -1; jy <= 1; jy = jy + 1) {
            for (var jx: i32 = -1; jx <= 1; jx = jx + 1) {
                let off = vec2<f32>(f32(jx), f32(jy));
                let cell_id = cell + off;
                // Inline hash.
                let h1 = fract(sin(dot(cell_id, vec2<f32>(127.1, 311.7))) * 43758.5453);
                let h2 = fract(sin(dot(cell_id, vec2<f32>(269.5, 183.3))) * 23421.6312);
                let h3 = fract(sin(dot(cell_id, vec2<f32>(419.2, 371.9))) * 18947.1357);
                // Star density: only some cells have stars.
                let present = step(0.86, h3);
                let pos = off + vec2<f32>(h1, h2);
                let d = length(frac_uv - pos);
                let star_size = 0.012 + 0.025 * h1;
                let bright = pow(clamp(1.0 - d / max(star_size, 1e-3), 0.0, 1.0), 6.0);
                // Twinkle.
                let tw = 0.7 + 0.3 * sin(time * (1.5 + 4.0 * h2) + h1 * 12.0);
                acc_star = acc_star + present * bright * tw;
            }
        }
        if (ci == 0) { star_rgb.x = acc_star; }
        if (ci == 1) { star_rgb.y = acc_star; }
        if (ci == 2) { star_rgb.z = acc_star; }
    }
    // Cool slightly bluish star tint baseline.
    color = color + star_rgb * vec3<f32>(0.95, 0.97, 1.05);

    // Soft nebula background derived from the deflected direction so it warps
    // around the lens. Layered sin acts as cheap FBM.
    var neb = 0.0;
    var amp = 0.5;
    var p_neb = dir * 1.7;
    for (var oct: i32 = 0; oct < 4; oct = oct + 1) {
        neb = neb + amp * (0.5 + 0.5 * sin(p_neb.x * 3.1 + sin(p_neb.y * 2.3 + time * 0.05)));
        p_neb = p_neb * 1.9 + vec2<f32>(1.3, -0.7);
        amp = amp * 0.55;
    }
    let neb_col = mix(
        vec3<f32>(0.02, 0.01, 0.05),
        vec3<f32>(0.15, 0.05, 0.22),
        clamp(neb, 0.0, 1.0),
    );
    color = color + neb_col * 0.55;

    // --- Accretion disk ---
    // Disk lies in a plane tilted toward the camera. Approximate with an
    // oblate ellipse in screen space: squash Y to simulate near-edge-on view.
    let tilt_y = 0.34; // squash factor: smaller = more edge-on.
    let disk_xy = vec2<f32>(screen.x, screen.y / max(tilt_y, 1e-3));
    let disk_r = length(disk_xy);
    let disk_inner = r_s * 1.55;
    let disk_outer = r_s * 3.6;

    // Radial profile: bright near inner edge, fades outward.
    let radial_mask = smoothstep(disk_inner, disk_inner * 1.05, disk_r) *
                      (1.0 - smoothstep(disk_outer * 0.7, disk_outer, disk_r));

    // Thin vertical thickness of the disk (in true screen Y, before squash).
    let disk_thickness = 0.05 + 0.04 * (disk_r / max(disk_outer, 1e-3));
    let vy_norm = screen.y / max(disk_thickness * tilt_y, 1e-3);
    let vertical_mask = exp(-(vy_norm * vy_norm));

    // Polar coordinates in disk plane, with rotation over time.
    let rot_speed = 0.6;
    let phi = atan2(disk_xy.y, disk_xy.x) + time * rot_speed * (1.0 / max(disk_r, 0.15));
    // Swirling brightness: layered sin "FBM".
    var swirl = 0.0;
    var samp_amp = 0.6;
    var samp_p = vec2<f32>(phi * 3.0, log(max(disk_r, 1e-3)) * 5.0);
    for (var oct2: i32 = 0; oct2 < 5; oct2 = oct2 + 1) {
        swirl = swirl + samp_amp * sin(samp_p.x + sin(samp_p.y) * 1.3);
        samp_p = samp_p * 1.8 + vec2<f32>(0.7, 1.1);
        samp_amp = samp_amp * 0.55;
    }
    swirl = 0.5 + 0.5 * swirl;

    // Doppler shift: side moving toward us (let's say +x) is bluer & brighter,
    // -x is redder & dimmer. Disk rotation direction: tangent at angle phi has
    // x-component -sin(phi), so an approaching-side proxy is -sin(phi).
    let approach = -sin(atan2(disk_xy.y, disk_xy.x));
    let doppler = clamp(approach, -1.0, 1.0);
    let blue_side = vec3<f32>(0.55, 0.85, 1.4);
    let red_side = vec3<f32>(1.4, 0.45, 0.15);
    let neutral = vec3<f32>(1.2, 0.75, 0.35);
    var disk_color = neutral;
    if (doppler > 0.0) {
        disk_color = mix(neutral, blue_side, doppler);
    } else {
        disk_color = mix(neutral, red_side, -doppler);
    }
    let doppler_gain = 1.0 + 0.9 * doppler;

    // Inner-edge blow-out: extra heat near the ISCO.
    let inner_norm = (disk_r - disk_inner) / max(disk_inner * 0.35, 1e-3);
    let inner_glow = exp(-(inner_norm * inner_norm));

    let disk_intensity = radial_mask * vertical_mask * (0.55 + 0.9 * swirl) * doppler_gain;
    color = color + disk_color * disk_intensity * 1.6;
    color = color + vec3<f32>(1.6, 1.3, 0.9) * inner_glow * radial_mask * vertical_mask * 0.7;

    // --- Photon sphere ring: thin bright ring just outside the horizon ---
    let ring_d = (r - photon_r) / 0.012;
    let ring = exp(-(ring_d * ring_d));
    color = color + vec3<f32>(1.4, 1.2, 0.95) * ring * 1.4;

    // Secondary lensed image of the disk: a faint arc at ~photon_r.
    let arc_d = (r - photon_r * 1.08) / 0.025;
    let arc = exp(-(arc_d * arc_d));
    color = color + disk_color * arc * 0.45;

    // --- Event horizon: pure black inside R_s with a soft edge ---
    let horizon = smoothstep(r_s * 0.985, r_s * 1.02, r);
    color = color * horizon;

    // Slight gravitational redshift halo just above horizon.
    let halo_d = (r - r_s * 1.1) / 0.05;
    let halo = exp(-(halo_d * halo_d));
    color = color + vec3<f32>(0.45, 0.18, 0.08) * halo * 0.25 * horizon;

    // Tonemap (Reinhard) and gentle gamma.
    color = color / (vec3<f32>(1.0) + color);
    color = pow(max(color, vec3<f32>(0.0)), vec3<f32>(1.0 / 1.15));

    return clamp(color, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn shader_quad_hyperspace_jump(
    uv: vec2<f32>,
    resolution: vec2<f32>,
    time: f32,
) -> vec3<f32> {
    // Aspect-correct coords centered around a slightly drifting focus point.
    let aspect = resolution.x / max(resolution.y, 1e-4);
    let drift = vec2<f32>(
        sin(time * 0.37) * 0.04 + cos(time * 0.21) * 0.02,
        cos(time * 0.29) * 0.035 + sin(time * 0.47) * 0.018,
    );
    let centered = (uv - vec2<f32>(0.5, 0.5) - drift) * vec2<f32>(aspect, 1.0);
    let radius = max(length(centered), 1e-4);
    let angle = atan2(centered.y, centered.x);

    var color = vec3<f32>(0.0);

    // Hot core bloom: bright white-blue gaussian-ish falloff from the focus.
    let core_falloff = exp(-radius * radius * 14.0);
    let core_tight = exp(-radius * radius * 90.0);
    let core_color = vec3<f32>(0.55, 0.78, 1.05) * core_falloff * 0.9
        + vec3<f32>(1.1, 1.05, 0.95) * core_tight * 1.6;
    color = color + core_color;

    // Streaming starfield: discrete angular bins, hashed per star.
    let star_count = 28;
    let bin_count = f32(star_count);
    let two_pi = 6.2831853;
    var star_index = 0;
    loop {
        if (star_index >= star_count) { break; }
        let fi = f32(star_index);

        // Hash this star's angular jitter & layer offset.
        let h_seed = fi * 12.9898 + 7.13;
        let h_a = fract(sin(h_seed) * 43758.5453);
        let h_b = fract(sin(h_seed * 1.7 + 3.1) * 22578.1459);
        let h_c = fract(sin(h_seed * 0.53 + 9.7) * 9182.331);
        let h_d = fract(sin(h_seed * 2.31 + 1.7) * 51237.713);

        // Angle around the focus with jitter so streaks don't form perfect spokes.
        let bin_angle = (fi + h_a * 0.85 - 0.42) * (two_pi / bin_count);
        let speed = 0.55 + h_b * 0.95;
        // Star "head" radius advected with time, looping outward.
        let phase = fract(h_c + time * speed * 0.45);
        let head = phase * 1.35;

        // Per-pixel angular distance from this star's spoke (wrapped).
        var dtheta = angle - bin_angle;
        dtheta = dtheta - two_pi * floor((dtheta + 3.14159265) / two_pi);
        let lateral = abs(dtheta) * radius;

        // Streak: bright at head, fading toward the focus (motion blur trail).
        let along = head - radius;
        // Trail length scales with star speed.
        let trail_len = 0.18 + h_d * 0.35;
        // Only stars whose head is ahead of this pixel contribute a trail behind them.
        let trail_t = clamp(along / max(trail_len, 1e-4), 0.0, 1.0);
        let trail = pow(1.0 - trail_t, 2.4) * step(0.0, along) * step(radius, 1.5);

        // Lateral falloff narrows further from focus to look like long thin streaks.
        let thickness = 0.0028 + 0.012 / max(radius * 5.0 + 0.6, 1e-3);
        let lateral_falloff = exp(-(lateral * lateral) / max(thickness * thickness, 1e-6));

        // Chromatic aberration: sample R/G/B at slightly different effective radii
        // by offsetting "along" so the streak fringes red on the trailing side and
        // blue on the leading side.
        let ca = 0.045 + h_b * 0.025;
        let along_r = clamp((along + ca * trail_len) / max(trail_len, 1e-4), 0.0, 1.0);
        let along_b = clamp((along - ca * trail_len) / max(trail_len, 1e-4), 0.0, 1.0);
        let trail_r = pow(1.0 - along_r, 2.4) * step(-ca * trail_len, along) * step(radius, 1.5);
        let trail_b = pow(1.0 - along_b, 2.4) * step(ca * trail_len, along) * step(radius, 1.5);

        // Star color: warm white with tinted fringes.
        let bright = (0.55 + h_a * 0.7) * lateral_falloff;
        // Boost head: a hot dot at the leading edge.
        let head_dot = exp(-((along) * (along)) / max(0.0009 + h_d * 0.0015, 1e-6))
            * exp(-(lateral * lateral) / max(0.00045, 1e-6));

        color.r = color.r + bright * (trail_r * 1.05 + head_dot * 1.4);
        color.g = color.g + bright * (trail   * 1.00 + head_dot * 1.5);
        color.b = color.b + bright * (trail_b * 1.20 + head_dot * 1.7);

        star_index = star_index + 1;
    }

    // Shockwave rings: up to 4 expanding rings on a ~1.2s cadence.
    let ring_period = 1.2;
    let ring_count = 4;
    var ring_index = 0;
    loop {
        if (ring_index >= ring_count) { break; }
        let fi = f32(ring_index);
        // Stagger ring births so several are alive concurrently.
        let ring_phase = fract((time + fi * 0.31) / ring_period);
        let ring_age = ring_phase * ring_period;
        // Ring radius grows quickly then slows.
        let ring_r = pow(ring_age / ring_period, 0.65) * 1.4;
        // Sharp rim, soft falloff outside.
        let rim = exp(-pow((radius - ring_r) * 22.0, 2.0));
        // Fade rings as they age and travel outward.
        let life = 1.0 - ring_phase;
        let dist_atten = exp(-radius * 1.2);
        let ring_color = vec3<f32>(0.45, 0.7, 1.15) * rim * life * dist_atten * 0.55;
        color = color + ring_color;
        ring_index = ring_index + 1;
    }

    // Subtle radial streaks of "warp soup" between stars to fill the gaps.
    let soup_seed = angle * 9.0 + radius * 2.5 - time * 1.7;
    let soup = fract(sin(soup_seed * 1.3 + 4.1) * 41231.7);
    let soup_band = pow(soup, 18.0) * exp(-radius * 0.8) * 0.35;
    color = color + vec3<f32>(0.6, 0.75, 1.0) * soup_band;

    // Vignette / dark halo.
    let vignette = exp(-pow(radius * 1.05, 2.6) * 0.9);
    color = color * (0.35 + 0.65 * vignette);

    // Slight cool ambient so darks aren't pure black.
    color = color + vec3<f32>(0.01, 0.015, 0.025);

    // Additive tonemap so streaks roll off nicely.
    let mapped = vec3<f32>(
        1.0 - exp(-max(color.r, 0.0) * 1.15),
        1.0 - exp(-max(color.g, 0.0) * 1.15),
        1.0 - exp(-max(color.b, 0.0) * 1.15),
    );

    return clamp(mapped, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn shader_quad_ferrofluid(
    uv: vec2<f32>,
    resolution: vec2<f32>,
    time: f32,
) -> vec3<f32> {
    // Map uv (origin top-left) to NDC with correct aspect, y-up.
    let aspect = max(resolution.x, 1.0) / max(resolution.y, 1.0);
    let p = vec2<f32>(
        (uv.x * 2.0 - 1.0) * aspect,
        (1.0 - uv.y * 2.0),
    );

    // Slow orbit camera around the blob with subtle bob.
    let orbit_t = time * 0.22;
    let cam_radius = 3.2;
    let cam_height = 0.45 + 0.18 * sin(time * 0.31);
    let eye = vec3<f32>(cos(orbit_t) * cam_radius, cam_height, sin(orbit_t) * cam_radius);
    let look_at = vec3<f32>(0.0, 0.0, 0.0);

    // Camera basis.
    let world_up = vec3<f32>(0.0, 1.0, 0.0);
    let fwd = normalize(look_at - eye);
    let right = normalize(cross(fwd, world_up));
    let up_axis = cross(right, fwd);

    // Perspective ray.
    let focal = 1.5;
    let rd = normalize(right * p.x + up_axis * p.y + fwd * focal);

    // Key directional light.
    let key_light = normalize(vec3<f32>(0.55, 0.85, -0.25));

    // Pulse drives spike length: reaches outward then retracts.
    let pulse = 0.5 + 0.5 * sin(time * 1.1);
    let pulse_b = 0.5 + 0.5 * sin(time * 0.73 + 1.7);

    // Eight spike directions distributed around a tilted set of axes.
    // Stored inline; index drives direction and per-spike phase.
    let spike_count: i32 = 8;
    let pi = 3.14159265;

    // Raymarch.
    let max_steps: i32 = 96;
    let max_dist = 6.0;

    var total_dist = 0.0;
    var hit = false;
    var steps_used: i32 = 0;

    for (var i: i32 = 0; i < max_steps; i = i + 1) {
        let pos = eye + rd * total_dist;

        // Inline distance estimator: smooth-min union of central sphere
        // with capsule spikes whose lengths animate over time.
        var d = length(pos) - 0.78;

        // Subtle wobble on the core via low-frequency noise-ish trig.
        let wobble = 0.05 * sin(pos.x * 3.1 + time * 1.3)
                   * cos(pos.y * 2.7 - time * 1.1)
                   * sin(pos.z * 3.3 + time * 0.9);
        d = d + wobble;

        // Iterate spikes.
        for (var k: i32 = 0; k < spike_count; k = k + 1) {
            let kf = f32(k);
            // Distribute on a sphere via fibonacci-ish mapping.
            let phi = kf * 2.39996323;
            let cos_th = 1.0 - 2.0 * (kf + 0.5) / f32(spike_count);
            let sin_th = sqrt(max(1.0 - cos_th * cos_th, 0.0));
            var dirs = vec3<f32>(cos(phi) * sin_th, cos_th, sin(phi) * sin_th);
            // Slow rotation of the spike rig over time.
            let rot = time * 0.35 + kf * 0.21;
            let cr = cos(rot);
            let sr = sin(rot);
            let dx = dirs.x * cr - dirs.z * sr;
            let dz = dirs.x * sr + dirs.z * cr;
            dirs = normalize(vec3<f32>(dx, dirs.y, dz));

            // Per-spike length pulse.
            let phase = kf * 0.9;
            let len_pulse = 0.5 + 0.5 * sin(time * 1.4 + phase);
            let spike_len = mix(0.05, 1.05, len_pulse * pulse + 0.15 * pulse_b);
            let spike_rad = mix(0.32, 0.16, len_pulse);

            // Capsule from origin along dirs of length spike_len, radius spike_rad.
            let h_t = clamp(dot(pos, dirs) / max(spike_len, 1e-4), 0.0, 1.0);
            let on_axis = dirs * (h_t * spike_len);
            let spike_d = length(pos - on_axis) - spike_rad;

            // Smooth-min union.
            let kk = 0.32;
            let hh = clamp(0.5 + 0.5 * (spike_d - d) / kk, 0.0, 1.0);
            d = mix(spike_d, d, hh) - kk * hh * (1.0 - hh);
        }

        // Tiny drifting metaball for organic surface motion.
        let mb_pos = vec3<f32>(
            0.65 * sin(time * 0.8),
            0.55 * cos(time * 0.6 + 0.4),
            0.65 * sin(time * 0.7 + 1.2),
        );
        let mb_d = length(pos - mb_pos) - 0.22;
        let kkb = 0.28;
        let hhb = clamp(0.5 + 0.5 * (mb_d - d) / kkb, 0.0, 1.0);
        d = mix(mb_d, d, hhb) - kkb * hhb * (1.0 - hhb);

        // Adaptive epsilon.
        let eps = max(0.0009, 0.0010 * total_dist);
        if (d < eps) {
            hit = true;
            steps_used = i;
            break;
        }

        total_dist = total_dist + max(d * 0.85, eps * 0.5);
        if (total_dist > max_dist) {
            steps_used = i;
            break;
        }
    }

    // Inline procedural sky for both miss and reflection. Computed in a
    // small block so we can reuse it after hit detection too.
    // Miss color.
    var bg = vec3<f32>(0.0);
    {
        let dir_y = clamp(rd.y, -1.0, 1.0);
        let horizon = exp(-abs(dir_y) * 3.2);
        let sky_top = vec3<f32>(0.04, 0.07, 0.14);
        let sky_mid = vec3<f32>(0.32, 0.34, 0.45);
        let sky_ground = vec3<f32>(0.05, 0.04, 0.03);
        let up_mix = clamp(0.5 + 0.5 * dir_y, 0.0, 1.0);
        var sky_col = mix(sky_ground, sky_mid, smoothstep(0.0, 0.5, up_mix));
        sky_col = mix(sky_col, sky_top, smoothstep(0.4, 1.0, up_mix));
        sky_col = sky_col + vec3<f32>(1.2, 0.8, 0.55) * horizon * 0.18;
        // Sun disk + glow.
        let sun_dot = clamp(dot(rd, key_light), -1.0, 1.0);
        let sun_glow = pow(max(sun_dot, 0.0), 8.0) * 0.6;
        let sun_disk = smoothstep(0.9985, 0.9995, sun_dot) * 6.0;
        sky_col = sky_col + vec3<f32>(1.5, 1.15, 0.75) * (sun_glow + sun_disk);
        bg = sky_col;
    }

    var color = bg;

    if (hit) {
        let hit_pos = eye + rd * total_dist;

        // 4-tap tetrahedral normal via DE. Inline DE is repeated; this is
        // unavoidable given the no-helper-fn constraint.
        let nh = 0.0018;
        let k0 = vec3<f32>(1.0, -1.0, -1.0);
        let k1 = vec3<f32>(-1.0, -1.0, 1.0);
        let k2 = vec3<f32>(-1.0, 1.0, -1.0);
        let k3 = vec3<f32>(1.0, 1.0, 1.0);

        var de_samples = vec4<f32>(0.0);
        for (var s: i32 = 0; s < 4; s = s + 1) {
            var off = k0;
            if (s == 1) { off = k1; }
            else if (s == 2) { off = k2; }
            else if (s == 3) { off = k3; }

            let sp = hit_pos + off * nh;
            var dd = length(sp) - 0.78;
            let wob = 0.05 * sin(sp.x * 3.1 + time * 1.3)
                    * cos(sp.y * 2.7 - time * 1.1)
                    * sin(sp.z * 3.3 + time * 0.9);
            dd = dd + wob;
            for (var k: i32 = 0; k < spike_count; k = k + 1) {
                let kf = f32(k);
                let phi = kf * 2.39996323;
                let cos_th = 1.0 - 2.0 * (kf + 0.5) / f32(spike_count);
                let sin_th = sqrt(max(1.0 - cos_th * cos_th, 0.0));
                var dirs = vec3<f32>(cos(phi) * sin_th, cos_th, sin(phi) * sin_th);
                let rot = time * 0.35 + kf * 0.21;
                let cr = cos(rot);
                let sr = sin(rot);
                let dx = dirs.x * cr - dirs.z * sr;
                let dz = dirs.x * sr + dirs.z * cr;
                dirs = normalize(vec3<f32>(dx, dirs.y, dz));
                let phase = kf * 0.9;
                let len_pulse = 0.5 + 0.5 * sin(time * 1.4 + phase);
                let spike_len = mix(0.05, 1.05, len_pulse * pulse + 0.15 * pulse_b);
                let spike_rad = mix(0.32, 0.16, len_pulse);
                let h_t = clamp(dot(sp, dirs) / max(spike_len, 1e-4), 0.0, 1.0);
                let on_axis = dirs * (h_t * spike_len);
                let spike_d = length(sp - on_axis) - spike_rad;
                let kk = 0.32;
                let hh = clamp(0.5 + 0.5 * (spike_d - dd) / kk, 0.0, 1.0);
                dd = mix(spike_d, dd, hh) - kk * hh * (1.0 - hh);
            }
            let mb_pos = vec3<f32>(
                0.65 * sin(time * 0.8),
                0.55 * cos(time * 0.6 + 0.4),
                0.65 * sin(time * 0.7 + 1.2),
            );
            let mb_d = length(sp - mb_pos) - 0.22;
            let kkb = 0.28;
            let hhb = clamp(0.5 + 0.5 * (mb_d - dd) / kkb, 0.0, 1.0);
            dd = mix(mb_d, dd, hhb) - kkb * hhb * (1.0 - hhb);

            if (s == 0) { de_samples.x = dd; }
            else if (s == 1) { de_samples.y = dd; }
            else if (s == 2) { de_samples.z = dd; }
            else { de_samples.w = dd; }
        }

        let n_raw = k0 * de_samples.x + k1 * de_samples.y + k2 * de_samples.z + k3 * de_samples.w;
        let normal = normalize(n_raw + vec3<f32>(1e-6, 0.0, 0.0));

        // View dir from surface to camera.
        let view_dir = -rd;

        // Reflection vector and inline procedural sky lookup for env reflection.
        let refl = reflect(rd, normal);
        var env = vec3<f32>(0.0);
        {
            let dir_y = clamp(refl.y, -1.0, 1.0);
            let horizon = exp(-abs(dir_y) * 3.2);
            let sky_top = vec3<f32>(0.04, 0.07, 0.14);
            let sky_mid = vec3<f32>(0.32, 0.34, 0.45);
            let sky_ground = vec3<f32>(0.05, 0.04, 0.03);
            let up_mix = clamp(0.5 + 0.5 * dir_y, 0.0, 1.0);
            var sky_col = mix(sky_ground, sky_mid, smoothstep(0.0, 0.5, up_mix));
            sky_col = mix(sky_col, sky_top, smoothstep(0.4, 1.0, up_mix));
            sky_col = sky_col + vec3<f32>(1.2, 0.8, 0.55) * horizon * 0.18;
            let sun_dot = clamp(dot(refl, key_light), -1.0, 1.0);
            let sun_glow = pow(max(sun_dot, 0.0), 8.0) * 0.6;
            let sun_disk = smoothstep(0.9985, 0.9995, sun_dot) * 6.0;
            sky_col = sky_col + vec3<f32>(1.5, 1.15, 0.75) * (sun_glow + sun_disk);
            env = sky_col;
        }

        // Fresnel (Schlick) with a fairly metallic F0 for inky liquid.
        let f0 = vec3<f32>(0.05, 0.05, 0.06);
        let cos_v = clamp(dot(normal, view_dir), 0.0, 1.0);
        let one_minus = 1.0 - cos_v;
        let fres = f0 + (vec3<f32>(1.0) - f0) * pow(one_minus, 5.0);

        // Base albedo: nearly black, very slight cool tint.
        let base = vec3<f32>(0.012, 0.013, 0.017);

        // Lambert.
        let n_dot_l = max(dot(normal, key_light), 0.0);

        // Blinn-Phong specular highlight from key light.
        let half_v = normalize(key_light + view_dir);
        let n_dot_h = max(dot(normal, half_v), 0.0);
        let spec = pow(n_dot_h, 256.0) * 1.4;
        let spec_color = vec3<f32>(1.0, 0.95, 0.82) * spec;

        // Cheap AO from step count.
        let ao = clamp(1.0 - f32(steps_used) / 80.0, 0.25, 1.0);

        // Rim term.
        let rim = pow(1.0 - cos_v, 3.0) * 0.5;

        // Composite: dark diffuse + environment * fresnel + specular highlight.
        var lit = base * (0.18 + 0.6 * n_dot_l) * ao;
        lit = lit + env * fres * ao;
        lit = lit + spec_color * (0.5 + 0.5 * fres.y);
        lit = lit + vec3<f32>(0.45, 0.55, 0.75) * rim * fres * 0.6;

        color = lit;
    }

    // Reinhard tonemap with mild exposure.
    let exposure = 1.15;
    let mapped = (color * exposure) / (vec3<f32>(1.0) + color * exposure);
    // Approx gamma.
    let gamma_corrected = pow(max(mapped, vec3<f32>(0.0)), vec3<f32>(1.0 / 2.2));

    return clamp(gamma_corrected, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn shader_quad_apollonian_gasket(
    uv: vec2<f32>,
    resolution: vec2<f32>,
    time: f32,
) -> vec3<f32> {
    // Map uv (origin top-left) to aspect-corrected NDC, y-up.
    let aspect = max(resolution.x, 1.0) / max(resolution.y, 1.0);
    let ndc = vec2<f32>(
        (uv.x * 2.0 - 1.0) * aspect,
        1.0 - uv.y * 2.0,
    );

    // Slow orbit camera with a modest pitch.
    let cam_t = time * 0.16;
    let cam_radius = 2.4;
    let cam_height = 0.55 + 0.18 * sin(time * 0.13);
    let eye = vec3<f32>(cos(cam_t) * cam_radius, cam_height, sin(cam_t) * cam_radius);
    let look_at = vec3<f32>(0.0, 0.0, 0.0);

    // Camera basis.
    let world_up = vec3<f32>(0.0, 1.0, 0.0);
    let fwd_raw = look_at - eye;
    let fwd = fwd_raw / max(length(fwd_raw), 1e-4);
    let right_raw = cross(fwd, world_up);
    let right = right_raw / max(length(right_raw), 1e-4);
    let up = cross(right, fwd);

    // Perspective ray.
    let focal = 1.5;
    let rd_raw = right * ndc.x + up * ndc.y + fwd * focal;
    let rd = rd_raw / max(length(rd_raw), 1e-4);

    // Time-varying Apollonian scale parameter.
    let scale_param = 1.27 + 0.18 * sin(time * 0.18);

    // Background: subtle radial gradient toward edges + sparse stars.
    let radial = length(uv - vec2<f32>(0.5));
    let bg_inner = vec3<f32>(0.025, 0.018, 0.045);
    let bg_outer = vec3<f32>(0.002, 0.003, 0.010);
    var background = mix(bg_inner, bg_outer, clamp(radial * 1.4, 0.0, 1.0));
    let star_seed = floor(rd.xy * 320.0 + vec2<f32>(rd.z * 71.0, rd.z * 113.0));
    let star_h0 = fract(sin(dot(star_seed, vec2<f32>(127.1, 311.7))) * 43758.5453);
    let star_h1 = fract(sin(dot(star_seed, vec2<f32>(269.5, 183.3))) * 23421.631);
    let star_mask = step(0.9965, star_h0);
    background = background + vec3<f32>(star_mask * pow(star_h1, 2.0) * 0.85);

    // Raymarch the Apollonian DE.
    let max_steps: i32 = 96;
    let max_dist: f32 = 6.0;
    let de_iters: i32 = 7;

    var total_dist: f32 = 0.0;
    var hit: bool = false;
    var steps_used: i32 = 0;
    var orbit_trap: f32 = 1e10;

    for (var i: i32 = 0; i < max_steps; i = i + 1) {
        let pos = eye + rd * total_dist;

        // Inline Apollonian DE.
        var p = pos;
        var k_acc: f32 = 1.0;
        var local_trap: f32 = 1e10;
        for (var j: i32 = 0; j < de_iters; j = j + 1) {
            p = -1.0 + 2.0 * fract(0.5 * p + 0.5);
            let r2 = dot(p, p);
            local_trap = min(local_trap, r2);
            let factor = scale_param / max(r2, 1e-4);
            p = p * factor;
            k_acc = k_acc * factor;
        }
        let de = 0.25 * abs(p.y) / max(k_acc, 1e-4);

        let eps = max(0.0009, 0.0006 * total_dist);
        if (de < eps) {
            hit = true;
            orbit_trap = local_trap;
            steps_used = i;
            break;
        }

        total_dist = total_dist + de;
        if (total_dist > max_dist) {
            steps_used = i;
            break;
        }
    }

    var color = background;

    if (hit) {
        let hit_pos = eye + rd * total_dist;

        // Normal via 4-tap tetrahedral gradient of the DE.
        let h = 0.0018;
        let k0 = vec3<f32>(1.0, -1.0, -1.0);
        let k1 = vec3<f32>(-1.0, -1.0, 1.0);
        let k2 = vec3<f32>(-1.0, 1.0, -1.0);
        let k3 = vec3<f32>(1.0, 1.0, 1.0);

        var de0: f32 = 0.0;
        {
            var p = hit_pos + k0 * h;
            var k_acc: f32 = 1.0;
            for (var j: i32 = 0; j < de_iters; j = j + 1) {
                p = -1.0 + 2.0 * fract(0.5 * p + 0.5);
                let r2 = dot(p, p);
                let factor = scale_param / max(r2, 1e-4);
                p = p * factor;
                k_acc = k_acc * factor;
            }
            de0 = 0.25 * abs(p.y) / max(k_acc, 1e-4);
        }
        var de1: f32 = 0.0;
        {
            var p = hit_pos + k1 * h;
            var k_acc: f32 = 1.0;
            for (var j: i32 = 0; j < de_iters; j = j + 1) {
                p = -1.0 + 2.0 * fract(0.5 * p + 0.5);
                let r2 = dot(p, p);
                let factor = scale_param / max(r2, 1e-4);
                p = p * factor;
                k_acc = k_acc * factor;
            }
            de1 = 0.25 * abs(p.y) / max(k_acc, 1e-4);
        }
        var de2: f32 = 0.0;
        {
            var p = hit_pos + k2 * h;
            var k_acc: f32 = 1.0;
            for (var j: i32 = 0; j < de_iters; j = j + 1) {
                p = -1.0 + 2.0 * fract(0.5 * p + 0.5);
                let r2 = dot(p, p);
                let factor = scale_param / max(r2, 1e-4);
                p = p * factor;
                k_acc = k_acc * factor;
            }
            de2 = 0.25 * abs(p.y) / max(k_acc, 1e-4);
        }
        var de3: f32 = 0.0;
        {
            var p = hit_pos + k3 * h;
            var k_acc: f32 = 1.0;
            for (var j: i32 = 0; j < de_iters; j = j + 1) {
                p = -1.0 + 2.0 * fract(0.5 * p + 0.5);
                let r2 = dot(p, p);
                let factor = scale_param / max(r2, 1e-4);
                p = p * factor;
                k_acc = k_acc * factor;
            }
            de3 = 0.25 * abs(p.y) / max(k_acc, 1e-4);
        }
        let n_raw = k0 * de0 + k1 * de1 + k2 * de2 + k3 * de3;
        let normal = normalize(n_raw + vec3<f32>(1e-6, 0.0, 0.0));

        // Lights.
        let key_dir = normalize(vec3<f32>(0.55, 0.75, -0.35));
        let fill_dir = normalize(vec3<f32>(-0.4, 0.6, 0.3));
        let view_dir = normalize(eye - hit_pos);
        let half_dir = normalize(key_dir + view_dir);

        let n_dot_l = max(dot(normal, key_dir), 0.0);
        let n_dot_f = max(dot(normal, fill_dir), 0.0);
        let n_dot_h = max(dot(normal, half_dir), 0.0);

        // Soft shadow: short march toward the key light.
        var shadow: f32 = 1.0;
        {
            var sh_t: f32 = 0.025;
            let sh_max: f32 = 1.0;
            let sh_steps: i32 = 14;
            let sh_k: f32 = 10.0;
            let sh_origin = hit_pos + normal * 0.005;
            for (var s: i32 = 0; s < sh_steps; s = s + 1) {
                let sp = sh_origin + key_dir * sh_t;
                var p = sp;
                var k_acc: f32 = 1.0;
                for (var j: i32 = 0; j < de_iters; j = j + 1) {
                    p = -1.0 + 2.0 * fract(0.5 * p + 0.5);
                    let r2 = dot(p, p);
                    let factor = scale_param / max(r2, 1e-4);
                    p = p * factor;
                    k_acc = k_acc * factor;
                }
                let de_s = 0.25 * abs(p.y) / max(k_acc, 1e-4);
                shadow = min(shadow, sh_k * de_s / max(sh_t, 1e-4));
                if (de_s < 0.0009) {
                    shadow = 0.0;
                    break;
                }
                sh_t = sh_t + max(de_s, 0.012);
                if (sh_t > sh_max) {
                    break;
                }
            }
            shadow = clamp(shadow, 0.0, 1.0);
        }

        // Orbit-trap based color: blend two saturated palettes.
        let trap_norm = clamp(orbit_trap * 1.6, 0.0, 1.0);
        let pal_a0 = vec3<f32>(0.05, 0.55, 0.65);   // teal
        let pal_a1 = vec3<f32>(0.95, 0.30, 0.55);   // pink
        let pal_b0 = vec3<f32>(0.75, 0.10, 0.85);   // magenta
        let pal_b1 = vec3<f32>(0.98, 0.78, 0.20);   // gold
        let pal_a = mix(pal_a0, pal_a1, trap_norm);
        let pal_b = mix(pal_b0, pal_b1, trap_norm);
        let palette_mix = clamp(0.5 + 0.5 * sin(time * 0.27 + trap_norm * 5.3), 0.0, 1.0);
        let surface_col = mix(pal_a, pal_b, palette_mix);

        // AO from raymarch step count.
        let ao = clamp(1.0 - f32(steps_used) / f32(max_steps) * 0.95, 0.05, 1.0);

        // Iridescent fresnel rim.
        let fresnel = pow(1.0 - max(dot(normal, view_dir), 0.0), 4.0);
        let rim_hue = vec3<f32>(
            0.5 + 0.5 * cos(trap_norm * 6.2831 + 0.0),
            0.5 + 0.5 * cos(trap_norm * 6.2831 + 2.094),
            0.5 + 0.5 * cos(trap_norm * 6.2831 + 4.188),
        );
        let rim_col = rim_hue * fresnel * 0.55;

        // Sharp Blinn-Phong specular for that gem look.
        let spec = pow(n_dot_h, 160.0) * shadow;
        let spec_col = vec3<f32>(1.0, 0.95, 0.88) * spec * 1.4;

        // Lighting composition.
        let key_col = vec3<f32>(1.05, 0.92, 0.72);
        let fill_col = vec3<f32>(0.32, 0.48, 0.85);
        let ambient = vec3<f32>(0.05, 0.06, 0.10);

        let diffuse = surface_col * (key_col * n_dot_l * shadow + fill_col * n_dot_f * 0.35);
        var lit = ambient * surface_col * ao + diffuse + spec_col + rim_col;

        // Distance fog blends to background.
        let fog = 1.0 - exp(-total_dist * 0.22);
        lit = mix(lit, background, clamp(fog * 0.4, 0.0, 1.0));

        color = lit;
    }

    // Subtle vignette.
    let vc = uv - vec2<f32>(0.5);
    let vig = 1.0 - dot(vc, vc) * 0.7;
    color = color * clamp(vig, 0.0, 1.0);

    return clamp(color, vec3<f32>(0.0), vec3<f32>(1.0));
}

// Evaluates the variant-specific shader at a given uv. Pulled out of
// `fs_shader_quad` so we can call it from a per-pixel supersample loop
// without duplicating the switch in two places.
fn shader_quad_dispatch(shader_quad: ShaderQuad, uv: vec2<f32>) -> vec3<f32> {
    let resolution_xy = shader_quad_resolution(shader_quad).xy;
    let now = shader_quad.iTime;
    var rgb = vec3<f32>(0.0);
    switch shader_quad.variant {
        case SHADER_QUAD_RIBBON: {
            rgb = shader_quad_ribbon(uv, now);
        }
        case SHADER_QUAD_WAVE_GRID: {
            rgb = shader_quad_wave_grid(uv, now);
        }
        case SHADER_QUAD_SPECTRUM_BARS: {
            rgb = shader_quad_spectrum_bars(uv, now);
        }
        case SHADER_QUAD_WARP_FIELD: {
            rgb = shader_quad_warp_field(uv, now);
        }
        case SHADER_QUAD_CAMERA: {
            rgb = shader_quad_camera(uv, resolution_xy, now);
        }
        case SHADER_QUAD_VOLUMETRIC_CLOUDS: {
            rgb = shader_quad_volumetric_clouds(uv, resolution_xy, now);
        }
        case SHADER_QUAD_MANDELBULB: {
            rgb = shader_quad_mandelbulb(uv, resolution_xy, now);
        }
        case SHADER_QUAD_KIFS_TEMPLE: {
            rgb = shader_quad_kifs_temple(uv, resolution_xy, now);
        }
        case SHADER_QUAD_TUNNEL_WARP: {
            rgb = shader_quad_tunnel_warp(uv, resolution_xy, now);
        }
        case SHADER_QUAD_BLACK_HOLE: {
            rgb = shader_quad_black_hole(uv, resolution_xy, now);
        }
        case SHADER_QUAD_HYPERSPACE_JUMP: {
            rgb = shader_quad_hyperspace_jump(uv, resolution_xy, now);
        }
        case SHADER_QUAD_FERROFLUID: {
            rgb = shader_quad_ferrofluid(uv, resolution_xy, now);
        }
        case SHADER_QUAD_APOLLONIAN_GASKET: {
            rgb = shader_quad_apollonian_gasket(uv, resolution_xy, now);
        }
        case SHADER_QUAD_AUDIO_REACTIVE: {
            rgb = shader_quad_audio_reactive(shader_quad, uv, resolution_xy, now);
            // The visualizer already consumes params; skip the post-pass.
            return rgb;
        }
        default: {
            rgb = shader_quad_plasma(uv, now);
        }
    }

    // Optional post-pass: when the app has supplied non-zero params we apply
    // a palette tint (param_0 in [0, 1]) and a gain (param_1 in [0, 4]) so
    // any built-in becomes user-animatable without touching its body.
    // Keeping the all-zero default a no-op preserves existing renders.
    let p = shader_quad_params4(shader_quad);
    let any_param = max(max(abs(p.x), abs(p.y)), max(abs(p.z), abs(p.w)));
    if (any_param > 1e-5) {
        let tint = mix(
            vec3<f32>(1.0, 1.0, 1.0),
            vec3<f32>(1.0 - rgb.r, 1.0 - rgb.g, 1.0 - rgb.b) + vec3<f32>(0.5, 0.4, 0.7),
            clamp(p.x, 0.0, 1.0),
        );
        let gain = clamp(p.y, 0.0, 4.0);
        let gained = rgb * tint * select(1.0, gain, gain > 1e-5);
        // Subtle saturation push driven by param_2.
        let luminance = dot(gained, vec3<f32>(0.2126, 0.7152, 0.0722));
        let saturated = mix(vec3<f32>(luminance), gained, 1.0 + clamp(p.z, -1.0, 2.0));
        rgb = clamp(saturated, vec3<f32>(0.0), vec3<f32>(1.0));
    }
    return rgb;
}

// Renders 16 vertical bars whose heights are driven by `param_0..param_15`.
// Each band is expected in [0, 1]; values are clamped. Apps wire FFT
// magnitudes (or any other 16-element series) into the params slot to drive
// the visualizer.
fn shader_quad_audio_reactive(
    shader_quad: ShaderQuad,
    uv: vec2<f32>,
    resolution: vec2<f32>,
    time: f32,
) -> vec3<f32> {
    let bands = 16.0;
    let band_index_f = floor(uv.x * bands);
    let band_index = clamp(i32(band_index_f), 0, 15);
    let band_uv = fract(uv.x * bands);

    let raw = shader_quad_param(shader_quad, band_index);
    let height = clamp(raw, 0.0, 1.0);

    // Inverted Y so the bar grows from the bottom.
    let from_bottom = 1.0 - uv.y;
    let bar_mask = step(band_uv, 0.86) * step(from_bottom, height);

    // Glow head a few % above the bar tip.
    let head_glow = smoothstep(height + 0.04, height, from_bottom)
        * smoothstep(0.0, 1.0, height);

    // Palette: cool->warm gradient along Y, plus a slow hue rotation in time.
    let cool = vec3<f32>(0.20, 0.80, 1.00);
    let warm = vec3<f32>(1.00, 0.40, 0.65);
    let palette = mix(cool, warm, clamp(uv.y, 0.0, 1.0));
    let pulse = 0.5 + 0.5 * sin(time * 2.0 + band_index_f * 0.6);

    let bar_rgb = palette * (0.4 + 0.6 * pulse);
    let head_rgb = vec3<f32>(1.0, 0.95, 0.85) * 0.9;

    // Floor reflection so the bottom edge of the canvas glows when bars are tall.
    // A faint horizontal scanline texture proportional to resolution so the
    // visualizer subtly responds to canvas size and we use every parameter.
    let scanline = 0.06 * sin(uv.y * resolution.y * 0.6);
    let floor_glow = smoothstep(0.0, 0.18, from_bottom) * (1.0 - from_bottom)
        * 0.35
        * height;

    return bar_rgb * bar_mask
        + head_rgb * head_glow
        + palette * floor_glow
        + vec3<f32>(scanline) * bar_mask;
}

@fragment
fn fs_shader_quad(input: ShaderQuadVarying) -> @location(0) vec4<f32> {
    if (any(input.clip_distances < vec4<f32>(0.0))) {
        return vec4<f32>(0.0);
    }

    let shader_quad = b_shader_quads[input.shader_quad_id];
    let signed_distance = quad_sdf(input.position.xy, shader_quad.bounds, shader_quad_corner_radii(shader_quad));
    let coverage = clamp(0.5 - signed_distance, 0.0, 1.0);
    if (coverage == 0.0) {
        return vec4<f32>(0.0);
    }

    let inv_size = vec2<f32>(1.0) / max(shader_quad.bounds.size, vec2<f32>(1e-4));
    let base_uv = clamp((input.position.xy - shader_quad.bounds.origin) * inv_size, vec2<f32>(0.0), vec2<f32>(1.0));

    // Supersample within a single pixel: ss = 1 → no extra cost,
    // ss = 2 → 4 samples, ss = 4 → 16 samples. WGSL requires constant loop
    // bounds for vectorization, so we hand-unroll the small lattice with
    // an explicit branch on the requested factor.
    let ss = clamp(shader_quad.supersample, 1u, 4u);

    var rgb_sum = vec3<f32>(0.0);
    var sample_count: f32 = 0.0;

    if (ss <= 1u) {
        rgb_sum = shader_quad_dispatch(shader_quad, base_uv);
        sample_count = 1.0;
    } else {
        // ss is 2 or 4. Step is 1.0 / ss within a single source pixel,
        // mapped into uv space via inv_size.
        let n = i32(ss);
        let step = 1.0 / f32(n);
        for (var iy: i32 = 0; iy < n; iy = iy + 1) {
            for (var ix: i32 = 0; ix < n; ix = ix + 1) {
                let jitter = vec2<f32>(
                    (f32(ix) + 0.5) * step - 0.5,
                    (f32(iy) + 0.5) * step - 0.5,
                );
                let uv_sample = clamp(
                    base_uv + jitter * inv_size,
                    vec2<f32>(0.0),
                    vec2<f32>(1.0),
                );
                rgb_sum = rgb_sum + shader_quad_dispatch(shader_quad, uv_sample);
                sample_count = sample_count + 1.0;
            }
        }
    }

    let rgb = rgb_sum / max(sample_count, 1.0);
    return blend_color(vec4<f32>(rgb, 1.0), coverage * shader_quad.opacity);
}

// Returns the dash velocity of a corner given the dash velocity of the two
// sides, by returning the slower velocity (larger dashes).
//
// Since 0 is used for dash velocity when the border width is 0 (instead of
// +inf), this returns the other dash velocity in that case.
//
// An alternative to this might be to appropriately interpolate the dash
// velocity around the corner, but that seems overcomplicated.
fn corner_dash_velocity(dv1: f32, dv2: f32) -> f32 {
    if (dv1 == 0.0) {
        return dv2;
    } else if (dv2 == 0.0) {
        return dv1;
    } else {
        return min(dv1, dv2);
    }
}

// Returns alpha used to render antialiased dashes.
// `t` is within the dash when `fmod(t, period) < length`.
fn dash_alpha(t: f32, period: f32, length: f32, dash_velocity: f32, antialias_threshold: f32) -> f32 {
    let half_period = period / 2;
    let half_length = length / 2;
    // Value in [-half_period, half_period].
    // The dash is in [-half_length, half_length].
    let centered = fmod(t + half_period - half_length, period) - half_period;
    // Signed distance for the dash, negative values are inside the dash.
    let signed_distance = abs(centered) - half_length;
    // Antialiased alpha based on the signed distance.
    return saturate(antialias_threshold - signed_distance / dash_velocity);
}

// This approximates distance to the nearest point to a quarter ellipse in a way
// that is sufficient for anti-aliasing when the ellipse is not very eccentric.
// The components of `point` are expected to be positive.
//
// Negative on the outside and positive on the inside.
fn quarter_ellipse_sdf(point: vec2<f32>, radii: vec2<f32>) -> f32 {
    // Scale the space to treat the ellipse like a unit circle.
    let circle_vec = point / radii;
    let unit_circle_sdf = length(circle_vec) - 1.0;
    // Approximate up-scaling of the length by using the average of the radii.
    //
    // TODO: A better solution would be to use the gradient of the implicit
    // function for an ellipse to approximate a scaling factor.
    return unit_circle_sdf * (radii.x + radii.y) * -0.5;
}

// Modulus that has the same sign as `a`.
fn fmod(a: f32, b: f32) -> f32 {
    return a - b * trunc(a / b);
}

// --- shadows --- //

struct Shadow {
    order: u32,
    blur_radius: f32,
    bounds: Bounds,
    corner_radii: Corners,
    content_mask: Bounds,
    color: Hsla,
}
@group(1) @binding(0) var<storage, read> b_shadows: array<Shadow>;

struct ShadowVarying {
    @builtin(position) position: vec4<f32>,
    @location(0) @interpolate(flat) color: vec4<f32>,
    @location(1) @interpolate(flat) shadow_id: u32,
    //TODO: use `clip_distance` once Naga supports it
    @location(3) clip_distances: vec4<f32>,
}

@vertex
fn vs_shadow(@builtin(vertex_index) vertex_id: u32, @builtin(instance_index) instance_id: u32) -> ShadowVarying {
    let unit_vertex = vec2<f32>(f32(vertex_id & 1u), 0.5 * f32(vertex_id & 2u));
    var shadow = b_shadows[instance_id];

    let margin = 3.0 * shadow.blur_radius;
    // Set the bounds of the shadow and adjust its size based on the shadow's
    // spread radius to achieve the spreading effect
    shadow.bounds.origin -= vec2<f32>(margin);
    shadow.bounds.size += 2.0 * vec2<f32>(margin);

    var out = ShadowVarying();
    out.position = to_device_position(unit_vertex, shadow.bounds);
    out.color = hsla_to_rgba(shadow.color);
    out.shadow_id = instance_id;
    out.clip_distances = distance_from_clip_rect(unit_vertex, shadow.bounds, shadow.content_mask);
    return out;
}

@fragment
fn fs_shadow(input: ShadowVarying) -> @location(0) vec4<f32> {
    // Alpha clip first, since we don't have `clip_distance`.
    if (any(input.clip_distances < vec4<f32>(0.0))) {
        return vec4<f32>(0.0);
    }

    let shadow = b_shadows[input.shadow_id];
    let half_size = shadow.bounds.size / 2.0;
    let center = shadow.bounds.origin + half_size;
    let center_to_point = input.position.xy - center;

    let corner_radius = pick_corner_radius(center_to_point, shadow.corner_radii);

    // The signal is only non-zero in a limited range, so don't waste samples
    let low = center_to_point.y - half_size.y;
    let high = center_to_point.y + half_size.y;
    let start = clamp(-3.0 * shadow.blur_radius, low, high);
    let end = clamp(3.0 * shadow.blur_radius, low, high);

    // Accumulate samples (we can get away with surprisingly few samples)
    let step = (end - start) / 4.0;
    var y = start + step * 0.5;
    var alpha = 0.0;
    for (var i = 0; i < 4; i += 1) {
        let blur = blur_along_x(center_to_point.x, center_to_point.y - y,
            shadow.blur_radius, corner_radius, half_size);
        alpha +=  blur * gaussian(y, shadow.blur_radius) * step;
        y += step;
    }

    return blend_color(input.color, alpha);
}

// --- path rasterization --- //

struct PathRasterizationVertex {
    xy_position: vec2<f32>,
    st_position: vec2<f32>,
    color: Background,
    bounds: Bounds,
}

@group(1) @binding(0) var<storage, read> b_path_vertices: array<PathRasterizationVertex>;

struct PathRasterizationVarying {
    @builtin(position) position: vec4<f32>,
    @location(0) st_position: vec2<f32>,
    @location(1) @interpolate(flat) vertex_id: u32,
    //TODO: use `clip_distance` once Naga supports it
    @location(3) clip_distances: vec4<f32>,
}

@vertex
fn vs_path_rasterization(@builtin(vertex_index) vertex_id: u32) -> PathRasterizationVarying {
    let v = b_path_vertices[vertex_id];

    var out = PathRasterizationVarying();
    out.position = to_device_position_impl(v.xy_position);
    out.st_position = v.st_position;
    out.vertex_id = vertex_id;
    out.clip_distances = distance_from_clip_rect_impl(v.xy_position, v.bounds);
    return out;
}

@fragment
fn fs_path_rasterization(input: PathRasterizationVarying) -> @location(0) vec4<f32> {
    let dx = dpdx(input.st_position);
    let dy = dpdy(input.st_position);
    if (any(input.clip_distances < vec4<f32>(0.0))) {
        return vec4<f32>(0.0);
    }

    let v = b_path_vertices[input.vertex_id];
    let background = v.color;
    let bounds = v.bounds;

    var alpha: f32;
    if (length(vec2<f32>(dx.x, dy.x)) < 0.001) {
        // If the gradient is too small, return a solid color.
        alpha = 1.0;
    } else {
        let gradient = 2.0 * input.st_position.xx * vec2<f32>(dx.x, dy.x) - vec2<f32>(dx.y, dy.y);
        let f = input.st_position.x * input.st_position.x - input.st_position.y;
        let distance = f / length(gradient);
        alpha = saturate(0.5 - distance);
    }
    let prepared_gradient = prepare_gradient_color(
        background.tag,
        background.color_space,
        background.solid,
        background.colors,
    );
    let color = gradient_color(background, input.position.xy, bounds,
        prepared_gradient.solid, prepared_gradient.color0, prepared_gradient.color1);
    return vec4<f32>(color.rgb * color.a * alpha, color.a * alpha);
}

// --- paths --- //

struct PathSprite {
    bounds: Bounds,
}
@group(1) @binding(0) var<storage, read> b_path_sprites: array<PathSprite>;

struct PathVarying {
    @builtin(position) position: vec4<f32>,
    @location(0) texture_coords: vec2<f32>,
}

@vertex
fn vs_path(@builtin(vertex_index) vertex_id: u32, @builtin(instance_index) instance_id: u32) -> PathVarying {
    let unit_vertex = vec2<f32>(f32(vertex_id & 1u), 0.5 * f32(vertex_id & 2u));
    let sprite = b_path_sprites[instance_id];
    // Don't apply content mask because it was already accounted for when rasterizing the path.
    let device_position = to_device_position(unit_vertex, sprite.bounds);
    // For screen-space intermediate texture, convert screen position to texture coordinates
    let screen_position = sprite.bounds.origin + unit_vertex * sprite.bounds.size;
    let texture_coords = screen_position / globals.viewport_size;

    var out = PathVarying();
    out.position = device_position;
    out.texture_coords = texture_coords;

    return out;
}

@fragment
fn fs_path(input: PathVarying) -> @location(0) vec4<f32> {
    let sample = textureSample(t_sprite, s_sprite, input.texture_coords);
    return sample;
}

// --- underlines --- //

struct Underline {
    order: u32,
    pad: u32,
    bounds: Bounds,
    content_mask: Bounds,
    color: Hsla,
    thickness: f32,
    wavy: u32,
}
@group(1) @binding(0) var<storage, read> b_underlines: array<Underline>;

struct UnderlineVarying {
    @builtin(position) position: vec4<f32>,
    @location(0) @interpolate(flat) color: vec4<f32>,
    @location(1) @interpolate(flat) underline_id: u32,
    //TODO: use `clip_distance` once Naga supports it
    @location(3) clip_distances: vec4<f32>,
}

@vertex
fn vs_underline(@builtin(vertex_index) vertex_id: u32, @builtin(instance_index) instance_id: u32) -> UnderlineVarying {
    let unit_vertex = vec2<f32>(f32(vertex_id & 1u), 0.5 * f32(vertex_id & 2u));
    let underline = b_underlines[instance_id];

    var out = UnderlineVarying();
    out.position = to_device_position(unit_vertex, underline.bounds);
    out.color = hsla_to_rgba(underline.color);
    out.underline_id = instance_id;
    out.clip_distances = distance_from_clip_rect(unit_vertex, underline.bounds, underline.content_mask);
    return out;
}

@fragment
fn fs_underline(input: UnderlineVarying) -> @location(0) vec4<f32> {
    const WAVE_FREQUENCY: f32 = 2.0;
    const WAVE_HEIGHT_RATIO: f32 = 0.8;

    // Alpha clip first, since we don't have `clip_distance`.
    if (any(input.clip_distances < vec4<f32>(0.0))) {
        return vec4<f32>(0.0);
    }

    let underline = b_underlines[input.underline_id];
    if ((underline.wavy & 0xFFu) == 0u)
    {
        return blend_color(input.color, input.color.a);
    }

    let half_thickness = underline.thickness * 0.5;

    let st = (input.position.xy - underline.bounds.origin) / underline.bounds.size.y - vec2<f32>(0.0, 0.5);
    let frequency = M_PI_F * WAVE_FREQUENCY * underline.thickness / underline.bounds.size.y;
    let amplitude = (underline.thickness * WAVE_HEIGHT_RATIO) / underline.bounds.size.y;

    let sine = sin(st.x * frequency) * amplitude;
    let dSine = cos(st.x * frequency) * amplitude * frequency;
    let distance = (st.y - sine) / sqrt(1.0 + dSine * dSine);
    let distance_in_pixels = distance * underline.bounds.size.y;
    let distance_from_top_border = distance_in_pixels - half_thickness;
    let distance_from_bottom_border = distance_in_pixels + half_thickness;
    let alpha = saturate(0.5 - max(-distance_from_bottom_border, distance_from_top_border));
    return blend_color(input.color, alpha * input.color.a);
}

// --- monochrome sprites --- //

struct MonochromeSprite {
    order: u32,
    pad: u32,
    bounds: Bounds,
    content_mask: Bounds,
    color: Hsla,
    tile: AtlasTile,
    transformation: TransformationMatrix,
}
@group(1) @binding(0) var<storage, read> b_mono_sprites: array<MonochromeSprite>;

struct MonoSpriteVarying {
    @builtin(position) position: vec4<f32>,
    @location(0) tile_position: vec2<f32>,
    @location(1) @interpolate(flat) color: vec4<f32>,
    @location(3) clip_distances: vec4<f32>,
}

@vertex
fn vs_mono_sprite(@builtin(vertex_index) vertex_id: u32, @builtin(instance_index) instance_id: u32) -> MonoSpriteVarying {
    let unit_vertex = vec2<f32>(f32(vertex_id & 1u), 0.5 * f32(vertex_id & 2u));
    let sprite = b_mono_sprites[instance_id];

    var out = MonoSpriteVarying();
    out.position = to_device_position_transformed(unit_vertex, sprite.bounds, sprite.transformation);

    out.tile_position = to_tile_position(unit_vertex, sprite.tile);
    out.color = hsla_to_rgba(sprite.color);
    out.clip_distances = distance_from_clip_rect_transformed(unit_vertex, sprite.bounds, sprite.content_mask, sprite.transformation);
    return out;
}

@fragment
fn fs_mono_sprite(input: MonoSpriteVarying) -> @location(0) vec4<f32> {
    let sample = textureSample(t_sprite, s_sprite, input.tile_position).r;
    let alpha_corrected = apply_contrast_and_gamma_correction(sample, input.color.rgb, gamma_params.grayscale_enhanced_contrast, gamma_params.gamma_ratios);

    // Alpha clip after using the derivatives.
    if (any(input.clip_distances < vec4<f32>(0.0))) {
        return vec4<f32>(0.0);
    }

    return blend_color(input.color, alpha_corrected);
}

// --- polychrome sprites --- //

struct PolychromeSprite {
    order: u32,
    pad: u32,
    grayscale: u32,
    opacity: f32,
    bounds: Bounds,
    content_mask: Bounds,
    corner_radii: Corners,
    tile: AtlasTile,
}
@group(1) @binding(0) var<storage, read> b_poly_sprites: array<PolychromeSprite>;

struct PolySpriteVarying {
    @builtin(position) position: vec4<f32>,
    @location(0) tile_position: vec2<f32>,
    @location(1) @interpolate(flat) sprite_id: u32,
    @location(3) clip_distances: vec4<f32>,
}

@vertex
fn vs_poly_sprite(@builtin(vertex_index) vertex_id: u32, @builtin(instance_index) instance_id: u32) -> PolySpriteVarying {
    let unit_vertex = vec2<f32>(f32(vertex_id & 1u), 0.5 * f32(vertex_id & 2u));
    let sprite = b_poly_sprites[instance_id];

    var out = PolySpriteVarying();
    out.position = to_device_position(unit_vertex, sprite.bounds);
    out.tile_position = to_tile_position(unit_vertex, sprite.tile);
    out.sprite_id = instance_id;
    out.clip_distances = distance_from_clip_rect(unit_vertex, sprite.bounds, sprite.content_mask);
    return out;
}

@fragment
fn fs_poly_sprite(input: PolySpriteVarying) -> @location(0) vec4<f32> {
    let sample = textureSample(t_sprite, s_sprite, input.tile_position);
    // Alpha clip after using the derivatives.
    if (any(input.clip_distances < vec4<f32>(0.0))) {
        return vec4<f32>(0.0);
    }

    let sprite = b_poly_sprites[input.sprite_id];
    let distance = quad_sdf(input.position.xy, sprite.bounds, sprite.corner_radii);

    var color = sample;
    if ((sprite.grayscale & 0xFFu) != 0u) {
        let grayscale = dot(color.rgb, GRAYSCALE_FACTORS);
        color = vec4<f32>(vec3<f32>(grayscale), sample.a);
    }
    return blend_color(color, sprite.opacity * saturate(0.5 - distance));
}

// --- surfaces --- //

struct SurfaceParams {
    bounds: Bounds,
    content_mask: Bounds,
}

@group(1) @binding(0) var<uniform> surface_locals: SurfaceParams;
@group(1) @binding(1) var t_y: texture_2d<f32>;
@group(1) @binding(2) var t_cb_cr: texture_2d<f32>;
@group(1) @binding(3) var s_surface: sampler;

const ycbcr_to_RGB = mat4x4<f32>(
    vec4<f32>( 1.0000f,  1.0000f,  1.0000f, 0.0),
    vec4<f32>( 0.0000f, -0.3441f,  1.7720f, 0.0),
    vec4<f32>( 1.4020f, -0.7141f,  0.0000f, 0.0),
    vec4<f32>(-0.7010f,  0.5291f, -0.8860f, 1.0),
);

struct SurfaceVarying {
    @builtin(position) position: vec4<f32>,
    @location(0) texture_position: vec2<f32>,
    @location(3) clip_distances: vec4<f32>,
}

@vertex
fn vs_surface(@builtin(vertex_index) vertex_id: u32) -> SurfaceVarying {
    let unit_vertex = vec2<f32>(f32(vertex_id & 1u), 0.5 * f32(vertex_id & 2u));

    var out = SurfaceVarying();
    out.position = to_device_position(unit_vertex, surface_locals.bounds);
    out.texture_position = unit_vertex;
    out.clip_distances = distance_from_clip_rect(unit_vertex, surface_locals.bounds, surface_locals.content_mask);
    return out;
}

@fragment
fn fs_surface(input: SurfaceVarying) -> @location(0) vec4<f32> {
    // Alpha clip after using the derivatives.
    if (any(input.clip_distances < vec4<f32>(0.0))) {
        return vec4<f32>(0.0);
    }

    let y_cb_cr = vec4<f32>(
        textureSampleLevel(t_y, s_surface, input.texture_position, 0.0).r,
        textureSampleLevel(t_cb_cr, s_surface, input.texture_position, 0.0).rg,
        1.0);

    return ycbcr_to_RGB * y_cb_cr;
}
