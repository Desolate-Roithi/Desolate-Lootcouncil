local L = LibStub("AceLocale-3.0"):NewLocale("DesolateLootcouncil", "deDE")
if not L then return end

-- Global
L["Close"] = "Schließen"
L["Loading..."] = "Lädt..."

-- Attendance.lua
L["Are you sure you want to delete this attendance record? This cannot be undone."] =
"Bist du sicher, dass du diesen Anwesenheitsrecord löschen möchtest? Dies kann nicht rückgängig gemacht werden."
L["Yes"] = "Ja"
L["No"] = "Nein"
L["No active session to review."] = "Keine aktive Sitzung zur Überprüfung."
L["Session Attendance & Decay Review"] = "Anwesenheit & Positions-Verfall Überprüfung"
L["Session Attendance Review (Decay Disabled)"] = "Anwesenheit Überprüfung (Positions-Verfall deaktiviert)"
L["Review attendance before ending session. Click names to move them between lists."] =
"Anwesenheit überprüfen, bevor die Sitzung beendet wird. Namen anklicken, um sie zwischen den Listen zu verschieben."
L["Attended (Safe)"] = "Anwesend (Sicher)"
L["Absent (Apply Decay)"] = "Abwesend (Verfall anwenden)"
L["Absent (Reference Only)"] = "Abwesend (Nur Referenz)"
L["Decay Amount"] = "Verfalls um x Positionen"
L["End Session (Save History)"] = "Sitzung beenden (Verlauf speichern)"
L["APPLY DECAY & END"] = "VERFALL ANWENDEN & BEENDEN"
L["Applied +%d Position Decay to all lists for absent players."] =
"Wandte +%d Positions-Verfall auf alle Listen für abwesende Spieler an."
L["Decay Amount is 0. No priorities changed."] = "Verfallsbetrag ist 0. Keine Prioritäten geändert."
L["Deleted attendance history entry."] = "Anwesenheitsverlauf-Eintrag gelöscht."
L["Settings"] = "Einstellungen"
L["Enable Priority Decay"] = "Positions-Verfall aktivieren"
L["If enabled, absent players will suffer priority decay."] =
"Wenn aktiviert, erleiden abwesende Spieler einen Positions-Verfall."
L["Default Penalty"] = "Standard-Verfall"
L["Amount of priority lost per missed raid."] = "Verlust von x Positionen pro verpasstem Raid."
L["Session Control"] = "Session-Steuerung"
L["Session Active"] = "Session aktiv"
L["Session Inactive"] = "Session inaktiv"
L["End Session"] = "Session beenden"
L["Start Session"] = "Session starten"
L["Open the Attendance Review window to process decay and end the session."] =
"Öffne das Anwesenheits-Überprüfungsfenster, um den Verfall zu verarbeiten und die Session zu beenden."
L["Start a new raid session."] = "Eine neue Raid-Session starten."
L["Raid History"] = "Raid-Verlauf"
L["Select Session"] = "Session auswählen"
L["View details of current or past raid sessions."] = "Details der aktuellen oder vergangenen Raid-Sessions anzeigen."
L["Delete Entry"] = "Eintrag löschen"
L["Permanently delete the selected history record."] = "Lösche den ausgewählten Raid-Verlaufsdatensatz dauerhaft."
L["Select a session to view details."] = "Wähle eine Session aus, um Details anzuzeigen."
L["Error: History entry not found or empty."] = "Fehler: Raid-Verlaufs-Eintrag nicht gefunden oder leer."
L["No attendees recorded."] = "Keine Teilnehmer aufgezeichnet."
L["Attendees (%d):"] = "Teilnehmer (%d):"
L["Attendance & Decay"] = "Anwesenheit & Verfall"

-- History.lua
L["Session History"] = "Session-Verlauf"
L["Select Date"] = "Datum auswählen"
L["Delete Date"] = "Datum löschen"
L["Re-award"] = "Neu vergeben"
L["No entries for this date."] = "Keine Einträge für dieses Datum."
L["Removed %d entries for %s"] = "%d Einträge für %s entfernt"

-- Monitor.lua
L["Loot Monitor"] = "Loot-Monitor"
L["Unassign"] = "Zuweisung aufheben"
L["Push Item"] = "Gegenstand pushen"
L["Assigning %s..."] = "Weise %s zu..."
L["Still Pending Response:"] = "Warte noch auf Antwort von:"
L["Roll Details for "] = "Wurfdetails für "
L["Confirm Award"] = "Vergabe bestätigen"
L["Cancel"] = "Abbrechen"
L["Award"] = "Vergeben"
L["View Rolls"] = "Würfe ansehen"
L["Session Monitor"] = "Session-Monitor"
L["Pending Trades"] = "Ausstehender Handel"
L["Stop Session"] = "Session beenden"
L["Unranked"] = "Ohne Rang"
L["Give"] = "Zuweisen"
L["Lvl %d"] = "Lvl %d"
L["Award Item"] = "Gegenstand vergeben"
L["No active votes."] = "Keine aktiven Abstimmungen."
L["Disenchanters"] = "Entzauberer"
L["OS"] = "OS"
L["TM"] = "TM"
L["Bid"] = "Bieten"
L["Roll"] = "Würfeln"
L["Pass"] = "Passen"

-- Voting.lua
L["Loot Vote"] = "Loot-Abstimmung"
L["You voted: |cffaaaaaaAuto Pass|r"] = "Du hast abgestimmt: |cffaaaaaaAutom. Passen|r"
L["Closed"] = "Abgeschlossen"
L["Syncing..."] = "Synchronisiere..."
L["Change"] = "Ändern"
L["Offspec"] = "Offspec"
L["T-Mog"] = "T-Mog"
L["You voted: %s%s|r"] = "Du hast abgestimmt: %s%s|r"
L["Voted: %s%s|r"] = "Abgestimmt: %s%s|r"

-- ItemManager.lua
L["Item Manager"] = "Gegenstands-Manager"
L["Item Name/Link/ID"] = "Gegenstands-Name/Link/ID"
L["Target List"] = "Zielliste"
L["Add"] = "Hinzufügen"
L["Sync Raid"] = "Raid synchronisieren"
L["Item Manager lists synced to raid."] = "Gegenstands-Manager-Listen mit Raid synchronisiert."
L["Remove"] = "Entfernen"
L["Assigned Items"] = "Zugewiesene Gegenstände"
L["Select List to View"] = "Liste zum Anzeigen auswählen"
L["Removed item ID: %s"] = "Gegenstands-ID entfernt: %s"

-- TradeList.lua
L["Trade"] = "Handeln"
L["%s is out of trade range."] = "%s ist außer Reichweite."
L["Could not auto-target %s. Please target them manually and click Trade again."] =
"Konnte %s nicht automatisch anvisieren. Bitte manuell anvisieren und erneut auf Handeln klicken."
L["Marked %s as traded."] = "%s als gehandelt markiert."
L["No pending trades."] = "Keine ausstehenden Handel."

-- Version.lua
L["Desolate Loot Council - Versions"] = "Desolate Loot Council - Versionen"
L["Highest Found Version: %s"] = "Höchste gefundene Version: %s"
L["Not Installed / Missing"] = "Nicht installiert / fehlt"
L["%s (Current)"] = "%s (Aktuell)"
L["%s (Outdated)"] = "%s (Veraltet)"
L["Refresh / Ping"] = "Aktualisieren / Ping"
L["Wait %.0fs"] = "Warte %.0fs"
L["Pinging..."] = "Pinge..."

-- PriorityOverride.lua
L["Override: %s"] = "Überschreiben: %s"
L["Manual Override: Moved %s from %d to %d in %s."] = "Manuelles Überschreiben: %s von %d auf %d in %s verschoben."

-- PriorityLogHistory.lua
L["Priority Log History"] = "Prioritäts-Logverlauf"
L["No history logs found."] = "Keine Verlaufs-Logs gefunden."

-- Loot.lua (Systems)
L["Systems/Loot Loaded"] = "Systeme/Loot geladen"
L["Wiped stale loot backlog from previous session."] = "Veraltetes Loot aus vorheriger Session gelöscht."
L["Added Item %d to '%s'"] = "Gegenstand %d zu '%s' hinzugefügt"
L["Item unassigned from all priority lists."] = "Gegenstand von allen Prioritätslisten entfernt."
L["Skipped low quality item: %s"] = "Gegenstände geringer Qualität übersprungen: %s"
L["--- LOOT SCAN START (%d slots) ---"] = "--- LOOT-SCAN START (%d Slots) ---"
L["--- SCAN END ---"] = "--- SCAN ENDE ---"
L["AUTO-ADDED from self-loot: %s"] = "AUTOM. HINZUGEFÜGT aus Eigenem Loot: %s"
L["Loot backlog cleared (dedup store preserved)."] = "Loot-Rückstand bereinigt (Duplikatenspeicherung erhalten)."
L["Manually added: %s"] = "Manuell hinzugefügt: %s"
L["Winner of %s is %s! (%s)"] = "Gewinner von %s ist %s! (%s)"
L["You have been awarded %s! Trade me."] = "Dir wurde %s zugesprochen! Handel mich an."
L["Restored %d votes for re-awarded item."] = "%d Stimmen für neu vergebenen Gegenstand wiederhergestellt."
L["Re-award item: %s"] = "Gegenstand neu vergeben: %s"
L["Item reverted to bidding session."] = "Gegenstand zurück in die Loot-Abstimmungssession gegeben."
L["Added test items to session."] = "Testgegenstände zur Sitzung hinzugefügt."
L["Triggered disenchanter scan via version check."] = "Entzauberer-Scan via Versionsprüfung ausgelöst."

-- Trade.lua (Systems)
L["Systems/Trade Loaded"] = "Systeme/Handel geladen"
L["Bypassed Blizzard trade confirmation: %s"] = "Blizzard-Handelsbestätigung umgangen: %s"
L["Staged %s for %s."] = "%s für %s bereitgestellt."
L["Could not find %s in bags for %s."] = "Konnte %s nicht in den Taschen für %s finden."
L["Trade complete. %s marked as delivered to %s."] = "Handel abgeschlossen. %s als an %s geliefert markiert."
