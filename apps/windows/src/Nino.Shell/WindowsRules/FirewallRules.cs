// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core;

namespace Nino.Shell.WindowsRules;

// Windows Güvenlik Duvarı kural mantığı (platformdan bağımsız; COM okuma/yazma Nino.App'te). Tarif: kimlikler-veri §11.

/// <summary>Kuralın yönü (Windows değerleri).</summary>
public enum FirewallDirection { Inbound = 1, Outbound = 2 }

/// <summary>Kuralın eylemi (Windows değerleri).</summary>
public enum FirewallAction { Block = 0, Allow = 1 }

/// <summary>Güvenlik duvarı kuralının Nino'yu ilgilendiren alanları.</summary>
public sealed record FirewallRule
{
    /// <summary>Kural adı.</summary>
    public string Name { get; init; } = "";

    /// <summary>Grup (yoksa null).</summary>
    public string? Grouping { get; init; }

    /// <summary>Program yolu (yoksa null).</summary>
    public string? Program { get; init; }

    /// <summary>Yön.</summary>
    public FirewallDirection Direction { get; init; } = FirewallDirection.Inbound;

    /// <summary>Eylem.</summary>
    public FirewallAction Action { get; init; } = FirewallAction.Allow;

    /// <summary>Profil bitleri (1 etki alanı, 2 özel, 4 ortak).</summary>
    public int Profiles { get; init; } = FirewallNames.PrivateProfile;

    /// <summary>Protokol (6 TCP, 17 UDP, 256 her protokol).</summary>
    public int Protocol { get; init; } = FirewallNames.AnyProtocol;

    /// <summary>Uzak adresler (boş = <c>*</c>).</summary>
    public string? RemoteAddresses { get; init; } = "*";

    /// <summary>Yerel adresler (boş = <c>*</c>).</summary>
    public string? LocalAddresses { get; init; } = "*";

    /// <summary>Yerel portlar (boş = <c>*</c>).</summary>
    public string? LocalPorts { get; init; } = "*";

    /// <summary>Uzak portlar (boş = <c>*</c>).</summary>
    public string? RemotePorts { get; init; } = "*";

    /// <summary>Hizmet adı (yoksa null).</summary>
    public string? ServiceName { get; init; }

    /// <summary>Arayüz türleri (<c>All</c>).</summary>
    public string? InterfaceTypes { get; init; } = "All";

    /// <summary>Belirli arayüzlere kısıtlı mı.</summary>
    public bool HasInterfaces { get; init; }

    /// <summary>Kenar geçişi.</summary>
    public bool EdgeTraversal { get; init; }

    /// <summary>Etkin mi.</summary>
    public bool Enabled { get; init; } = true;

    /// <summary>Açıklama.</summary>
    public string? Description { get; init; }
}

/// <summary>Güvenlik duvarı ilkesinin Özel profille ilgili durumu.</summary>
/// <param name="PrivateEnabled">Özel profilde güvenlik duvarı açık mı.</param>
/// <param name="PrivateBlocksAllInbound">Özel profilde "bütün gelen bağlantıları engelle" açık mı.</param>
/// <param name="CurrentProfileTypes">Şu anki profil türleri (bitler).</param>
/// <param name="LocalPolicyModifyState">Yerel ilke değiştirme durumu (0: yerel kurallar geçerli).</param>
public sealed record FirewallPolicyState(bool PrivateEnabled, bool PrivateBlocksAllInbound, int CurrentProfileTypes,
    int LocalPolicyModifyState);

/// <summary>Kural adları, grup, açıklama ve yardımcı süreç argümanı.</summary>
public static class FirewallNames
{
    /// <summary>TCP kuralının adı.</summary>
    public const string TcpRule = "Nino - Local TCP";

    /// <summary>UDP kuralının adı.</summary>
    public const string UdpRule = "Nino - Local UDP";

    /// <summary>Kural grubu.</summary>
    public const string RuleGroup = "Nino.LocalNetwork";

    /// <summary>Kural açıklaması.</summary>
    public const string Description = "Lets Nino reach your TV and PS Remote Play over private local networks.";

    /// <summary>Kuralı yazan yönetici süreci argümanı.</summary>
    public const string HelperArgument = "--configure-local-firewall";

    /// <summary>Özel profil biti.</summary>
    public const int PrivateProfile = 2;

    /// <summary>Üç profil birden.</summary>
    public const int AllThreeProfiles = 1 | 2 | 4;

    /// <summary>TCP.</summary>
    public const int Tcp = 6;

    /// <summary>UDP.</summary>
    public const int Udp = 17;

    /// <summary>Her protokol.</summary>
    public const int AnyProtocol = 256;

    /// <summary>Uzak adres: yerel alt ağ.</summary>
    public const string LocalSubnet = "LocalSubnet";

    /// <summary>Eski geniş kuralın adı (eski klasör adı).</summary>
    public static string LegacyBroadRule => LegacyNames.DataFolder;

    /// <summary>Önceki sürümün TCP kuralı.</summary>
    public static string PreviousTcpRule => LegacyNames.DataFolder + " - Local TCP";

    /// <summary>Önceki sürümün UDP kuralı.</summary>
    public static string PreviousUdpRule => LegacyNames.DataFolder + " - Local UDP";

    /// <summary>Önceki sürümün grubu.</summary>
    public static string PreviousGroup => LegacyNames.DataFolder + ".LocalNetwork";

    /// <summary>Komut satırı yardımcı süreç çağrısı mı (tek argüman, birebir).</summary>
    public static bool IsHelperInvocation(IReadOnlyList<string>? args) =>
        args is { Count: 1 } && string.Equals(args[0], HelperArgument, StringComparison.Ordinal);

    /// <summary>Yazılacak iki kural.</summary>
    public static IReadOnlyList<FirewallRule> ManagedRules(string exePath) =>
    [
        Managed(TcpRule, Tcp, exePath),
        Managed(UdpRule, Udp, exePath),
    ];

    static FirewallRule Managed(string name, int protocol, string exe) => new()
    {
        Name = name,
        Grouping = RuleGroup,
        Program = exe,
        Direction = FirewallDirection.Inbound,
        Action = FirewallAction.Allow,
        Profiles = PrivateProfile,
        Protocol = protocol,
        RemoteAddresses = LocalSubnet,
        LocalAddresses = "*",
        LocalPorts = "*",
        RemotePorts = "*",
        InterfaceTypes = "All",
        HasInterfaces = false,
        EdgeTraversal = false,
        Enabled = true,
        Description = Description,
    };
}

/// <summary>
/// Kural değerlendirmesi. Program yolları <paramref name="normalizePath"/> ile karşılaştırılır (ortam değişkenleri
/// açılır, tam yola çevrilir; boş ya da çevrilemeyen yol null döner ve hiçbir şeyle eşleşmez); büyük/küçük harf duyarsız.
/// </summary>
public sealed class FirewallLogic
{
    readonly string? _exe;
    readonly Func<string?, string?> _normalize;

    /// <param name="exePath">Bu <c>Nino.exe</c>'nin tam yolu.</param>
    /// <param name="normalizePath">Yol düzeltici; yoksa <see cref="DefaultNormalize"/>.</param>
    public FirewallLogic(string exePath, Func<string?, string?>? normalizePath = null)
    {
        _normalize = normalizePath ?? DefaultNormalize;
        _exe = _normalize(exePath);
        ExePath = exePath;
    }

    /// <summary>Bu exe'nin yolu.</summary>
    public string ExePath { get; }

    /// <summary>Ortam değişkenlerini açar, tam yola çevirir; olmazsa null.</summary>
    public static string? DefaultNormalize(string? path)
    {
        if (string.IsNullOrWhiteSpace(path)) return null;
        try
        {
            return Path.GetFullPath(Environment.ExpandEnvironmentVariables(path.Trim()));
        }
        catch (Exception e) when (e is ArgumentException or NotSupportedException or PathTooLongException
            or System.Security.SecurityException)
        {
            return null;
        }
    }

    static bool Same(string? a, string? b) => string.Equals(a ?? "", b ?? "", StringComparison.OrdinalIgnoreCase);

    static bool Empty(string? s) => string.IsNullOrWhiteSpace(s);

    /// <summary>Kuralın programı bu exe mi.</summary>
    public bool IsThisExe(FirewallRule r) =>
        _exe is not null && _normalize(r.Program) is { } p && string.Equals(p, _exe, StringComparison.OrdinalIgnoreCase);

    static bool IsTcpUdp(int protocol) => protocol is FirewallNames.Tcp or FirewallNames.Udp;

    /// <summary>Uzak/yerel kapsam: boş → <c>*</c>; <c>LocalSubnet</c> harf duyarsız.</summary>
    public static string Scope(string? value)
    {
        var v = value?.Trim();
        if (string.IsNullOrEmpty(v)) return "*";
        return string.Equals(v, FirewallNames.LocalSubnet, StringComparison.OrdinalIgnoreCase) ? FirewallNames.LocalSubnet : v;
    }

    static string Ports(FirewallRule r, string? value)
    {
        if (!IsTcpUdp(r.Protocol)) return "*";
        var v = value?.Trim();
        return string.IsNullOrEmpty(v) ? "*" : v;
    }

    static bool AllPorts(FirewallRule r) => Ports(r, r.LocalPorts) == "*" && Ports(r, r.RemotePorts) == "*";

    static bool AnyOrSubnet(string? remote) => Scope(remote) is "*" or FirewallNames.LocalSubnet;

    static bool AllInterfaces(FirewallRule r) =>
        string.Equals((r.InterfaceTypes ?? "All").Trim(), "All", StringComparison.OrdinalIgnoreCase) && !r.HasInterfaces;

    static bool InPrivate(FirewallRule r) => (r.Profiles & FirewallNames.PrivateProfile) != 0;

    /// <summary>Bu exe'nin en eski geniş kuralı mı.</summary>
    public bool IsLegacyBroad(FirewallRule r) =>
        Same(r.Name, FirewallNames.LegacyBroadRule) && IsThisExe(r) && r.Direction == FirewallDirection.Inbound
        && r.Action == FirewallAction.Allow && r.Protocol == FirewallNames.AnyProtocol
        && (r.Profiles & FirewallNames.AllThreeProfiles) == FirewallNames.AllThreeProfiles
        && Scope(r.RemoteAddresses) == "*" && Scope(r.LocalAddresses) == "*" && Empty(r.ServiceName) && Empty(r.Grouping)
        && AllInterfaces(r) && !r.EdgeTraversal;

    /// <summary>Bu exe'nin yeni adlı yönetilen kuralı mı (ad, program, grup, yön, eylem).</summary>
    public bool IsManaged(FirewallRule r) =>
        (Same(r.Name, FirewallNames.TcpRule) || Same(r.Name, FirewallNames.UdpRule)) && Owns(r, FirewallNames.RuleGroup);

    /// <summary>Bu exe'nin önceki sürüm adlı dar kuralı mı.</summary>
    public bool IsPrevious(FirewallRule r) =>
        (Same(r.Name, FirewallNames.PreviousTcpRule) || Same(r.Name, FirewallNames.PreviousUdpRule))
        && Owns(r, FirewallNames.PreviousGroup);

    bool Owns(FirewallRule r, string group) =>
        IsThisExe(r) && Same(r.Grouping, group) && r.Direction == FirewallDirection.Inbound && r.Action == FirewallAction.Allow;

    /// <summary>Bu exe'nin yerel engeli (Windows'un ilk sorusu kapatılınca yazılan kural gibi).</summary>
    public bool IsOwnLocalBlock(FirewallRule r) =>
        r.Direction == FirewallDirection.Inbound && r.Action == FirewallAction.Block && InPrivate(r) && IsThisExe(r)
        && Empty(r.Grouping) && Empty(r.ServiceName);

    bool IsGeneralBlock(FirewallRule r) =>
        Empty(r.Program) && Empty(r.ServiceName) && AllPorts(r) && AnyOrSubnet(r.RemoteAddresses)
        && Scope(r.LocalAddresses) == "*";

    bool IsFullAllow(FirewallRule r) =>
        r.Action == FirewallAction.Allow && IsThisExe(r) && AnyOrSubnet(r.RemoteAddresses) && Scope(r.LocalAddresses) == "*"
        && AllPorts(r) && Empty(r.ServiceName) && AllInterfaces(r);

    /// <summary>Özel ağda bu exe'ye gelen bağlantı izni var mı (§11.2).</summary>
    public bool HasPermission(FirewallPolicyState policy, IReadOnlyList<FirewallRule> rules)
    {
        if (policy.PrivateEnabled && policy.PrivateBlocksAllInbound) return false;
        if (policy.PrivateEnabled && (policy.CurrentProfileTypes & FirewallNames.PrivateProfile) != 0
            && policy.LocalPolicyModifyState != 0) return false;
        if (rules.Any(IsLegacyBroad)) return false;
        if (!policy.PrivateEnabled) return true;
        foreach (var protocol in new[] { FirewallNames.Tcp, FirewallNames.Udp })
        {
            var relevant = rules.Where(r => r.Enabled && r.Direction == FirewallDirection.Inbound && InPrivate(r)
                && (r.Protocol == protocol || r.Protocol == FirewallNames.AnyProtocol)).ToList();
            if (relevant.Any(r => r.Action == FirewallAction.Block && (IsThisExe(r) || IsGeneralBlock(r)))) return false;
            if (!relevant.Any(IsFullAllow)) return false;
        }
        return true;
    }

    /// <summary>Yazılan kural istenenle birebir mi.</summary>
    public bool Matches(FirewallRule wanted, FirewallRule actual) =>
        Same(wanted.Name, actual.Name) && Same(wanted.Grouping, actual.Grouping) && IsThisExe(actual)
        && wanted.Direction == actual.Direction && wanted.Action == actual.Action && wanted.Profiles == actual.Profiles
        && wanted.Protocol == actual.Protocol && Scope(wanted.RemoteAddresses) == Scope(actual.RemoteAddresses)
        && Scope(wanted.LocalAddresses) == Scope(actual.LocalAddresses)
        && Ports(wanted, wanted.LocalPorts) == Ports(actual, actual.LocalPorts)
        && Ports(wanted, wanted.RemotePorts) == Ports(actual, actual.RemotePorts)
        && Empty(actual.ServiceName) && AllInterfaces(actual) && actual.EdgeTraversal == wanted.EdgeTraversal
        && actual.Enabled == wanted.Enabled;

    /// <summary>Kural yazma planı (§11.4 adım 1–4).</summary>
    public FirewallPlan Plan(FirewallPolicyState policy, IReadOnlyList<FirewallRule> rules)
    {
        var wanted = FirewallNames.ManagedRules(ExePath);
        // 1. Yeni ad yabancı bir kurala ait.
        foreach (var w in wanted)
            if (rules.Any(r => Same(r.Name, w.Name) && !IsManaged(r)))
                return FirewallPlan.Fail("foreign rule uses " + w.Name);
        var groups = rules.GroupBy(r => r.Name, StringComparer.OrdinalIgnoreCase).ToList();
        // 2. Eski geniş kuralın ad grubunda yabancı kural.
        foreach (var g in groups)
            if (g.Any(IsLegacyBroad) && g.Any(r => !IsThisExe(r)))
                return FirewallPlan.Fail("foreign rule shares the old name");
        // 3. Silinecek ad grupları.
        var delete = new List<string>();
        foreach (var g in groups)
        {
            var list = g.ToList();
            var allOwn = list.All(IsThisExe);
            var removable = allOwn && !list.Any(IsManaged) && list.Any(r => IsLegacyBroad(r) || IsOwnLocalBlock(r));
            if (removable || list.All(IsPrevious)) delete.Add(g.Key);
        }
        // 4. Planlanan son durum izin vermeli.
        var final = rules.Where(r => !IsManaged(r) && !delete.Contains(r.Name, StringComparer.OrdinalIgnoreCase))
            .Concat(wanted).ToList();
        if (!HasPermission(policy, final)) return FirewallPlan.Fail("planned rules would not allow Nino");
        return new FirewallPlan(true, null, wanted, delete, groups.ToDictionary(g => g.Key, g => g.Count(),
            StringComparer.OrdinalIgnoreCase));
    }

    /// <summary>Kaldırırken silinecek adlar (§11.5): grubun tamamı bu exe'nin yönetilen ya da eski geniş kuralıysa.</summary>
    public IReadOnlyList<string> UninstallNames(IReadOnlyList<FirewallRule> rules) =>
        rules.GroupBy(r => r.Name, StringComparer.OrdinalIgnoreCase)
            .Where(g => g.All(r => IsManaged(r) || IsPrevious(r) || IsLegacyBroad(r)))
            .Select(g => g.Key).ToList();
}

/// <summary>Yazma planı.</summary>
/// <param name="Ok">Yazılabilir mi.</param>
/// <param name="Problem">Yazılamıyorsa nedeni (günlük için).</param>
/// <param name="Write">Yazılacak kurallar.</param>
/// <param name="DeleteNames">Silinecek adlar.</param>
/// <param name="GroupSizes">Ad başına kural sayısı (adla silme en çok bu kadar tekrarlanır).</param>
public sealed record FirewallPlan(bool Ok, string? Problem, IReadOnlyList<FirewallRule> Write, IReadOnlyList<string> DeleteNames,
    IReadOnlyDictionary<string, int> GroupSizes)
{
    /// <summary>Başarısız plan.</summary>
    public static FirewallPlan Fail(string problem) =>
        new(false, problem, [], [], new Dictionary<string, int>());
}

/// <summary>Güvenlik duvarına erişim (Windows'ta HNetCfg COM nesneleri; testlerde bellek).</summary>
public interface IFirewallStore
{
    /// <summary>İlkenin durumu.</summary>
    FirewallPolicyState ReadPolicy();

    /// <summary>Bütün kurallar.</summary>
    IReadOnlyList<FirewallRule> ReadRules();

    /// <summary>Kural ekler.</summary>
    void Add(FirewallRule rule);

    /// <summary>Aynı adlı, bu exe'nin yönettiği kuralı yerinde günceller (<paramref name="isTarget"/> hangisi olduğunu söyler).</summary>
    void Update(FirewallRule rule, Func<FirewallRule, bool> isTarget);

    /// <summary>Adla bir kural siler (Windows'ta adı tutan ilk kural silinir).</summary>
    void RemoveByName(string name);
}

/// <summary>Kural yazan yönetici sürecinin işi (§11.4) ve kaldırma kancası (§11.5).</summary>
public static class FirewallConfigurator
{
    /// <summary>Kuralları yazar; sonuç izin denetimidir. Hata fırlatmaz.</summary>
    public static bool Configure(IFirewallStore store, FirewallLogic logic, Action<string>? log = null)
    {
        try
        {
            var policy = store.ReadPolicy();
            var rules = store.ReadRules();
            var plan = logic.Plan(policy, rules);
            if (!plan.Ok)
            {
                log?.Invoke("firewall: " + plan.Problem);
                return false;
            }
            foreach (var w in plan.Write)
            {
                var same = rules.Where(r => string.Equals(r.Name, w.Name, StringComparison.OrdinalIgnoreCase)).ToList();
                if (same.Any(r => !logic.IsManaged(r)))
                {
                    log?.Invoke("firewall: name clash " + w.Name);
                    return false;
                }
                if (same.Count > 0) store.Update(w, logic.IsManaged);
                else store.Add(w);
            }
            var written = store.ReadRules();
            foreach (var w in plan.Write)
                if (!written.Any(r => logic.Matches(w, r)))
                {
                    log?.Invoke("firewall: written rule could not be read back: " + w.Name);
                    return false;
                }
            foreach (var name in plan.DeleteNames)
            {
                var tries = plan.GroupSizes.TryGetValue(name, out var n) ? n : 1;
                for (var i = 0; i < tries; i++)
                {
                    if (!store.ReadRules().Any(r => string.Equals(r.Name, name, StringComparison.OrdinalIgnoreCase))) break;
                    store.RemoveByName(name);
                }
            }
            return logic.HasPermission(store.ReadPolicy(), store.ReadRules());
        }
        catch (Exception e)
        {
            log?.Invoke("firewall: " + e.GetType().Name + ": " + e.Message);
            return false;
        }
    }

    /// <summary>Kaldırma öncesi: bu exe'nin kurallarını sessizce siler.</summary>
    public static void RemoveOwnRules(IFirewallStore store, FirewallLogic logic)
    {
        try
        {
            var rules = store.ReadRules();
            foreach (var name in logic.UninstallNames(rules))
            {
                var count = rules.Count(r => string.Equals(r.Name, name, StringComparison.OrdinalIgnoreCase));
                for (var i = 0; i < count; i++) store.RemoveByName(name);
            }
        }
        catch (Exception)
        {
            // Kaldırma durmasın.
        }
    }
}
