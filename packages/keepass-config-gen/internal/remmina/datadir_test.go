package remmina

import (
	"os"
	"path/filepath"
	"testing"
)

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestReadINIValue(t *testing.T) {
	path := filepath.Join(t.TempDir(), "remmina.pref")
	writeFile(t, path, `# a comment
[other]
datadir_path = /wrong

[remmina_pref]
; another comment
datadir_path = /home/me/profiles
scale = 1
`)

	got, err := readINIValue(path, "remmina_pref", "datadir_path")
	if err != nil {
		t.Fatal(err)
	}
	if got != "/home/me/profiles" {
		t.Fatalf("got %q", got)
	}

	got, err = readINIValue(path, "missing", "datadir_path")
	if err != nil {
		t.Fatal(err)
	}
	if got != "" {
		t.Fatalf("missing section returned %q", got)
	}

	if _, err := readINIValue(filepath.Join(t.TempDir(), "absent"), "remmina_pref", "datadir_path"); !os.IsNotExist(err) {
		t.Fatalf("missing file error = %v", err)
	}
}

func TestResolvePrefPath(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", "")

	if got, want := ResolvePrefPath(""), filepath.Join(home, ".config", "remmina", "remmina.pref"); got != want {
		t.Fatalf("default = %q, want %q", got, want)
	}

	config := filepath.Join(t.TempDir(), "config")
	t.Setenv("XDG_CONFIG_HOME", config)
	if got, want := ResolvePrefPath(""), filepath.Join(config, "remmina", "remmina.pref"); got != want {
		t.Fatalf("XDG config = %q, want %q", got, want)
	}

	if got, want := ResolvePrefPath("~/custom.pref"), filepath.Join(home, "custom.pref"); got != want {
		t.Fatalf("override = %q, want %q", got, want)
	}
}

func TestResolveDataDirPrecedence(t *testing.T) {
	setup := func(t *testing.T) (home, config string) {
		t.Helper()
		home = t.TempDir()
		config = t.TempDir()
		t.Setenv("HOME", home)
		t.Setenv("XDG_CONFIG_HOME", config)
		t.Setenv("XDG_DATA_HOME", "")
		return home, config
	}

	t.Run("explicit output wins", func(t *testing.T) {
		_, config := setup(t)
		prefData := filepath.Join(t.TempDir(), "pref-data")
		if err := os.MkdirAll(prefData, 0o755); err != nil {
			t.Fatal(err)
		}
		pref := filepath.Join(config, "remmina", "remmina.pref")
		writeFile(t, pref, "[remmina_pref]\ndatadir_path="+prefData+"\n")

		override := filepath.Join(t.TempDir(), "override")
		got, gotPref, gotValue := ResolveDataDir(override, pref)
		if got != override {
			t.Fatalf("data dir = %q, want %q", got, override)
		}
		if gotPref != pref {
			t.Fatalf("pref path = %q, want %q", gotPref, pref)
		}
		if gotValue != prefData {
			t.Fatalf("pref value = %q, want %q", gotValue, prefData)
		}
	})

	t.Run("pref datadir wins over home fallback", func(t *testing.T) {
		home, config := setup(t)
		prefData := filepath.Join(t.TempDir(), "pref-data")
		if err := os.MkdirAll(prefData, 0o755); err != nil {
			t.Fatal(err)
		}
		// The legacy directory exists, but a valid datadir_path still wins.
		if err := os.MkdirAll(filepath.Join(home, ".remmina"), 0o755); err != nil {
			t.Fatal(err)
		}
		pref := filepath.Join(config, "remmina", "remmina.pref")
		writeFile(t, pref, "[remmina_pref]\ndatadir_path="+prefData+"\n")

		got, _, _ := ResolveDataDir("", "")
		if got != prefData {
			t.Fatalf("data dir = %q, want %q", got, prefData)
		}
	})

	t.Run("nonexistent pref datadir falls through", func(t *testing.T) {
		home, config := setup(t)
		legacy := filepath.Join(home, ".remmina")
		if err := os.MkdirAll(legacy, 0o755); err != nil {
			t.Fatal(err)
		}
		pref := filepath.Join(config, "remmina", "remmina.pref")
		writeFile(t, pref, "[remmina_pref]\ndatadir_path="+filepath.Join(t.TempDir(), "missing")+"\n")

		got, _, _ := ResolveDataDir("", "")
		if got != legacy {
			t.Fatalf("data dir = %q, want %q", got, legacy)
		}
	})

	t.Run("legacy home directory", func(t *testing.T) {
		home, _ := setup(t)
		legacy := filepath.Join(home, ".remmina")
		if err := os.MkdirAll(legacy, 0o755); err != nil {
			t.Fatal(err)
		}
		got, _, _ := ResolveDataDir("", "")
		if got != legacy {
			t.Fatalf("data dir = %q, want %q", got, legacy)
		}
	})

	t.Run("XDG data home", func(t *testing.T) {
		_, _ = setup(t)
		data := filepath.Join(t.TempDir(), "data")
		t.Setenv("XDG_DATA_HOME", data)
		got, _, _ := ResolveDataDir("", "")
		if want := filepath.Join(data, "remmina"); got != want {
			t.Fatalf("data dir = %q, want %q", got, want)
		}
	})

	t.Run("default data home", func(t *testing.T) {
		home, _ := setup(t)
		got, _, _ := ResolveDataDir("", "")
		if want := filepath.Join(home, ".local", "share", "remmina"); got != want {
			t.Fatalf("data dir = %q, want %q", got, want)
		}
	})
}

func TestResolveDataDirReturnsPrefValue(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	t.Setenv("XDG_CONFIG_HOME", "")
	t.Setenv("XDG_DATA_HOME", "")

	pref := filepath.Join(t.TempDir(), "remmina.pref")
	writeFile(t, pref, "[remmina_pref]\ndatadir_path=~/profiles\n")
	_, gotPref, gotValue := ResolveDataDir("", pref)
	if gotPref != pref {
		t.Fatalf("pref path = %q, want %q", gotPref, pref)
	}
	if gotValue != "~/profiles" {
		t.Fatalf("pref value = %q, want %q", gotValue, "~/profiles")
	}

	_, _, missing := ResolveDataDir("", filepath.Join(t.TempDir(), "absent"))
	if missing != "" {
		t.Fatalf("missing pref returned %q", missing)
	}
}

func TestRelativeXDGValuesAreIgnored(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", "relative/config")
	t.Setenv("XDG_DATA_HOME", "relative/data")

	if got, want := ResolvePrefPath(""), filepath.Join(home, ".config", "remmina", "remmina.pref"); got != want {
		t.Fatalf("pref path = %q, want %q", got, want)
	}
	got, _, _ := ResolveDataDir("", "")
	if want := filepath.Join(home, ".local", "share", "remmina"); got != want {
		t.Fatalf("data dir = %q, want %q", got, want)
	}
}

func TestPrefReadErrorFallsThrough(t *testing.T) {
	home := t.TempDir()
	config := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", config)
	t.Setenv("XDG_DATA_HOME", "")

	// remmina.pref is a directory, so opening it succeeds but reading fails.
	pref := filepath.Join(config, "remmina", "remmina.pref")
	if err := os.MkdirAll(pref, 0o755); err != nil {
		t.Fatal(err)
	}
	legacy := filepath.Join(home, ".remmina")
	if err := os.MkdirAll(legacy, 0o755); err != nil {
		t.Fatal(err)
	}

	got, _, _ := ResolveDataDir("", "")
	if got != legacy {
		t.Fatalf("data dir = %q, want %q", got, legacy)
	}
}

func TestUnreadablePrefFallsThrough(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root can read a mode-0000 file")
	}
	home := t.TempDir()
	config := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", config)
	t.Setenv("XDG_DATA_HOME", "")

	pref := filepath.Join(config, "remmina", "remmina.pref")
	writeFile(t, pref, "[remmina_pref]\ndatadir_path=/ignored\n")
	if err := os.Chmod(pref, 0o000); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(pref, 0o600) })

	got, _, _ := ResolveDataDir("", "")
	if want := filepath.Join(home, ".local", "share", "remmina"); got != want {
		t.Fatalf("data dir = %q, want %q", got, want)
	}
}
