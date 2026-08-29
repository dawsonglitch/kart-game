shader_type spatial;
render_mode cull_back, diffuse_lambert;
// Cel-shaded lighting: lighting response is banded into a few discrete steps instead
// of a smooth gradient, plus a soft fresnel rim-light for a "toy racer" pop, and an
// optional sharp specular highlight (metallic uniform) for glossy car paint. Used for
// kart body panels, the road, and scenery — not for glass/metal trim or emissive bits,
// which stay on plain StandardMaterial3D (see kart.tscn / track_builder.gd).

uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Defaults to solid white (hint_default_white) when no texture is assigned, so
// this is a no-op multiply for anything that doesn't set one (kart panels, most
// scenery) — only the road currently assigns a real texture here.
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform int band_count : hint_range(2, 4) = 3;
uniform float shadow_softness : hint_range(0.0, 0.3) = 0.08;
uniform float min_brightness : hint_range(0.0, 0.5) = 0.2; // never fully black — stays readable for kids
uniform float rim_amount : hint_range(0.0, 1.0) = 0.35;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// A sharp, bright highlight rather than PBR roughness — reads as glossy car paint
// without fighting the flat cel-shaded look. 0 = fully matte (road, scenery).
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular_sharpness : hint_range(1.0, 128.0) = 48.0;
// Flat additional glow on top of albedo_color, independent of lighting — used for
// the kart's underglow strip so it lights up in the player's own chosen color.
uniform float emission_boost : hint_range(0.0, 3.0) = 0.0;

void fragment() {
	vec3 tex_color = texture(albedo_texture, UV * uv_scale).rgb;
	ALBEDO = albedo_color.rgb * COLOR.rgb * tex_color; // COLOR carries per-instance MultiMesh tint (e.g. flowers); white otherwise
	ALPHA = albedo_color.a;

	vec3 view = normalize(VIEW);
	float rim = 1.0 - clamp(dot(NORMAL, view), 0.0, 1.0);
	rim = pow(rim, rim_power) * rim_amount;
	EMISSION = rim_color.rgb * rim + albedo_color.rgb * emission_boost;
}

void light() {
	float ndotl = clamp(dot(NORMAL, LIGHT), 0.0, 0.999);
	float lit = smoothstep(0.0, shadow_softness, ndotl);
	float banded = floor(lit * float(band_count)) / float(band_count - 1);
	banded = max(banded, min_brightness);
	DIFFUSE_LIGHT += ALBEDO * banded * LIGHT_COLOR * ATTENUATION;

	if (metallic > 0.0) {
		vec3 half_vec = normalize(LIGHT + VIEW);
		float spec = pow(max(dot(NORMAL, half_vec), 0.0), specular_sharpness);
		SPECULAR_LIGHT += LIGHT_COLOR * spec * metallic * ATTENUATION;
	}
}
