// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Globalization;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;
using Nino.Core.Data;
using Nino.Core.Text;

namespace Nino.Core.Health;

/// <summary>Sorun türü (dosyada küçük harfle başlayan adla: <c>ps5Dropped</c> …).</summary>
[JsonConverter(typeof(JsonStringEnumConverter<ProblemKind>))]
public enum ProblemKind
{
    [JsonStringEnumMemberName("ps5Dropped")] Ps5Dropped,
    [JsonStringEnumMemberName("ps5Unreachable")] Ps5Unreachable,
    [JsonStringEnumMemberName("networkLost")] NetworkLost,
    [JsonStringEnumMemberName("tvDropped")] TvDropped,
}

/// <summary>
/// Kayıtlı bir sorun. Altyazı metni, PS5 adı ya da adres içermez.
/// </summary>
public sealed record ProblemRecord
{
    [JsonPropertyName("id")] public Guid Id { get; init; } = Guid.NewGuid();

    /// <summary>
    /// UTC zaman. Dosyada eski uygulama gibi <c>Z</c> ile yazılır (<c>2026-11-22T18:04:05.123Z</c>; kesir varsa en
    /// kısa haliyle); okurken her ISO-8601 biçimi kabul edilir.
    /// </summary>
    [JsonPropertyName("date")]
    [JsonConverter(typeof(UtcDateJson))]
    public DateTimeOffset Date { get; init; }

    [JsonPropertyName("kind")] public ProblemKind Kind { get; init; }

    /// <summary>Kopma nedeninin adı (ör. <c>NotFound</c>).</summary>
    [JsonPropertyName("reason")] public string? Reason { get; init; }

    /// <summary>O ana kadar akış dakikası; ölçüm yoksa yok.</summary>
    [JsonPropertyName("streamedMinutes")] public double? StreamedMinutes { get; init; }

    [JsonPropertyName("lossPerMinute")] public double? LossPerMinute { get; init; }
    [JsonPropertyName("stallsPerMinute")] public double? StallsPerMinute { get; init; }

    /// <summary>Ağ türünün sabit adı (<c>wifi</c>, <c>wired</c> …).</summary>
    [JsonPropertyName("network")] public string? Network { get; init; }

    /// <summary>Şu anki oyunun adı.</summary>
    [JsonPropertyName("game")] public string? Game { get; init; }

    /// <summary>Ekran dilindeki kısa ad.</summary>
    public string ShortName(ITextSource text) => text.Get(Kind switch
    {
        ProblemKind.Ps5Dropped => "health.problem.ps5Dropped",
        ProblemKind.Ps5Unreachable => "health.problem.ps5Unreachable",
        ProblemKind.NetworkLost => "health.problem.networkLost",
        _ => "health.problem.tvDropped",
    });

    /// <summary>Destek için Türkçe adı (ekran dilinden bağımsız).</summary>
    [JsonIgnore] // hesaplanan; dosyaya yazılmaz (eski dosyada yok)
    public string TurkishName => Kind switch
    {
        ProblemKind.Ps5Dropped => "PS5 ile bağlantı kesildi",
        ProblemKind.Ps5Unreachable => "PS5'e uzun süredir ulaşılamıyor",
        ProblemKind.NetworkLost => "bilgisayar ağdan düştü",
        _ => "TV ile bağlantı kesildi",
    };

    /// <summary>
    /// Destek satırı (Türkçe, yerel saatle):
    /// <c>gg.AA SS:dd ad (neden) · 27 dk oyun · ağ wifi · kayıp 12/dk, durma 0.4/dk · oyun</c>.
    /// </summary>
    public string SupportLine(TimeZoneInfo zone)
    {
        var local = TimeZoneInfo.ConvertTime(Date, zone);
        var head = local.ToString("dd.MM HH:mm", CultureInfo.InvariantCulture) + " " + TurkishName;
        if (!string.IsNullOrEmpty(Reason)) head += $" ({Reason})";
        var parts = new List<string> { head };
        if (StreamedMinutes is { } m)
            parts.Add($"{Math.Round(m, MidpointRounding.AwayFromZero).ToString("0", CultureInfo.InvariantCulture)} dk oynandı");
        if (!string.IsNullOrEmpty(Network)) parts.Add("ağ " + Network);
        if (LossPerMinute is { } loss && StallsPerMinute is { } stalls)
            parts.Add($"kayıp {Math.Round(loss, MidpointRounding.AwayFromZero).ToString("0", CultureInfo.InvariantCulture)}/dk, " +
                      $"durma {stalls.ToString("0.0", CultureInfo.InvariantCulture)}/dk");
        if (!string.IsNullOrEmpty(Game)) parts.Add(Game);
        return string.Join(" · ", parts);
    }
}

/// <summary>
/// Oturumlar arası kalan sorun listesi (<c>sorunlar.json</c>, JSON dizi, en yenisi sonda, en çok 40). Yol yoksa yalnız
/// bellekte tutulur. Okuma/yazma hataları sessizdir. Her iş parçacığından çağrılabilir.
/// </summary>
public sealed class ProblemLog
{
    /// <summary>Dosya adı (sağlık klasöründe).</summary>
    public const string FileName = "sorunlar.json";

    /// <summary>En çok kayıt.</summary>
    public const int MaxRecords = 40;

    internal static readonly JsonSerializerOptions Json = new()
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        WriteIndented = false,
    };

    readonly string? _path;
    readonly object _gate = new();
    readonly List<ProblemRecord> _records;

    /// <param name="path">Dosya yolu; null ise yalnız bellek (testler, Linux).</param>
    public ProblemLog(string? path)
    {
        _path = path;
        _records = Load(path);
    }

    /// <summary>Sağlık klasöründen kurar (klasör yoksa yalnız bellek).</summary>
    public static ProblemLog InFolder(string? healthFolder) =>
        new(healthFolder is null ? null : Path.Combine(healthFolder, FileName));

    /// <summary>Bütün kayıtlar (en eskisi önce).</summary>
    public IReadOnlyList<ProblemRecord> All
    {
        get { lock (_gate) return _records.ToArray(); }
    }

    /// <summary>Verilen andan (dahil) sonraki kayıtlar.</summary>
    public IReadOnlyList<ProblemRecord> Since(DateTimeOffset from)
    {
        lock (_gate) return _records.Where(r => r.Date >= from).ToArray();
    }

    /// <summary>En yeni <paramref name="count"/> kayıt, en yenisi önce (ekran listeleri için).</summary>
    public IReadOnlyList<ProblemRecord> Newest(int count)
    {
        lock (_gate) return Enumerable.Reverse(_records).Take(count).ToArray();
    }

    /// <summary>Kayıt ekler (fazlası baştan atılır) ve yazar.</summary>
    public void Add(ProblemRecord record)
    {
        lock (_gate)
        {
            _records.Add(record);
            if (_records.Count > MaxRecords) _records.RemoveRange(0, _records.Count - MaxRecords);
            Save();
        }
    }

    /// <summary>Listeyi boşaltır ve dosyayı siler.</summary>
    public void Clear()
    {
        lock (_gate)
        {
            _records.Clear();
            if (_path is null) return;
            try { File.Delete(_path); }
            catch (Exception e) when (FileIo.IsIoError(e)) { }
        }
    }

    void Save()
    {
        if (_path is null) return;
        try { FileIo.WriteAtomic(_path, JsonSerializer.Serialize(_records, Json)); }
        catch (Exception e) when (FileIo.IsIoError(e)) { }
    }

    static List<ProblemRecord> Load(string? path)
    {
        if (path is null) return [];
        try
        {
            if (!File.Exists(path)) return [];
            var list = JsonSerializer.Deserialize<List<ProblemRecord?>>(File.ReadAllText(path, FileIo.Utf8), Json);
            var records = list?.Where(r => r is not null).Select(r => r!).ToList() ?? [];
            return records.Count > MaxRecords ? records.GetRange(records.Count - MaxRecords, MaxRecords) : records;
        }
        catch (Exception e) when (e is JsonException or NotSupportedException || FileIo.IsIoError(e))
        {
            return [];
        }
    }
}

/// <summary>Tarihi UTC <c>DateTime</c> gibi (<c>…Z</c>) yazar; okurken ofsetli ya da ofsetsiz her ISO-8601'i UTC'ye çevirir.</summary>
sealed class UtcDateJson : JsonConverter<DateTimeOffset>
{
    public override DateTimeOffset Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var text = reader.GetString() ?? throw new JsonException("tarih yok");
        if (!DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var value))
            throw new JsonException("tarih okunamadı");
        return value.ToUniversalTime();
    }

    public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value.UtcDateTime);
}
