// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Linux.Hosting;

namespace Nino.Linux.Tests;

public sealed class JournalTests
{
    [Fact]
    public void SatirBicimiVeKonsol()
    {
        var console = new StringWriter();
        var journal = new Journal(console, () => new DateTime(2026, 11, 22, 9, 5, 7));
        journal.Write("panel", "hazır");
        Assert.Equal("[09:05:07] [panel] hazır", journal.Recent().Single());
        Assert.Contains("[09:05:07] [panel] hazır", console.ToString());
    }

    [Fact]
    public void YalnizSonDortYuzSatirKalir()
    {
        var journal = new Journal();
        for (var i = 0; i < Journal.Capacity + 25; i++) journal.Write("t", i.ToString());
        var lines = journal.Recent();
        Assert.Equal(Journal.Capacity, lines.Length);
        Assert.EndsWith("] 25", lines[0]);
        Assert.EndsWith($"] {Journal.Capacity + 24}", lines[^1]);
    }
}

public sealed class SerialWorkerTests
{
    [Fact]
    public async Task IslerTekIsParcacigindaVeAwaitSonrasiDaOrada()
    {
        using var worker = new SerialWorker();
        var threads = new HashSet<int>();
        await worker.Invoke(async () =>
        {
            threads.Add(Environment.CurrentManagedThreadId);
            await Task.Delay(10);
            threads.Add(Environment.CurrentManagedThreadId);
            await Task.Yield();
            threads.Add(Environment.CurrentManagedThreadId);
        });
        await worker.Invoke(() => { threads.Add(Environment.CurrentManagedThreadId); });
        Assert.Single(threads);
    }

    [Fact]
    public async Task SiraKorunur()
    {
        using var worker = new SerialWorker();
        var seen = new List<int>();
        var all = Enumerable.Range(0, 100).Select(i => worker.Invoke(() => seen.Add(i))).ToArray();
        await Task.WhenAll(all);
        Assert.Equal(Enumerable.Range(0, 100), seen);
    }

    [Fact]
    public async Task HataCagiranaDoner()
    {
        using var worker = new SerialWorker();
        await Assert.ThrowsAsync<InvalidOperationException>(() => worker.Invoke(new Func<int>(() => throw new InvalidOperationException("x"))));
        await Assert.ThrowsAsync<TimeoutException>(() => worker.Invoke(async () => { await Task.Yield(); throw new TimeoutException(); }));
        Assert.Equal(3, await worker.Invoke(() => 3));
    }

    [Fact]
    public async Task KapaninceGelenIsDuserBeklenenHataAlir()
    {
        var worker = new SerialWorker();
        worker.Dispose();
        worker.Enqueue(() => throw new InvalidOperationException("çalışmamalı"));
        await Assert.ThrowsAsync<ObjectDisposedException>(() => worker.Invoke(() => 1));
    }

    [Fact]
    public async Task SendKendiIcindenCagrilincaKilitlenmez()
    {
        using var worker = new SerialWorker();
        var result = await worker.Invoke(() =>
        {
            var value = 0;
            SynchronizationContext.Current!.Send(_ => value = 42, null);
            return value;
        });
        Assert.Equal(42, result);
    }
}

public sealed class DataFolderTests
{
    [Fact]
    public void DosyaAdlari()
    {
        var data = new DataFolder("/data");
        Assert.Equal("/data/secure.json", data.SecretsFile);
        Assert.Equal("/data/settings.json", data.SettingsFile);
        Assert.Equal("/data/models", data.ModelsFolder);
        Assert.Equal("/data/remoteplay.log", data.RemotePlayLog);
        Assert.Equal("/data/tvinstall.log", data.TvInstallLog);
    }
}

public sealed class SleepWatchTests
{
    [Fact]
    public void DuvarSaatiTekduzeSaattenKacinca()
    {
        long mono = 1_000;
        var wall = new DateTimeOffset(2026, 11, 22, 23, 0, 0, TimeSpan.Zero);
        var watch = new SleepWatch(() => mono, () => wall);

        mono += 5_000; wall += TimeSpan.FromSeconds(5);
        Assert.Null(watch.Check());                       // olağan 5 sn

        mono += 5_000; wall += TimeSpan.FromSeconds(12);
        Assert.Null(watch.Check());                       // küçük kayma: saat düzeltmesi

        mono += 5_000; wall += TimeSpan.FromMinutes(40);
        Assert.Equal(TimeSpan.FromMinutes(40) - TimeSpan.FromSeconds(5), watch.Check());

        mono += 5_000; wall += TimeSpan.FromSeconds(5);
        Assert.Null(watch.Check());                       // uyanıştan sonra yine olağan
    }
}
