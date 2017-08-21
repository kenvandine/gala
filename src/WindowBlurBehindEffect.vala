//
//  Copyright (C) 2015 Deepin Technology Co., Ltd.
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.

using Clutter;

const string BLUR_SHADER_FRAG_H_CODE = """
uniform sampler2D texture;
uniform int width;
uniform float radius;
uniform float bloom;
void main()
{
	float v;
	float pi = 3.141592653589793;
	float e_step = 1.0 / width;
	float rel_radius = radius;
	if (rel_radius < 0) rel_radius = 0;
	int steps = int(min(rel_radius * 0.7, sqrt(rel_radius) * pi));
	float r = rel_radius / steps;
	float t = bloom / (steps * 2 + 1);
	float x = cogl_tex_coord_in[0].x;
	float y = cogl_tex_coord_in[0].y;
	vec4 sum = texture2D(texture, vec2(x, y)) * t;
	int i;
	for(i = 1; i <= steps; i++){
		v = (cos(i / (steps + 1) / pi) + 1) * 0.5;
		sum += texture2D(texture, vec2(x + i * e_step * r, y)) * v * t;
		sum += texture2D(texture, vec2(x - i * e_step * r, y)) * v * t;
	}
	cogl_color_out = sum;
}
""";

const string BLUR_SHADER_FRAG_V_CODE = """
// Fragment Shader vertical
uniform sampler2D texture;
uniform int height;
uniform float radius;
uniform float bloom;
void main()
{
	float v;
	float pi = 3.141592653589793;
	float e_step = 1.0 / height;
	float rel_radius = radius;
	if (rel_radius < 0) rel_radius = 0;
	int steps = int(min(rel_radius * 0.7, sqrt(rel_radius) * pi));
	float r = rel_radius / steps;
	float t = bloom / (steps * 2 + 1);
	float x = cogl_tex_coord_in[0].x;
	float y = cogl_tex_coord_in[0].y;
	vec4 sum = texture2D(texture, vec2(x, y)) * t;
	int i;
	for(i = 1; i <= steps; i++){
		v = (cos(i / (steps + 1) / pi) + 1) * 0.5;
		sum += texture2D(texture, vec2(x, y + i * e_step * r)) * v * t;
		sum += texture2D(texture, vec2(x, y - i * e_step * r)) * v * t;
	}
	cogl_color_out = sum;
}
""";

namespace Gala
{
	public class WindowBlurBehindEffect : Clutter.Effect {
		public Meta.Window window { get; construct; }
		public float radius { get; construct; }

		Cogl.Program h_program;
		Cogl.Program v_program;
		Cogl.Material material;
		
		public WindowBlurBehindEffect (Meta.Window window, float radius)
		{
			Object (window: window, radius: radius);
		}

		construct
		{
			h_program = new Cogl.Program ();
			v_program = new Cogl.Program ();
			material = new Cogl.Material ();

			var shader = new Cogl.Shader (Cogl.ShaderType.FRAGMENT);
			shader.source (BLUR_SHADER_FRAG_H_CODE);
			shader.compile ();
			h_program.attach_shader (shader);
			h_program.link ();

			shader = new Cogl.Shader (Cogl.ShaderType.FRAGMENT);
			shader.source (BLUR_SHADER_FRAG_V_CODE);
			shader.compile ();
			v_program.attach_shader (shader);
			v_program.link ();
			
			int uniform_no;
			uniform_no = h_program.get_uniform_location ("texture");
			CoglFixes.set_uniform_1i (h_program, uniform_no, 0);
			uniform_no = h_program.get_uniform_location ("radius");
			CoglFixes.set_uniform_1f (h_program, uniform_no, radius);
			uniform_no = h_program.get_uniform_location ("bloom");
			CoglFixes.set_uniform_1f (h_program, uniform_no, 1.0f);

			uniform_no = v_program.get_uniform_location ("texture");
			CoglFixes.set_uniform_1i (v_program, uniform_no, 0);
			uniform_no = v_program.get_uniform_location ("radius");
			CoglFixes.set_uniform_1f (v_program, uniform_no, radius);
			uniform_no = v_program.get_uniform_location ("bloom");
			CoglFixes.set_uniform_1f (v_program, uniform_no, 1.0f);
		}

		private Meta.Rectangle get_window_area ()
		{
			return window.get_frame_rect ();
		}

		private Meta.Rectangle get_blur_area (Meta.Rectangle window_area)
		{
			return {
				window_area.x - (int)radius,
				window_area.y - (int)radius,
				window_area.width + (int)radius * 2,
				window_area.height + (int)radius * 2
			};
		}

		private void update_size (int new_width, int new_height)
		{
			int uniform_no;
			
			uniform_no = h_program.get_uniform_location ("width");
			CoglFixes.set_uniform_1i (h_program, uniform_no, new_width);
			
			uniform_no = v_program.get_uniform_location ("height");
			CoglFixes.set_uniform_1i (v_program, uniform_no, new_height);
		}

		public override void paint (Clutter.EffectPaintFlags flags)
		{
			// TODO: cache all this
			Meta.Rectangle window_area = get_window_area ();
			Meta.Rectangle blur_area = get_blur_area (window_area);

			int screen_width, screen_height;

			var screen = window.get_screen ();
			screen.get_size (out screen_width, out screen_height);

			float aspect = screen_width / screen_height;

			update_size (blur_area.width, blur_area.height);

			var perspective = actor.get_stage ().get_perspective ();

			var scene = read_framebuffer (blur_area.x, blur_area.y, blur_area.width, blur_area.height);
			var format = scene.get_format ();

			// Apply horizontal blur
			var h_blur  = new Cogl.Texture.with_size (blur_area.width, blur_area.height, Cogl.TextureFlags.NONE, format);
			var h_fbo = new Cogl.Offscreen.to_texture (h_blur);

			Cogl.push_framebuffer ((Cogl.Framebuffer)h_fbo);
			setup_viewport (blur_area.width, blur_area.height, perspective.fovy, aspect, perspective.z_near, perspective.z_far);

			material.set_layer (0, scene);
			CoglFixes.set_user_program (material, h_program);
			Cogl.set_source (material);
			
			Cogl.rectangle (0, 0, blur_area.width, blur_area.height);
			Cogl.pop_framebuffer ();

			// Apply vertical blur
			var v_blur  = new Cogl.Texture.with_size (blur_area.width, blur_area.height, Cogl.TextureFlags.NONE, format);
			var v_fbo = new Cogl.Offscreen.to_texture (v_blur);

			Cogl.push_framebuffer ((Cogl.Framebuffer)v_fbo);
			setup_viewport (blur_area.width, blur_area.height, perspective.fovy, aspect, perspective.z_near, perspective.z_far);

			material.set_layer (0, h_blur);
			CoglFixes.set_user_program (material, v_program);
			Cogl.set_source (material);
			
			Cogl.rectangle (0, 0, blur_area.width, blur_area.height);
			Cogl.pop_framebuffer ();

			var blurred = new Cogl.Texture.from_sub_texture (v_blur, (int)radius, (int)radius, window_area.width, window_area.height);

			// A GTK+3 window usually has a shadow drawn on the client side so we calculate
			// only the actual window frame position
			int xoff = window_area.x - (int)actor.get_x ();
			int yoff = window_area.y - (int)actor.get_y ();

			// Draw the final texture
			Cogl.set_source_texture (blurred);
			Cogl.rectangle (xoff, yoff, window_area.width + xoff, window_area.height + yoff);

			actor.continue_paint ();
		}

		private static Cogl.Texture read_framebuffer (int x, int y, int width, int height) {
			unowned Clutter.Backend backend = Clutter.get_default_backend ();
			unowned Cogl.Context context = Clutter.backend_get_cogl_context (backend);
			
			var image = new Cairo.ImageSurface (Cairo.Format.ARGB32, width, height);
			var bitmap = Cogl.bitmap_new_for_data (context, width, height, Cogl.PixelFormat.BGRA_8888_PRE, image.get_stride (), image.get_data ());
			Cogl.framebuffer_read_pixels_into_bitmap (Cogl.get_draw_framebuffer (), x, y, Cogl.ReadPixelsFlags.BUFFER, bitmap);

			var texture = new Cogl.Texture.from_bitmap (bitmap, Cogl.TextureFlags.NONE, Cogl.PixelFormat.BGRA_8888_PRE);
			return texture;
		}

		// Translate GL coordinates to Clutter coordinate space
		private static void setup_viewport (int width, int height, float fovy, float aspect, float z_near, float z_far) {
			Cogl.set_viewport (0, 0, width, height);
			Cogl.perspective (fovy, aspect, z_near, z_far);

			Cogl.Matrix pmat;
			CoglFixes.get_projection_matrix (out pmat);
			float z_camera = 0.5f * (float)pmat.xx;

			var matrix = Cogl.Matrix.identity ();
			matrix.translate (-0.5f, -0.5f, -z_camera);
			matrix.scale (1.0f / width, -1.0f / height, 1.0f / width);
			matrix.translate (0.0f, -1.0f * height, 0.0f);
			Cogl.set_modelview_matrix (matrix);
		}
	}
}
