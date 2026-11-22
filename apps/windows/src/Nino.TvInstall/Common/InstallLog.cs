// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Text;

namespace Nino.TvInstall;

/// <summary>
/// TV kurulum günlüğü (<c>tvinstall.log</c>). Satır: <c>[yyyy-MM-dd HH:mm:ss] ileti</c> (yerel saat).
/// 1 MiB'ı geçince eski yarısı atılır. Yazılamazsa kurulum sürer. Yol yoksa hiçbir şey yazılmaz.
/// </summary>
public sealed class InstallLog
{
    public const long MaxBytes = 1_048_576;
    static readonly Lock Gate = new();

    public InstallLog(string? path) => Path = string.IsNullOrWhiteSpace(path) ? null : path;

    /// <summary>Hiçbir şey yazmayan günlük.</summary>
    public static InstallLog None { get; } = new(null);

    public string? Path { get; }

    public void Write(string message)
    {
        if (Path is null) return;
        var entry = "[" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "] " + message.TrimEnd() + "\n";
        lock (Gate)
        {
            try
            {
                var dir = System.IO.Path.GetDirectoryName(Path);
                if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
                var current = new FileInfo(Path);
                if (current.Exists && current.Length > MaxBytes)
                {
                    var text = File.ReadAllText(Path, Encoding.UTF8);
                    var cut = text.IndexOf('\n', text.Length / 2);
                    File.WriteAllText(Path, cut < 0 ? "" : text[(cut + 1)..], new UTF8Encoding(false));
                }
                File.AppendAllText(Path, entry, new UTF8Encoding(false));
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }
}
