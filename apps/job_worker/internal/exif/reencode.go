package exif

import (
	"bytes"
	"errors"
	"fmt"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"

	"golang.org/x/image/draw"
)

// ErrUnsupportedImage is returned by ReencodeJPEG for input that is not a
// JPEG or a PNG, or whose header cannot be read.
var ErrUnsupportedImage = errors.New("exif: not a JPEG or PNG")

// ErrImageTooLarge is returned by ReencodeJPEG when the header declares more
// pixels than the caller allows. Nothing past the header is decoded.
var ErrImageTooLarge = errors.New("exif: image dimensions over the limit")

// ReencodeJPEG decodes a JPEG or PNG to pixels and encodes a new baseline
// JPEG from them, so nothing of the input file but its pixels survives: no
// EXIF, XMP, IPTC, ICC profile, comment, text chunk or trailing bytes, in any
// segment or chunk type, known or not. It is the direct-message image path's
// metadata guarantee (issue #1216), where StripJPEG's marker list would be a
// list of things to remember.
//
// The header is read first and the image refused, without decoding, when it
// is neither JPEG nor PNG or declares more than maxPixels pixels: a small
// file can declare dimensions whose decode buffer would exhaust the worker.
// The format is checked by name rather than trusting the global decoder
// registry, which another package in the binary may have widened.
//
// The output's long edge is at most maxLongSide (never upscaled; each side
// at least 1 px) and it is always drawn into a fresh RGBA over white, so a
// transparent PNG comes out on white rather than black.
func ReencodeJPEG(in []byte, maxLongSide, quality, maxPixels int) (out []byte, w, h int, err error) {
	if maxLongSide <= 0 || maxPixels <= 0 {
		return nil, 0, 0, fmt.Errorf("exif: maxLongSide and maxPixels must be > 0")
	}
	cfg, format, err := image.DecodeConfig(bytes.NewReader(in))
	if err != nil {
		return nil, 0, 0, ErrUnsupportedImage
	}
	if format != "jpeg" && format != "png" {
		return nil, 0, 0, ErrUnsupportedImage
	}
	if cfg.Width <= 0 || cfg.Height <= 0 || int64(cfg.Width)*int64(cfg.Height) > int64(maxPixels) {
		return nil, 0, 0, ErrImageTooLarge
	}

	var src image.Image
	if format == "jpeg" {
		src, err = jpeg.Decode(bytes.NewReader(in))
	} else {
		src, err = png.Decode(bytes.NewReader(in))
	}
	if err != nil {
		return nil, 0, 0, fmt.Errorf("exif: %s decode: %w", format, err)
	}

	sb := src.Bounds()
	srcW, srcH := sb.Dx(), sb.Dy()
	if srcW <= 0 || srcH <= 0 {
		return nil, 0, 0, ErrUnsupportedImage
	}
	w, h = srcW, srcH
	if srcW >= srcH && srcW > maxLongSide {
		w = maxLongSide
		h = max(1, int(int64(srcH)*int64(maxLongSide)/int64(srcW)))
	} else if srcH > srcW && srcH > maxLongSide {
		h = maxLongSide
		w = max(1, int(int64(srcW)*int64(maxLongSide)/int64(srcH)))
	}

	dst := image.NewRGBA(image.Rect(0, 0, w, h))
	draw.Draw(dst, dst.Bounds(), image.NewUniform(color.White), image.Point{}, draw.Src)
	if w == srcW && h == srcH {
		draw.Draw(dst, dst.Bounds(), src, sb.Min, draw.Over)
	} else {
		draw.CatmullRom.Scale(dst, dst.Bounds(), src, sb, draw.Over, nil)
	}

	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, dst, &jpeg.Options{Quality: quality}); err != nil {
		return nil, 0, 0, fmt.Errorf("exif: jpeg encode: %w", err)
	}
	return buf.Bytes(), w, h, nil
}
