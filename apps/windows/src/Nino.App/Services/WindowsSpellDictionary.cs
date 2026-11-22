// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nino contributors

using System.Runtime.InteropServices;
using Nino.Core.Reading;
using Nino.Shell.WindowsRules;

namespace Nino.App.Services;

/// <summary>
/// Sistemin yazım denetleyicisi (Windows 8+, COM; okuma-hatti §3.6), dil en-US. Denetleyici ilk sorguda bir
/// kez kurulur (arayüz iş parçacığında sorulduysa çok iş parçacıklı bir arka plan işinde). Denetleyici yoksa ya da
/// çağrı hata verirse her sözcük sözlükte sayılır; sonuçlar <see cref="CachedSpellDictionary"/>'de önbelleklenir
/// ve sorgular tek kilitle sıralanır. COM nesneleri her sorgudan sonra bırakılır.
/// </summary>
public sealed class WindowsSpellDictionary : ISpellDictionary
{
    const string Language = "en-US";
    const int SFalse = 1;

    static readonly Guid FactoryClass = new("7AB36653-1796-484B-BDFA-E74F1DB7C1DC");

    readonly CachedSpellDictionary _cache;
    readonly object _createGate = new();
    bool _created;
    ISpellChecker? _checker;

    /// <summary>Uygulama boyunca tek örnek.</summary>
    public static WindowsSpellDictionary Shared { get; } = new();

    WindowsSpellDictionary() => _cache = new CachedSpellDictionary(Lookup);

    /// <inheritdoc />
    public bool Contains(string word) => _cache.Contains(word);

    /// <summary>Denetleyici çalışıyor mu: "hello" sorulur, sonra denetleyici kurulmuş mu bakılır.</summary>
    public bool IsWorking
    {
        get
        {
            Contains("hello");
            lock (_createGate) return _checker is not null;
        }
    }

    bool? Lookup(string word)
    {
        var checker = Checker();
        if (checker is null) return null;
        IEnumSpellingError? errors = null;
        IntPtr error = IntPtr.Zero;
        try
        {
            errors = checker.Check(word);
            var hr = errors.Next(out error);
            return hr == SFalse;
        }
        catch (Exception)
        {
            return null;
        }
        finally
        {
            if (error != IntPtr.Zero) Marshal.Release(error);
            if (errors != null) Marshal.FinalReleaseComObject(errors);
        }
    }

    ISpellChecker? Checker()
    {
        lock (_createGate)
        {
            if (_created) return _checker;
            _created = true;
            try
            {
                _checker = Thread.CurrentThread.GetApartmentState() == ApartmentState.STA
                    ? Task.Run(Create).GetAwaiter().GetResult()
                    : Create();
            }
            catch (Exception)
            {
                _checker = null;
            }
            return _checker;
        }
    }

    static ISpellChecker? Create()
    {
        var type = Type.GetTypeFromCLSID(FactoryClass, throwOnError: false);
        if (type is null || Activator.CreateInstance(type) is not ISpellCheckerFactory factory) return null;
        try
        {
            factory.IsSupported(Language, out var supported);
            return supported != 0 ? factory.CreateSpellChecker(Language) : null;
        }
        finally
        {
            Marshal.ReleaseComObject(factory);
        }
    }

    // Arayüzler: yalnız çağrılan yöntemlere kadar, sanal tablo sırasıyla.

    [ComImport, Guid("8E018A9D-2415-4677-BF08-794EA61F94BB"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ISpellCheckerFactory
    {
        IntPtr SupportedLanguages();

        void IsSupported([MarshalAs(UnmanagedType.LPWStr)] string languageTag, out int value);

        ISpellChecker CreateSpellChecker([MarshalAs(UnmanagedType.LPWStr)] string tag);
    }

    [ComImport, Guid("B6FD0B71-E2BC-4653-8D05-F197E412770B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ISpellChecker
    {
        [return: MarshalAs(UnmanagedType.LPWStr)]
        string LanguageTag();

        IEnumSpellingError Check([MarshalAs(UnmanagedType.LPWStr)] string word);
    }

    [ComImport, Guid("803E3BD4-2828-4410-8290-418D1D73C762"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IEnumSpellingError
    {
        [PreserveSig]
        int Next(out IntPtr value);
    }
}
