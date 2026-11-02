# Control–Option hold dictation — 0.4.4

Installed canonical app: `build/Coda.app`, version 0.4.4 build 3. This user's saved `dictationModifierShortcut` is true and `dictationMode` is hold. No other preferences were changed; the previous 0.4.3 app is recoverable in Trash as `Coda 19-41-46-290.app`.

Hold Control and Option alone for 180 ms to start once. Release either modifier to stop and run the existing local transcription/insertion flow. A quick release during startup cancels that session; a stale permission response cannot start recording. The brief arming interval avoids most ordinary Control–Option combinations. Additional keys/modifiers cancel the chord without consuming events. Both modifiers must be released before a completed/interrupted chord can restart. No changes were made to Wispr or system shortcuts.

Unified Settings → Dictation offers Control + Option or Custom shortcut, plus Hold/Toggle activation. The existing custom shortcut is retained but disabled while modifier mode is selected. The suggested shortcut action selects Custom mode. VoiceOver active state blocks the modifier listener. At install, the VoiceOver enabled preference was unset and its process was absent. Other apps' arbitrary modifier bindings cannot be exhaustively detected.

NSEvent local/global monitors return all events untouched. An 80 ms physical-flags watchdog handles missed release events and focus changes without initiating recording. Listener setup requires existing Accessibility trust and fails closed if native monitor registration fails. Existing capture timeout, cancellation, focus-safe insertion, overlay dismissal and local history remain in place.

Validation: scripts/test.sh passed 47 core and 13 UI/lifecycle tests, including one skipped opt-in insertion fixture. Six new reducer/lifecycle tests cover duplicate events, either-key release, rapid release before activation, unrelated shortcut chords, interruption/rearm, stale microphone startup and hold/toggle flow. Existing overlay regression and rendering tests passed. The Settings render was visually inspected.

Actual installed app verification: Coda 0.4.4 reports Accessibility enabled; visible picker values are Control + Option and Hold. The native listener status is available. Stable signing requirement is unchanged: app.coda.notebook plus certificate 22571B293DDEED6B20DB834884A208BFDADDEDD7. No security permission repair was needed.

No real microphone/global-key recording test, clipboard insertion, private audio, model download or API request was performed. Live audio/shortcut end-to-end behavior remains user-verifiable.

Logs: /tmp/coda-hold-tests.log and /tmp/coda-hold-build.log.
