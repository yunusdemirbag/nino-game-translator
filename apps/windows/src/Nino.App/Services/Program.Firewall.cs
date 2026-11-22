// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.App.Services;

namespace Nino.App;

// Giriş noktasının güvenlik duvarı parçaları (kimlikler-veri §3.1, §11.4, §11.5).
public static partial class Program
{
    static partial void ConfigureLocalFirewall(ref int exitCode) => exitCode = WindowsFirewall.RunHelper();

    static partial void RemoveFirewallRulesBeforeUninstall() => WindowsFirewall.RemoveOwnRules();
}
