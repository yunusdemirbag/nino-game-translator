// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Windows;
using Nino.Shell;

namespace Nino.App.Views;

// Kabuğun kurulum bölümünden aldığı görünüm.
public static partial class ShellWindows
{
    static partial void CreateSetupView(NinoController controller, ref FrameworkElement? view) =>
        view = new SetupView(controller);
}
