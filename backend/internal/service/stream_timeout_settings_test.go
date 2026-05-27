package service

import "testing"

func TestDefaultStreamTimeoutSettingsTempUnschedPolicy(t *testing.T) {
	settings := DefaultStreamTimeoutSettings()

	if !settings.Enabled {
		t.Fatal("expected stream timeout handling enabled by default")
	}
	if settings.Action != StreamTimeoutActionTempUnsched {
		t.Fatalf("expected temp unsched action, got %q", settings.Action)
	}
	if settings.ThresholdCount != 2 {
		t.Fatalf("expected threshold count 2, got %d", settings.ThresholdCount)
	}
	if settings.ThresholdWindowMinutes != 30 {
		t.Fatalf("expected threshold window 30 minutes, got %d", settings.ThresholdWindowMinutes)
	}
	if settings.TempUnschedMinutes != 15 {
		t.Fatalf("expected temp unsched 15 minutes, got %d", settings.TempUnschedMinutes)
	}
}
