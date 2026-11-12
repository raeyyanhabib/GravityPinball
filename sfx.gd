extends RefCounted
class_name Sfx

# Builds short tones in code, so there are no audio files to ship.
const RATE := 22050

# A tone that slides from one pitch to another and fades out
static func tone(from_hz: float, to_hz: float, seconds: float, volume: float = 0.3) -> AudioStreamWAV:
	var count := int(RATE * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)           # 16-bit samples, 2 bytes each
	var phase := 0.0
	for i in range(count):
		var t := float(i) / float(count)
		phase += TAU * lerpf(from_hz, to_hz, t) / float(RATE)
		var sample := sin(phase) * (1.0 - t) * volume   # fade out so it doesn't click
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	return stream
