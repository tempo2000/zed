#![cfg_attr(target_family = "wasm", no_main)]

use std::time::Instant;

use gpui::{
    App, Bounds, Context, Render, ShaderMaterial, ShaderSource, SharedString, Window, WindowBounds,
    WindowOptions, canvas, div, prelude::*, px, rgb, size,
};
use gpui_platform::application;

const TRACK_LENGTH_SECONDS: f32 = 240.0;
/// Number of "FFT" bands fed into the `audio_reactive` shader. Matches the
/// 16 scalar params slot on `ShaderMaterial`.
const BAND_COUNT: usize = 16;

struct ShaderVisualizer {
    started_at: Instant,
    now_playing: SharedString,
    artist: SharedString,
    progress: f32,
    bands: [f32; BAND_COUNT],
}

impl ShaderVisualizer {
    fn new() -> Self {
        Self {
            started_at: Instant::now(),
            now_playing: SharedString::from("Aurora Drift"),
            artist: SharedString::from("Lumen Trails"),
            progress: 0.0,
            bands: [0.0; BAND_COUNT],
        }
    }

    fn update_signals(&mut self, time: f32) {
        self.progress = (time % TRACK_LENGTH_SECONDS) / TRACK_LENGTH_SECONDS;

        // Synthesize 16 frequency bands. Lower bands beat slower and harder,
        // higher bands flicker faster, so the result reads as music-like.
        for (index, band) in self.bands.iter_mut().enumerate() {
            let n = index as f32;
            let frequency = 0.6 + 0.18 * n;
            let envelope = (-0.04 * n).exp().max(0.15);
            let beat = 0.5 + 0.5 * (time * frequency + n * 0.7).sin();
            let shimmer = 0.25 * (time * 6.0 + n * 1.5).sin();
            *band = (envelope * beat + shimmer * 0.4 + 0.05).clamp(0.0, 1.0);
        }
    }

    fn shader_material(
        &self,
        shader_name: &'static str,
        time: f32,
        corner_radius: f32,
    ) -> ShaderMaterial {
        ShaderMaterial {
            shader: ShaderSource::BuiltIn(SharedString::from(shader_name)),
            corner_radii: px(corner_radius).into(),
            time,
            ..Default::default()
        }
    }

    /// Build a material whose `params` slot carries the current 16-band
    /// "spectrum". `audio_reactive` reads each band as a vertical bar
    /// height; other variants would see them as palette/intensity hints
    /// via the dispatcher's post-pass.
    fn audio_reactive_material(&self, time: f32, corner_radius: f32) -> ShaderMaterial {
        ShaderMaterial {
            shader: ShaderSource::BuiltIn(SharedString::from("audio_reactive")),
            corner_radii: px(corner_radius).into(),
            time,
            params: self.bands,
            ..Default::default()
        }
    }
}

fn format_clock(seconds: f32) -> SharedString {
    let total = seconds.max(0.0) as u32;
    let minutes = total / 60;
    let secs = total % 60;
    SharedString::from(format!("{:02}:{:02}", minutes, secs))
}

impl Render for ShaderVisualizer {
    fn render(&mut self, window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        window.request_animation_frame();

        let time = self.started_at.elapsed().as_secs_f32();
        self.update_signals(time);

        let main_material = self.shader_material("warp_field", time, 18.0);
        let bars_material = self.audio_reactive_material(time, 10.0);
        let grid_material = self.shader_material("wave_grid", time, 10.0);
        let plasma_material = self.shader_material("plasma", time, 10.0);
        let seek_material = self.shader_material("ribbon", time, 4.0);

        let progress = self.progress;
        let elapsed_label = format_clock(progress * TRACK_LENGTH_SECONDS);
        let total_label = format_clock(TRACK_LENGTH_SECONDS);

        div()
            .flex()
            .flex_col()
            .gap_4()
            .p_8()
            .size_full()
            .bg(rgb(0x0b0d12))
            .text_color(rgb(0xf5f7fa))
            .child(
                div()
                    .flex()
                    .flex_row()
                    .justify_between()
                    .items_baseline()
                    .child(div().text_2xl().child(self.now_playing.clone()))
                    .child(
                        div()
                            .text_sm()
                            .text_color(rgb(0x9aa3b2))
                            .child(self.artist.clone()),
                    ),
            )
            .child(
                canvas(
                    |_, _, _| (),
                    move |bounds, (), window, _| {
                        window.paint_shader_quad(bounds, main_material);
                    },
                )
                .w_full()
                .h(px(220.))
                .rounded_lg(),
            )
            .child(
                div()
                    .flex()
                    .flex_row()
                    .gap_3()
                    .h(px(96.))
                    .child(
                        canvas(
                            |_, _, _| (),
                            move |bounds, (), window, _| {
                                window.paint_shader_quad(bounds, bars_material);
                            },
                        )
                        .flex_1()
                        .h_full()
                        .rounded_md(),
                    )
                    .child(
                        canvas(
                            |_, _, _| (),
                            move |bounds, (), window, _| {
                                window.paint_shader_quad(bounds, grid_material);
                            },
                        )
                        .flex_1()
                        .h_full()
                        .rounded_md(),
                    )
                    .child(
                        canvas(
                            |_, _, _| (),
                            move |bounds, (), window, _| {
                                window.paint_shader_quad(bounds, plasma_material);
                            },
                        )
                        .flex_1()
                        .h_full()
                        .rounded_md(),
                    ),
            )
            .child(
                div()
                    .relative()
                    .w_full()
                    .h(px(8.))
                    .rounded_md()
                    .bg(rgb(0x1c2030))
                    .child(
                        canvas(
                            |_, _, _| (),
                            move |bounds, (), window, _| {
                                let mut filled = bounds;
                                filled.size.width = bounds.size.width * progress;
                                window.paint_shader_quad(filled, seek_material);
                            },
                        )
                        .size_full(),
                    ),
            )
            .child(
                div()
                    .flex()
                    .flex_row()
                    .justify_between()
                    .text_sm()
                    .text_color(rgb(0x9aa3b2))
                    .child(div().child(elapsed_label))
                    .child(div().child(SharedString::from(format!(
                        "{} / {}",
                        format_clock(progress * TRACK_LENGTH_SECONDS),
                        total_label
                    )))),
            )
    }
}

fn run_example() {
    application().run(|cx: &mut App| {
        let bounds = Bounds::centered(None, size(px(720.), px(520.)), cx);
        cx.open_window(
            WindowOptions {
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                ..Default::default()
            },
            |_, cx| cx.new(|_| ShaderVisualizer::new()),
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
