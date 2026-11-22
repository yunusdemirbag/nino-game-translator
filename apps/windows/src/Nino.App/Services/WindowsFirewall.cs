// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.IO;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Nino.Shell.Platform;
using Nino.Shell.WindowsRules;

namespace Nino.App.Services;

/// <summary>
/// Windows Güvenlik Duvarı (kimlikler-veri §11). Okuma yönetici istemez; kural yazma, uygulamanın kendini
/// <c>--configure-local-firewall</c> ile UAC (runas) altında gizli pencereyle yeniden başlatmasıyla olur. Kural
/// mantığı <see cref="FirewallLogic"/>'te (Nino.Shell, testli); burada yalnız COM okuma/yazma var.
/// </summary>
public sealed class WindowsFirewall : IFirewall
{
    readonly string _exePath;
    readonly Action<string>? _log;

    /// <param name="exePath">Bu <c>Nino.exe</c>'nin tam yolu (yoksa çalışan süreçten).</param>
    /// <param name="log">Hata günlüğü.</param>
    public WindowsFirewall(string? exePath = null, Action<string>? log = null)
    {
        _exePath = exePath ?? Environment.ProcessPath ?? "";
        _log = log;
    }

    /// <inheritdoc />
    public Task<bool> HasPrivateRuleAsync(CancellationToken cancellationToken = default) => Task.Run(() =>
    {
        try
        {
            var store = new ComFirewallStore();
            return new FirewallLogic(_exePath).HasPermission(store.ReadPolicy(), store.ReadRules());
        }
        catch (Exception e)
        {
            _log?.Invoke("Güvenlik duvarı kuralları okunamadı: " + e.Message);
            return false;
        }
    }, cancellationToken);

    /// <inheritdoc />
    public async Task<bool> AddRuleAsync(CancellationToken cancellationToken = default)
    {
        var exit = await Task.Run(() =>
        {
            try
            {
                using var process = Process.Start(new ProcessStartInfo(_exePath, FirewallNames.HelperArgument)
                {
                    UseShellExecute = true,
                    Verb = "runas", WindowStyle = ProcessWindowStyle.Hidden,
                    CreateNoWindow = true,
                });
                if (process is null) return -1;
                process.WaitForExit();
                return process.ExitCode;
            }
            catch (Win32Exception)
            {
                return -1; // UAC reddedildi.
            }
            catch (Exception e) when (e is InvalidOperationException or IOException)
            {
                _log?.Invoke("Güvenlik duvarı yardımcısı açılamadı: " + e.Message);
                return -1;
            }
        }, cancellationToken).ConfigureAwait(false);
        if (exit != 0) return false;
        return await HasPrivateRuleAsync(cancellationToken).ConfigureAwait(false);
    }

    /// <inheritdoc />
    public Task<bool> IsOnPublicNetworkAsync(CancellationToken cancellationToken = default) =>
        Task.Run(NetworkCategories.AnyConnectedPublic, cancellationToken);

    /// <summary>
    /// Yönetici yardımcı sürecinin işi (Program.Main'de, Velopack'ten önce, veri klasörüne dokunmadan): kuralları yazar;
    /// çıkış kodu başarıda 0, değilse 1.
    /// </summary>
    public static int RunHelper()
    {
        try
        {
            var exe = Environment.ProcessPath ?? "";
            return FirewallConfigurator.Configure(new ComFirewallStore(), new FirewallLogic(exe)) ? 0 : 1;
        }
        catch (Exception)
        {
            return 1;
        }
    }

    /// <summary>Velopack kaldırma öncesi kancası: bu exe'nin kurallarını sessizce siler.</summary>
    public static void RemoveOwnRules()
    {
        try
        {
            FirewallConfigurator.RemoveOwnRules(new ComFirewallStore(), new FirewallLogic(Environment.ProcessPath ?? ""));
        }
        catch (Exception) { }
    }
}

/// <summary>HNetCfg.FwPolicy2 / HNetCfg.FWRule COM nesneleriyle kural deposu.</summary>
sealed class ComFirewallStore : IFirewallStore
{
    const int PrivateProfile = 2;

    static dynamic Policy() =>
        Activator.CreateInstance(Type.GetTypeFromProgID("HNetCfg.FwPolicy2", throwOnError: true)!)!;

    public FirewallPolicyState ReadPolicy()
    {
        dynamic policy = Policy();
        try
        {
            bool enabled = policy.FirewallEnabled[PrivateProfile];
            bool blockAll = policy.BlockAllInboundTraffic[PrivateProfile];
            int current = policy.CurrentProfileTypes;
            int modify = policy.LocalPolicyModifyState;
            return new FirewallPolicyState(enabled, blockAll, current, modify);
        }
        finally
        {
            Release(policy);
        }
    }

    public IReadOnlyList<FirewallRule> ReadRules()
    {
        dynamic policy = Policy();
        var list = new List<FirewallRule>();
        try
        {
            dynamic rules = policy.Rules;
            foreach (dynamic r in rules)
            {
                try { list.Add(Read(r)); }
                finally { Release(r); }
            }
            Release(rules);
        }
        finally
        {
            Release(policy);
        }
        return list;
    }

    static FirewallRule Read(dynamic r) => new()
    {
        Name = (string?)r.Name ?? "",
        Grouping = (string?)r.Grouping,
        Program = (string?)r.ApplicationName,
        Direction = (FirewallDirection)(int)r.Direction,
        Action = (FirewallAction)(int)r.Action,
        Profiles = (int)r.Profiles,
        Protocol = (int)r.Protocol,
        RemoteAddresses = (string?)r.RemoteAddresses,
        LocalAddresses = (string?)r.LocalAddresses,
        LocalPorts = (string?)r.LocalPorts,
        RemotePorts = (string?)r.RemotePorts,
        ServiceName = (string?)r.serviceName,
        InterfaceTypes = (string?)r.InterfaceTypes,
        HasInterfaces = HasAny(r.Interfaces),
        EdgeTraversal = (bool)r.EdgeTraversal,
        Enabled = (bool)r.Enabled,
        Description = (string?)r.Description,
    };

    static bool HasAny(object? interfaces) => interfaces is Array a && a.Length > 0;

    static void Fill(dynamic target, FirewallRule rule)
    {
        target.Name = rule.Name;
        target.Description = rule.Description ?? "";
        target.ApplicationName = rule.Program ?? "";
        target.Grouping = rule.Grouping ?? "";
        target.Direction = (int)rule.Direction;
        target.Action = (int)rule.Action;
        target.Profiles = rule.Profiles;
        // Protokol portlardan önce atanmalı.
        target.Protocol = rule.Protocol;
        target.LocalPorts = rule.LocalPorts ?? "*";
        target.RemotePorts = rule.RemotePorts ?? "*";
        target.RemoteAddresses = rule.RemoteAddresses ?? "*";
        target.LocalAddresses = rule.LocalAddresses ?? "*";
        target.InterfaceTypes = rule.InterfaceTypes ?? "All";
        target.EdgeTraversal = rule.EdgeTraversal;
        target.Enabled = rule.Enabled;
    }

    public void Add(FirewallRule rule)
    {
        dynamic policy = Policy();
        dynamic created = Activator.CreateInstance(Type.GetTypeFromProgID("HNetCfg.FWRule", throwOnError: true)!)!;
        try
        {
            Fill(created, rule);
            dynamic rules = policy.Rules;
            rules.Add(created);
            Release(rules);
        }
        finally
        {
            Release(created);
            Release(policy);
        }
    }

    public void Update(FirewallRule rule, Func<FirewallRule, bool> isTarget)
    {
        dynamic policy = Policy();
        try
        {
            dynamic rules = policy.Rules;
            foreach (dynamic r in rules)
            {
                try
                {
                    if (string.Equals((string?)r.Name, rule.Name, StringComparison.OrdinalIgnoreCase) && isTarget(Read(r)))
                        Fill(r, rule);
                }
                finally { Release(r); }
            }
            Release(rules);
        }
        finally
        {
            Release(policy);
        }
    }

    public void RemoveByName(string name)
    {
        dynamic policy = Policy();
        try
        {
            dynamic rules = policy.Rules;
            rules.Remove(name);
            Release(rules);
        }
        finally
        {
            Release(policy);
        }
    }

    static void Release(object? o)
    {
        if (o is not null && Marshal.IsComObject(o)) Marshal.ReleaseComObject(o);
    }
}

/// <summary>Ağ listesi yöneticisi (COM): bağlı ağlardan biri "Ortak" mı.</summary>
static class NetworkCategories
{
    static readonly Guid NetworkListManager = new("DCB00C01-570F-4A9B-8D69-199FDBA5723B");
    const int ConnectedNetworks = 1;
    const int PublicCategory = 0;

    public static bool AnyConnectedPublic()
    {
        object? manager = null;
        try
        {
            manager = Activator.CreateInstance(Type.GetTypeFromCLSID(NetworkListManager, throwOnError: true)!);
            dynamic m = manager!;
            dynamic networks = m.GetNetworks(ConnectedNetworks);
            var found = false;
            foreach (dynamic n in networks)
            {
                try
                {
                    if ((int)n.GetCategory() == PublicCategory) found = true;
                }
                finally
                {
                    if (Marshal.IsComObject(n)) Marshal.ReleaseComObject(n);
                }
            }
            if (Marshal.IsComObject(networks)) Marshal.ReleaseComObject(networks);
            return found;
        }
        catch (Exception)
        {
            return false;
        }
        finally
        {
            if (manager is not null && Marshal.IsComObject(manager)) Marshal.ReleaseComObject(manager);
        }
    }
}
