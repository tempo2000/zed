#![cfg_attr(target_family = "wasm", no_main)]

use std::time::Instant;

use gpui::{
    App, Bounds, Context, Render, ShaderMaterial, ShaderSource, SharedString, Window, WindowBounds,
    WindowOptions, canvas, div, prelude::*, px, rgb, size,
};
use gpui_platform::application;

/// (name, corner radius, tile height).
type ShaderRow = (&'static str, f32, f32);

/// Built-in shader names rendered side by side in the top row.
const ROW_SHADERS: &[ShaderRow] = &[
    ("plasma", 12.0, 160.0),
    ("ribbon", 24.0, 160.0),
    ("wave_grid", 6.0, 160.0),
    ("spectrum_bars", 18.0, 160.0),
];

/// Heavier 3D / raymarching built-ins rendered in the extreme row.
///
/// Each tile pushes the fragment shader budget harder than the top row to
/// demonstrate that GPUI can host non-trivial per-pixel work without
/// bespoke renderer plumbing.
const EXTREME_SHADERS: &[ShaderRow] = &[
    ("volumetric_clouds", 14.0, 220.0),
    ("mandelbulb", 18.0, 220.0),
    ("kifs_temple", 18.0, 220.0),
    ("tunnel_warp", 22.0, 220.0),
];

/// "Crazier" row: gravitational lensing, hyperspace, ferrofluid, and the
/// Apollonian sphere packing. These are the heaviest fragment programs in
/// the demo and give the best impression of what GPUI can host per pixel.
const CRAZIER_SHADERS: &[ShaderRow] = &[
    ("black_hole", 16.0, 240.0),
    ("hyperspace_jump", 16.0, 240.0),
    ("ferrofluid", 20.0, 240.0),
    ("apollonian_gasket", 20.0, 240.0),
];

/// Built-in shader name used to demonstrate vertex displacement.
const VERTEX_DISPLACEMENT_SHADER: &str = "warp_field";

/// Built-in shader name used for the rotating-mesh camera demo.
const CAMERA_SHADER: &str = "camera";

/// Smoothing factor for the displayed FPS value.
const FPS_SMOOTHING: f32 = 0.1;

/// Read an env-var stress knob (1, 2, or 4). Falls back to `default` for any
/// unset / unparseable value, then clamps to the supported range.
fn env_stress(name: &str, default: u32) -> u32 {
    std::env::var(name)
        .ok()
        .and_then(|raw| raw.trim().parse::<u32>().ok())
        .unwrap_or(default)
        .clamp(1, 4)
}

struct ShaderQuadExample {
    started_at: Instant,
    last_frame_at: Instant,
    last_time_seconds: f32,
    frame_count: u32,
    smoothed_fps: f32,
    /// Linear multiplier on tile dimensions for the extreme/crazier rows.
    /// Driven by `GPUI_STRESS_TILES`. Default 1 (no upscale).
    tile_scale: u32,
    /// Per-pixel supersample factor passed to heavy variants. Driven by
    /// `GPUI_SUPERSAMPLE`. Default 1 (no supersampling).
    supersample: u32,
}

impl ShaderQuadExample {
    fn new() -> Self {
        let now = Instant::now();
        Self {
            started_at: now,
            last_frame_at: now,
            last_time_seconds: 0.0,
            frame_count: 0,
            smoothed_fps: 0.0,
            tile_scale: env_stress("GPUI_STRESS_TILES", 1),
            supersample: env_stress("GPUI_SUPERSAMPLE", 1),
        }
    }

    fn tick(&mut self) -> ShaderTick {
        let now = Instant::now();
        let time = now.duration_since(self.started_at).as_secs_f32();
        let raw_delta = now.duration_since(self.last_frame_at).as_secs_f32();
        self.last_frame_at = now;
        self.last_time_seconds = time;
        self.frame_count = self.frame_count.wrapping_add(1);

        if raw_delta > 0.0 {
            let instant_fps = 1.0 / raw_delta;
            if self.smoothed_fps <= 0.0 {
                self.smoothed_fps = instant_fps;
            } else {
                self.smoothed_fps =
                    self.smoothed_fps + (instant_fps - self.smoothed_fps) * FPS_SMOOTHING;
            }
        }

        ShaderTick {
            time,
            time_delta: raw_delta,
            frame: self.frame_count,
        }
    }

    fn material(
        &self,
        tick: &ShaderTick,
        name: &'static str,
        corner_radius: f32,
        supersample: u32,
    ) -> ShaderMaterial {
        ShaderMaterial {
            shader: ShaderSource::BuiltIn(SharedString::from(name)),
            corner_radii: px(corner_radius).into(),
            time: tick.time,
            time_delta: tick.time_delta,
            frame: tick.frame,
            supersample,
            ..Default::default()
        }
    }

    fn shader_tile(
        &self,
        tick: &ShaderTick,
        name: &'static str,
        corner_radius: f32,
        tile_height: f32,
        supersample: u32,
    ) -> impl IntoElement + use<> {
        let material = self.material(tick, name, corner_radius, supersample);
        let scaled_height = tile_height * self.tile_scale as f32;

        div()
            .id(name)
            .flex()
            .flex_col()
            .gap_2()
            .flex_1()
            .min_w_0()
            .hover(|style| style.opacity(0.85))
            .child(
                canvas(
                    |_, _, _| (),
                    move |bounds, (), window, _| {
                        window.paint_shader_quad(bounds, material);
                    },
                )
                .w_full()
                .h(px(scaled_height))
                .rounded(px(corner_radius)),
            )
            .child(
                div()
                    .text_xs()
                    .text_color(rgb(0xb6bcc7))
                    .child(SharedString::from(name)),
            )
    }
}

struct ShaderTick {
    time: f32,
    time_delta: f32,
    frame: u32,
}

impl Render for ShaderQuadExample {
    fn render(&mut self, window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        window.request_animation_frame();

        let tick = self.tick();
        // Top row stays light (1x supersample). Extreme + crazier rows pick
        // up the configured supersample factor.
        let heavy_ss = self.supersample;
        let warp_material = self.material(&tick, VERTEX_DISPLACEMENT_SHADER, 28.0, heavy_ss);
        let camera_material = self.material(&tick, CAMERA_SHADER, 18.0, heavy_ss);

        let row = ROW_SHADERS
            .iter()
            .map(|(name, radius, height)| self.shader_tile(&tick, name, *radius, *height, 1));
        let extreme_row = EXTREME_SHADERS.iter().map(|(name, radius, height)| {
            self.shader_tile(&tick, name, *radius, *height, heavy_ss)
        });
        let crazier_row = CRAZIER_SHADERS.iter().map(|(name, radius, height)| {
            self.shader_tile(&tick, name, *radius, *height, heavy_ss)
        });

        let fps_label = SharedString::from(format!(
            "{:>5.1} fps  ·  frame {}  ·  t {:>5.2}s  ·  tiles {}x  ·  ss {}x",
            self.smoothed_fps, tick.frame, self.last_time_seconds, self.tile_scale, heavy_ss
        ));

        div()
            .flex()
            .flex_col()
            .gap_5()
            .p_8()
            .size_full()
            .bg(rgb(0x101318))
            .text_color(rgb(0xf5f7fa))
            .child(
                div()
                    .flex()
                    .flex_row()
                    .items_center()
                    .justify_between()
                    .gap_4()
                    .child(div().text_2xl().child("Shader quads"))
                    .child(
                        div()
                            .px_3()
                            .py_1()
                            .rounded(px(8.))
                            .bg(rgb(0x1c2129))
                            .text_xs()
                            .text_color(rgb(0xb6bcc7))
                            .child(fps_label),
                    ),
            )
            .child(
                div()
                    .text_sm()
                    .text_color(rgb(0xb6bcc7))
                    .child("Built-in fragment shaders rendered as GPUI primitives."),
            )
            .child(div().flex().flex_row().gap_4().w_full().children(row))
            .child(div().mt_2().text_sm().text_color(rgb(0xb6bcc7)).child(
                "Heavier 3D / raymarching variants \
                         (clouds, fractals, kaleidoscopic IFS, neon tunnel)",
            ))
            .child(
                div()
                    .flex()
                    .flex_row()
                    .gap_4()
                    .w_full()
                    .children(extreme_row),
            )
            .child(div().mt_2().text_sm().text_color(rgb(0xb6bcc7)).child(
                "Crazier raymarched / lensed scenes \
                         (gravitational lens, hyperspace jump, ferrofluid, Apollonian)",
            ))
            .child(
                div()
                    .flex()
                    .flex_row()
                    .gap_4()
                    .w_full()
                    .children(crazier_row),
            )
            .child(
                div()
                    .mt_2()
                    .text_sm()
                    .text_color(rgb(0xb6bcc7))
                    .child("Vertex displacement and rotating-camera variants"),
            )
            .child(
                div()
                    .flex()
                    .flex_row()
                    .gap_4()
                    .w_full()
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .gap_2()
                            .flex_1()
                            .min_w_0()
                            .child(
                                canvas(
                                    |_, _, _| (),
                                    move |bounds, (), window, _| {
                                        window.paint_shader_quad(bounds, warp_material);
                                    },
                                )
                                .w_full()
                                .h(px(260. * self.tile_scale as f32))
                                .rounded(px(28.))
                                .border_1()
                                .border_color(rgb(0x2a2f3a)),
                            )
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(rgb(0xb6bcc7))
                                    .child(SharedString::from(VERTEX_DISPLACEMENT_SHADER)),
                            ),
                    )
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .gap_2()
                            .flex_1()
                            .min_w_0()
                            .child(
                                canvas(
                                    |_, _, _| (),
                                    move |bounds, (), window, _| {
                                        window.paint_shader_quad(bounds, camera_material);
                                    },
                                )
                                .w_full()
                                .h(px(260. * self.tile_scale as f32))
                                .rounded(px(18.))
                                .border_1()
                                .border_color(rgb(0x2a2f3a)),
                            )
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(rgb(0xb6bcc7))
                                    .child(SharedString::from(CAMERA_SHADER)),
                            ),
                    ),
            )
    }
}

fn run_example() {
    application().run(|cx: &mut App| {
        let bounds = Bounds::centered(None, size(px(1280.), px(1380.)), cx);
        cx.open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                ..Default::default()
            },
            |_, cx| cx.new(|_| ShaderQuadExample::new()),
        )
        .unwrap();
        cx.activate(true);
    });
}

#[cfg(not(target_family = "wasm"))]
fn main() {
    run_example();
}

#[cfg(target_family = "wasm")]
#[wasm_bindgen::prelude::wasm_bindgen(start)]
pub fn start() {
    gpui_platform::web_init();
    run_example();
}
