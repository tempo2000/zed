#![cfg_attr(target_family = "wasm", no_main)]

use std::sync::Arc;
use std::time::Instant;

use gpui::{
    App, Bounds, Context, Render, ShaderMaterial, ShaderSource, ShaderUniforms, SharedString,
    Window, WindowBounds, WindowOptions, canvas, div, prelude::*, px, rgb, size,
};
use gpui_platform::application;

const TRACK_LENGTH_SECONDS: f32 = 240.0;
const PEAK_COUNT: usize = 64;
const LAYOUT_HASH: u64 = 0x0A17_BEEF;

struct ShaderVisualizer {
    started_at: Instant,
    now_playing: SharedString,
    artist: SharedString,
    progress: f32,
    bass: f32,
    mid: f32,
    treble: f32,
    peaks: Vec<f32>,
}

impl ShaderVisualizer {
    fn new() -> Self {
        Self {
            started_at: Instant::now(),
            now_playing: SharedString::from("Aurora Drift"),
            artist: SharedString::from("Lumen Trails"),
            progress: 0.0,
            bass: 0.0,
            mid: 0.0,
            treble: 0.0,
            peaks: vec![0.0; PEAK_COUNT],
        }
    }

    fn update_signals(&mut self, time: f32) {
        self.progress = (time % TRACK_LENGTH_SECONDS) / TRACK_LENGTH_SECONDS;

        let bass = 0.5 + 0.5 * (time * 1.7).sin();
        let mid = 0.5 + 0.5 * (time * 2.3 + 1.2).cos();
        let treble = 0.5 + 0.5 * (time * 3.1 + 2.4).sin() * (time * 0.9).cos();

        self.bass = bass.clamp(0.0, 1.0);
        self.mid = mid.clamp(0.0, 1.0);
        self.treble = treble.clamp(0.0, 1.0);

        for (index, peak) in self.peaks.iter_mut().enumerate() {
            let normalized = index as f32 / PEAK_COUNT as f32;
            let value = 0.5
                + 0.5
                    * ((time * 2.0 + normalized * 12.0).sin()
                        * (time * 0.7 + normalized * 4.0).cos());
            *peak = value.clamp(0.0, 1.0);
        }
    }

    fn build_uniform_bytes(&self, time: f32) -> Arc<[u8]> {
        let mut buffer: Vec<u8> = Vec::with_capacity((6 + PEAK_COUNT) * 4);
        let scalars = [time, self.progress, self.bass, self.mid, self.treble, 0.0];
        for value in scalars {
            buffer.extend_from_slice(&value.to_ne_bytes());
        }
        for peak in &self.peaks {
            buffer.extend_from_slice(&peak.to_ne_bytes());
        }
        Arc::from(buffer.into_boxed_slice())
    }

    fn shader_material(
        &self,
        shader_name: &'static str,
        time: f32,
        corner_radius: f32,
    ) -> ShaderMaterial {
        ShaderMaterial {
            shader: ShaderSource::BuiltIn(SharedString::from(shader_name)),
            uniforms: ShaderUniforms {
                bytes: self.build_uniform_bytes(time),
                layout_hash: LAYOUT_HASH,
            },
            corner_radii: px(corner_radius).into(),
            time,
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
        let bars_material = self.shader_material("spectrum_bars", time, 10.0);
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
