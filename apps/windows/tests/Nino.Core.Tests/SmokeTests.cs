// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using Nino.Core;

namespace Nino.Core.Tests;

public class LegacyNamesTests
{
    [Fact]
    public void EskiAdlarCozulur()
    {
        Assert.False(string.IsNullOrWhiteSpace(LegacyNames.DataFolder));
        Assert.NotEmpty(LegacyNames.SecretsEntropy);
    }
}
