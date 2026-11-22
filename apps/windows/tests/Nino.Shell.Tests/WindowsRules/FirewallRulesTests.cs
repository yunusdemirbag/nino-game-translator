// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Shell.WindowsRules;

namespace Nino.Shell.Tests.WindowsRules;

// Güvenlik duvarı kural mantığı: kimlikler-veri §11.2, §11.4, §11.5 örnekleri.
public sealed class FirewallRulesTests
{
    const string Exe = @"C:\Users\u\AppData\Local\NinoGameTranslator\current\Nino.exe";
    const string OtherExe = @"C:\Games\Other.exe";

    static readonly FirewallPolicyState On = new(true, false, 2, 0);
    static readonly FirewallPolicyState Off = new(false, false, 2, 0);

    static FirewallLogic Logic => new(Exe, p => string.IsNullOrWhiteSpace(p) ? null : p.Trim().ToLowerInvariant());

    static FirewallRule Allow(string name, int protocol, string? program = Exe, string? group = null) => new()
    {
        Name = name, Grouping = group, Program = program, Protocol = protocol, Profiles = 2,
        RemoteAddresses = "LocalSubnet",
    };

    static FirewallRule LegacyBroad(string? program = Exe) => new()
    {
        Name = FirewallNames.LegacyBroadRule, Program = program, Protocol = 256, Profiles = 7, RemoteAddresses = "*",
    };

    static FirewallRule OwnBlock(string name = "Nino.exe", int profiles = 2) => new()
    {
        Name = name, Program = Exe, Action = FirewallAction.Block, Protocol = 256, Profiles = profiles,
    };

    static IReadOnlyList<FirewallRule> Managed => FirewallNames.ManagedRules(Exe);

    sealed class Store(FirewallPolicyState policy, IEnumerable<FirewallRule> rules) : IFirewallStore
    {
        public List<FirewallRule> Rules { get; } = rules.ToList();
        public bool SilentWriteFailure { get; init; }
        public bool ThrowOnAdd { get; init; }

        public FirewallPolicyState ReadPolicy() => policy;
        public IReadOnlyList<FirewallRule> ReadRules() => Rules.ToList();

        public void Add(FirewallRule rule)
        {
            if (ThrowOnAdd) throw new UnauthorizedAccessException("denied");
            if (!SilentWriteFailure) Rules.Add(rule);
        }

        public void Update(FirewallRule rule, Func<FirewallRule, bool> isTarget)
        {
            var i = Rules.FindIndex(r => string.Equals(r.Name, rule.Name, StringComparison.OrdinalIgnoreCase) && isTarget(r));
            if (i >= 0 && !SilentWriteFailure) Rules[i] = rule;
        }

        public void RemoveByName(string name)
        {
            var i = Rules.FindIndex(r => string.Equals(r.Name, name, StringComparison.OrdinalIgnoreCase));
            if (i >= 0) Rules.RemoveAt(i);
        }
    }

    [Fact]
    public void NarrowRulesGivePermission() => Assert.True(Logic.HasPermission(On, Managed));

    [Theory]
    [InlineData(1)]
    [InlineData(4)]
    public void OnlyPublicOrDomainProfileIsNotEnough(int profiles) =>
        Assert.False(Logic.HasPermission(On, Managed.Select(r => r with { Profiles = profiles }).ToList()));

    public static TheoryData<string> NarrowedVariants => ["remote", "localport", "remoteport", "interface", "service",
        "disabled", "outbound", "restricted", "otherprogram"];

    [Theory]
    [MemberData(nameof(NarrowedVariants))]
    public void NarrowedRulesAreNotEnough(string variant)
    {
        var rules = Managed.Select(r => variant switch
        {
            "remote" => r with { RemoteAddresses = "192.168.0.110" },
            "localport" => r with { LocalPorts = "8787" },
            "remoteport" => r with { RemotePorts = "9296" },
            "interface" => r with { InterfaceTypes = "Wireless" },
            "service" => r with { ServiceName = "svc" },
            "disabled" => r with { Enabled = false },
            "outbound" => r with { Direction = FirewallDirection.Outbound },
            "restricted" => r with { HasInterfaces = true },
            _ => r with { Program = OtherExe },
        }).ToList();
        Assert.False(Logic.HasPermission(On, rules));
    }

    [Fact]
    public void TcpOnlyIsNotEnough() => Assert.False(Logic.HasPermission(On, [Managed[0]]));

    [Fact]
    public void BlockAllInboundOrGroupPolicyMeansNo()
    {
        Assert.False(Logic.HasPermission(On with { PrivateBlocksAllInbound = true }, Managed));
        Assert.False(Logic.HasPermission(On with { LocalPolicyModifyState = 1 }, Managed));
    }

    [Fact]
    public void FirewallOffNeedsNoRuleButLegacyBroadStillCounts()
    {
        Assert.True(Logic.HasPermission(Off, []));
        Assert.False(Logic.HasPermission(Off, [LegacyBroad()]));
    }

    [Fact]
    public void GeneralBlockCountsOtherProgramBlockDoesNot()
    {
        var general = new FirewallRule { Name = "block all", Program = null, Action = FirewallAction.Block, Protocol = 256 };
        Assert.False(Logic.HasPermission(On, [.. Managed, general]));
        var other = general with { Program = OtherExe };
        var service = general with { ServiceName = "svc" };
        Assert.True(Logic.HasPermission(On, [.. Managed, other, service]));
    }

    [Fact]
    public void PreviousNamesCountAsPermission()
    {
        var prev = new[]
        {
            Allow(FirewallNames.PreviousTcpRule, 6, group: FirewallNames.PreviousGroup),
            Allow(FirewallNames.PreviousUdpRule, 17, group: FirewallNames.PreviousGroup),
        };
        Assert.True(Logic.HasPermission(On, prev));
    }

    [Fact]
    public void LegacyBroadIsMigratedAndUserRuleKept()
    {
        var custom = Allow("my custom rule", 6, program: OtherExe);
        var store = new Store(On, [LegacyBroad(), custom]);
        Assert.True(FirewallConfigurator.Configure(store, Logic));
        Assert.DoesNotContain(store.Rules, r => r.Name == FirewallNames.LegacyBroadRule);
        Assert.Contains(store.Rules, r => r.Name == "my custom rule");
        Assert.Equal(3, store.Rules.Count);
        Assert.True(FirewallConfigurator.Configure(store, Logic));
        Assert.Equal(3, store.Rules.Count);
    }

    [Fact]
    public void OwnBlockIsReplacedByAllow()
    {
        var store = new Store(On, [OwnBlock()]);
        Assert.True(FirewallConfigurator.Configure(store, Logic));
        Assert.DoesNotContain(store.Rules, r => r.Action == FirewallAction.Block);
        Assert.Equal(2, store.Rules.Count);
    }

    [Fact]
    public void BlockSharingNameWithForeignRuleIsKeptAndNoPermissionClaimed()
    {
        var foreign = Allow("Nino.exe", 6, program: OtherExe);
        var store = new Store(On, [OwnBlock(), foreign]);
        Assert.False(FirewallConfigurator.Configure(store, Logic));
        Assert.Contains(store.Rules, r => r.Action == FirewallAction.Block);
        Assert.Equal(2, store.Rules.Count);
    }

    [Fact]
    public void PublicOnlyBlockIsKept()
    {
        var store = new Store(On, [OwnBlock(profiles: 4)]);
        Assert.True(FirewallConfigurator.Configure(store, Logic));
        Assert.Contains(store.Rules, r => r.Action == FirewallAction.Block && r.Profiles == 4);
    }

    [Fact]
    public void GeneralBlockMakesConfigureFail()
    {
        var general = new FirewallRule { Name = "block all", Action = FirewallAction.Block, Protocol = 256 };
        var store = new Store(On, [general]);
        Assert.False(FirewallConfigurator.Configure(store, Logic));
        Assert.Single(store.Rules);
    }

    [Fact]
    public void FailedWriteKeepsOldPermission()
    {
        var store = new Store(On, [LegacyBroad()]) { ThrowOnAdd = true };
        Assert.False(FirewallConfigurator.Configure(store, Logic));
        Assert.Contains(store.Rules, r => r.Name == FirewallNames.LegacyBroadRule);
    }

    [Fact]
    public void SilentWriteFailureIsNotMaskedByOldRule()
    {
        var store = new Store(Off, [LegacyBroad()]) { SilentWriteFailure = true };
        Assert.False(FirewallConfigurator.Configure(store, Logic));
        Assert.Contains(store.Rules, r => r.Name == FirewallNames.LegacyBroadRule);
    }

    [Fact]
    public void ManagedNameClashDoesNotOverwriteForeign()
    {
        var foreign = Allow("nino - local tcp", 6, program: OtherExe);
        var store = new Store(On, [foreign]);
        Assert.False(FirewallConfigurator.Configure(store, Logic));
        Assert.Single(store.Rules);
        Assert.Equal(OtherExe, store.Rules[0].Program);
    }

    [Fact]
    public void LegacyNameClashDoesNotDeleteForeign()
    {
        var foreign = LegacyBroad(OtherExe);
        var store = new Store(On, [LegacyBroad(), foreign]);
        Assert.False(FirewallConfigurator.Configure(store, Logic));
        Assert.Equal(2, store.Rules.Count);
    }

    [Fact]
    public void FreshInstallGetsNewNames()
    {
        var store = new Store(On, []);
        Assert.True(FirewallConfigurator.Configure(store, Logic));
        Assert.Equal([FirewallNames.TcpRule, FirewallNames.UdpRule], store.Rules.Select(r => r.Name));
        Assert.All(store.Rules, r => Assert.Equal(FirewallNames.RuleGroup, r.Grouping));
    }

    [Fact]
    public void PreviousNamesAreRenamedOldAppRulesStay()
    {
        var oldExe = @"C:\Users\u\AppData\Local\" + Nino.Core.LegacyNames.InstallFolder + @"\current\" + Nino.Core.LegacyNames.Executable;
        var prev = new[]
        {
            Allow(FirewallNames.PreviousTcpRule, 6, group: FirewallNames.PreviousGroup),
            Allow(FirewallNames.PreviousUdpRule, 17, group: FirewallNames.PreviousGroup),
        };
        var oldApp = Allow(FirewallNames.PreviousTcpRule + " (old)", 6, program: oldExe, group: FirewallNames.PreviousGroup);
        var store = new Store(On, [.. prev, oldApp]);
        Assert.True(FirewallConfigurator.Configure(store, Logic));
        Assert.DoesNotContain(store.Rules, r => r.Program == Exe && r.Grouping == FirewallNames.PreviousGroup);
        Assert.Contains(store.Rules, r => r.Program == oldExe);
        Assert.Equal(3, store.Rules.Count);
    }

    [Fact]
    public void PreviousNameSharedWithOtherProgramIsNotDeleted()
    {
        var mine = Allow(FirewallNames.PreviousTcpRule, 6, group: FirewallNames.PreviousGroup);
        var other = Allow(FirewallNames.PreviousTcpRule, 6, program: OtherExe, group: FirewallNames.PreviousGroup);
        var store = new Store(On, [mine, other]);
        Assert.True(FirewallConfigurator.Configure(store, Logic));
        Assert.Equal(2, store.Rules.Count(r => r.Name == FirewallNames.PreviousTcpRule));
    }

    [Fact]
    public void ExistingManagedRulesAreUpdatedInPlace()
    {
        var stale = Managed.Select(r => r with { RemoteAddresses = "*", Description = "old" }).ToList();
        var store = new Store(On, stale);
        Assert.True(FirewallConfigurator.Configure(store, Logic));
        Assert.Equal(2, store.Rules.Count);
        Assert.All(store.Rules, r => Assert.Equal(FirewallNames.Description, r.Description));
    }

    [Fact]
    public void UninstallRemovesOnlyOwnRules()
    {
        var custom = Allow("my custom rule", 6, program: OtherExe);
        var store = new Store(On, [.. Managed, LegacyBroad(), custom]);
        FirewallConfigurator.RemoveOwnRules(store, Logic);
        Assert.Single(store.Rules);
        Assert.Equal("my custom rule", store.Rules[0].Name);
    }

    [Fact]
    public void ScopeNormalisation()
    {
        Assert.Equal("*", FirewallLogic.Scope(""));
        Assert.Equal("*", FirewallLogic.Scope(null));
        Assert.Equal("LocalSubnet", FirewallLogic.Scope("localsubnet"));
    }

    [Fact]
    public void EmptyProgramNeverMatches()
    {
        var logic = new FirewallLogic(Exe);
        Assert.False(logic.IsThisExe(new FirewallRule { Name = "x", Program = "" }));
        Assert.True(logic.IsThisExe(new FirewallRule { Name = "x", Program = Exe.ToUpperInvariant() }));
    }

    [Fact]
    public void HelperInvocationIsExact()
    {
        Assert.True(FirewallNames.IsHelperInvocation(["--configure-local-firewall"]));
        Assert.False(FirewallNames.IsHelperInvocation(["--configure-local-firewall", "x"]));
        Assert.False(FirewallNames.IsHelperInvocation([]));
        Assert.False(FirewallNames.IsHelperInvocation(null));
    }
}
