package exif

import (
	"bytes"
	"encoding/binary"
	"errors"
	"hash/crc32"
	"image"
	"image/color"
	"image/gif"
	"image/jpeg"
	"image/png"
	"testing"
)

const (
	testMaxLongSide = 2048
	testQuality     = 85
	testMaxPixels   = 40_000_000
)

func solidImage(w, h int) *image.RGBA {
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			img.Set(x, y, color.RGBA{R: uint8(x), G: uint8(y), B: 90, A: 255})
		}
	}
	return img
}

func encodeJPEG(t *testing.T, img image.Image) []byte {
	t.Helper()
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 90}); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func encodePNG(t *testing.T, img image.Image) []byte {
	t.Helper()
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

// withSegments puts the given marker segments straight after SOI.
func withSegments(jpg []byte, segs ...seg) []byte {
	var buf bytes.Buffer
	buf.Write(jpg[:2])
	for _, s := range segs {
		buf.Write([]byte{0xFF, s.marker})
		var n [2]byte
		binary.BigEndian.PutUint16(n[:], uint16(len(s.payload)+2))
		buf.Write(n[:])
		buf.Write(s.payload)
	}
	buf.Write(jpg[2:])
	return buf.Bytes()
}

func pngChunk(typ string, data []byte) []byte {
	var buf bytes.Buffer
	var n [4]byte
	binary.BigEndian.PutUint32(n[:], uint32(len(data)))
	buf.Write(n[:])
	buf.WriteString(typ)
	buf.Write(data)
	crc := crc32.NewIEEE()
	crc.Write([]byte(typ))
	crc.Write(data)
	binary.BigEndian.PutUint32(n[:], crc.Sum32())
	buf.Write(n[:])
	return buf.Bytes()
}

// markers walks a JPEG's marker segments up to SOS and returns every marker
// seen, ending with SOS and the trailing EOI.
func markers(t *testing.T, b []byte) []byte {
	t.Helper()
	if len(b) < 4 || b[0] != 0xFF || b[1] != 0xD8 {
		t.Fatalf("output does not start with SOI")
	}
	out := []byte{0xD8}
	i := 2
	for i+4 <= len(b) {
		if b[i] != 0xFF {
			t.Fatalf("expected a marker at offset %d, got %#x", i, b[i])
		}
		m := b[i+1]
		out = append(out, m)
		n := int(binary.BigEndian.Uint16(b[i+2 : i+4]))
		i += 2 + n
		if m == 0xDA {
			break
		}
	}
	if b[len(b)-2] != 0xFF || b[len(b)-1] != 0xD9 {
		t.Fatalf("output does not end with EOI")
	}
	return append(out, 0xD9)
}

func TestReencodeJPEG_DropsEveryMetadataSegment(t *testing.T) {
	exifPayload := append([]byte("Exif\x00\x00"), []byte("MM\x00*GPSLatitude 51.5074 GPSLongitude -0.1278")...)
	in := withSegments(encodeJPEG(t, solidImage(64, 48)),
		seg{marker: 0xE1, payload: exifPayload},
		seg{marker: 0xE2, payload: []byte("ICC_PROFILE\x00\x01\x01profile")},
		seg{marker: 0xED, payload: []byte("Photoshop 3.0\x00IPTC")},
		seg{marker: 0xFE, payload: []byte("a comment with a GPS fix")},
	)

	out, w, h, err := ReencodeJPEG(in, testMaxLongSide, testQuality, testMaxPixels)
	if err != nil {
		t.Fatalf("ReencodeJPEG: %v", err)
	}
	if w != 64 || h != 48 {
		t.Fatalf("size = %dx%d, want 64x48", w, h)
	}
	allowed := map[byte]bool{0xD8: true, 0xDB: true, 0xC0: true, 0xC4: true, 0xDA: true, 0xD9: true}
	for _, m := range markers(t, out) {
		if !allowed[m] {
			t.Fatalf("output carries marker 0xFF%02X; only SOI, DQT, SOF0, DHT, SOS and EOI may remain", m)
		}
	}
	for _, needle := range []string{"Exif", "GPS", "ICC_PROFILE", "Photoshop", "comment"} {
		if bytes.Contains(out, []byte(needle)) {
			t.Fatalf("output still contains %q", needle)
		}
	}
}

func TestReencodeJPEG_PNGWithTextChunkBecomesACleanJPEG(t *testing.T) {
	raw := encodePNG(t, solidImage(30, 20))
	// Signature (8) + IHDR chunk (4 + 4 + 13 + 4).
	const afterIHDR = 8 + 25
	var in []byte
	in = append(in, raw[:afterIHDR]...)
	in = append(in, pngChunk("tEXt", []byte("Comment\x00GPS 51.5074,-0.1278"))...)
	in = append(in, raw[afterIHDR:]...)
	if _, err := png.Decode(bytes.NewReader(in)); err != nil {
		t.Fatalf("fixture is not a valid PNG: %v", err)
	}

	out, w, h, err := ReencodeJPEG(in, testMaxLongSide, testQuality, testMaxPixels)
	if err != nil {
		t.Fatalf("ReencodeJPEG: %v", err)
	}
	if !IsJPEG(out) {
		t.Fatal("a PNG must come out as a JPEG")
	}
	if w != 30 || h != 20 {
		t.Fatalf("size = %dx%d, want 30x20", w, h)
	}
	if bytes.Contains(out, []byte("GPS")) || bytes.Contains(out, []byte("tEXt")) {
		t.Fatal("output still carries the text chunk")
	}
}

func TestReencodeJPEG_TransparentPNGComesOutOnWhite(t *testing.T) {
	out, _, _, err := ReencodeJPEG(encodePNG(t, image.NewNRGBA(image.Rect(0, 0, 8, 8))),
		testMaxLongSide, testQuality, testMaxPixels)
	if err != nil {
		t.Fatalf("ReencodeJPEG: %v", err)
	}
	img, err := jpeg.Decode(bytes.NewReader(out))
	if err != nil {
		t.Fatal(err)
	}
	r, g, b, _ := img.At(4, 4).RGBA()
	if r>>8 < 250 || g>>8 < 250 || b>>8 < 250 {
		t.Fatalf("transparent pixel came out as %d,%d,%d, want white", r>>8, g>>8, b>>8)
	}
}

// The header alone declares a 10000 x 10000 image: refused before any pixel
// buffer is allocated, which the absent IDAT proves (a decode would fail with
// a different error).
func TestReencodeJPEG_RefusesOversizeDimensionsFromTheHeader(t *testing.T) {
	ihdr := make([]byte, 13)
	binary.BigEndian.PutUint32(ihdr[0:4], 10000)
	binary.BigEndian.PutUint32(ihdr[4:8], 10000)
	ihdr[8] = 8 // bit depth
	ihdr[9] = 2 // truecolour
	var in []byte
	in = append(in, "\x89PNG\r\n\x1a\n"...)
	in = append(in, pngChunk("IHDR", ihdr)...)
	in = append(in, pngChunk("IEND", nil)...)

	_, _, _, err := ReencodeJPEG(in, testMaxLongSide, testQuality, testMaxPixels)
	if !errors.Is(err, ErrImageTooLarge) {
		t.Fatalf("err = %v, want ErrImageTooLarge", err)
	}
}

func TestReencodeJPEG_RefusesOverThePixelLimitExactly(t *testing.T) {
	in := encodeJPEG(t, solidImage(10, 10))
	if _, _, _, err := ReencodeJPEG(in, testMaxLongSide, testQuality, 99); !errors.Is(err, ErrImageTooLarge) {
		t.Fatalf("100 px against a 99 px limit: err = %v", err)
	}
	if _, _, _, err := ReencodeJPEG(in, testMaxLongSide, testQuality, 100); err != nil {
		t.Fatalf("100 px against a 100 px limit: %v", err)
	}
}

// image/gif is imported by this test file, so the GIF decoder IS registered:
// the refusal is by format name, not by an absent decoder.
func TestReencodeJPEG_RefusesGarbageAndOtherFormats(t *testing.T) {
	var g bytes.Buffer
	pal := image.NewPaletted(image.Rect(0, 0, 4, 4), []color.Color{color.Black, color.White})
	if err := gif.Encode(&g, pal, nil); err != nil {
		t.Fatal(err)
	}
	cases := map[string][]byte{
		"nil":       nil,
		"garbage":   []byte("definitely not an image"),
		"gif":       g.Bytes(),
		"jpeg soi":  {0xFF, 0xD8, 0xFF, 0xD9},
		"png magic": []byte("\x89PNG\r\n\x1a\n"),
	}
	for name, in := range cases {
		if _, _, _, err := ReencodeJPEG(in, testMaxLongSide, testQuality, testMaxPixels); !errors.Is(err, ErrUnsupportedImage) {
			t.Errorf("%s: err = %v, want ErrUnsupportedImage", name, err)
		}
	}
}

func TestReencodeJPEG_ScalesTheLongEdgeAndNeverUpscales(t *testing.T) {
	cases := []struct {
		name         string
		w, h, max    int
		wantW, wantH int
	}{
		{"landscape", 400, 300, 200, 200, 150},
		{"portrait", 300, 400, 200, 150, 200},
		{"square", 300, 300, 100, 100, 100},
		{"small is kept", 50, 40, 200, 50, 40},
		{"at the limit is kept", 200, 100, 200, 200, 100},
		{"thin strip clamps to one pixel", 1000, 2, 100, 100, 1},
		{"tall strip clamps to one pixel", 2, 1000, 100, 1, 100},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			out, w, h, err := ReencodeJPEG(encodePNG(t, solidImage(c.w, c.h)), c.max, testQuality, testMaxPixels)
			if err != nil {
				t.Fatalf("ReencodeJPEG: %v", err)
			}
			if w != c.wantW || h != c.wantH {
				t.Fatalf("reported %dx%d, want %dx%d", w, h, c.wantW, c.wantH)
			}
			cfg, err := jpeg.DecodeConfig(bytes.NewReader(out))
			if err != nil {
				t.Fatalf("output does not decode: %v", err)
			}
			if cfg.Width != w || cfg.Height != h {
				t.Fatalf("output decodes to %dx%d, reported %dx%d", cfg.Width, cfg.Height, w, h)
			}
		})
	}
}

func TestReencodeJPEG_RejectsNonPositiveLimits(t *testing.T) {
	in := encodeJPEG(t, solidImage(4, 4))
	if _, _, _, err := ReencodeJPEG(in, 0, testQuality, testMaxPixels); err == nil {
		t.Fatal("maxLongSide 0 accepted")
	}
	if _, _, _, err := ReencodeJPEG(in, testMaxLongSide, testQuality, 0); err == nil {
		t.Fatal("maxPixels 0 accepted")
	}
}
