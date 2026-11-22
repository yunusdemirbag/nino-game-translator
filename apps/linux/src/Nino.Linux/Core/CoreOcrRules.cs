// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core.Imaging;
using Nino.Core.Reading;
using Nino.Linux.Imaging;
using Nino.Linux.Ocr;
using CoreReading = Nino.Core.Reading.OcrReading;
using CoreLine = Nino.Core.Reading.OcrLine;

namespace Nino.Linux.Core;

/// <summary>Tesseract okuyucusunun kurallarını ortak çekirdeğin işlevlerine yönlendirir (masaüstüyle aynı ölçüt).</summary>
public sealed class CoreOcrRules : IOcrRules
{
    public BgraPicture KeepWhiteText(BgraPicture picture) => Pictures.From(TextImageFilters.WhiteText(Pictures.ToFrame(picture)));

    public BgraPicture Enlarge(BgraPicture picture, int factor) => Pictures.From(Pictures.ToFrame(picture).Upscale(factor));

    public double WordLikeness(string text) => OcrJunk.Score(text);

    public bool IsSeparateText(double gap, double lineHeight, double imageWidth) =>
        WordLineSplitter.IsSeparateText(gap, lineHeight, imageWidth);
}

/// <summary>Linux'un kare türüyle çekirdeğinki arasında çeviri.</summary>
public static class Pictures
{
    public static BgraFrame ToFrame(BgraPicture picture) =>
        BgraFrame.CopyFrom(picture.Pixels, picture.Width, picture.Height, picture.Stride);

    public static BgraPicture From(BgraFrame frame) => BgraPicture.Packed(frame.Pixels, frame.Width, frame.Height);

    public static Box ToBox(OcrBox box) => new(box.Left, box.Top, box.Right, box.Bottom);

    public static CoreReading ToReading(Ocr.OcrReading reading) =>
        new(reading.Lines.Select(line => new CoreLine(line.Text, line.Box is { } box ? ToBox(box) : null)));
}
