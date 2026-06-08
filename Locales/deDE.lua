local L = LibStub("AceLocale-3.0"):NewLocale("DesolateLootcouncil", "deDE")
if not L then return end

-- Global
L["Close"] = "Schließen"
L["Loading..."] = "Lädt..."
L["Desolate Loot Council Settings"] = "Desolate Loot Council Einstellungen"

-- Attendance.lua
L["Are you sure you want to delete this attendance record? This cannot be undone."] =
"Bist du sicher, dass du diesen Anwesenheitsrecord löschen möchtest? Dies kann nicht rückgängig gemacht werden."
L["Yes"] = "Ja"
L["No"] = "Nein"
L["No active session to review."] = "Keine aktive Lootsession zur Überprüfung."
L["Session Attendance & Decay Review"] = "Anwesenheit & Positions-Verfall Überprüfung"
L["Session Attendance Review (Decay Disabled)"] = "Anwesenheit Überprüfung (Positions-Verfall deaktiviert)"
L["Review attendance before ending session. Click names to move them between lists."] =
"Anwesenheit überprüfen, bevor die Lootsession beendet wird. Namen anklicken, um sie zwischen den Listen zu verschieben."
L["Attended (Safe)"] = "Anwesend (Sicher)"
L["Absent (Apply Decay)"] = "Abwesend (Verfall anwenden)"
L["Absent (Reference Only)"] = "Abwesend (Nur Referenz)"
L["Decay Amount"] = "Verfalls um x Positionen"
L["End Session (Save History)"] = "Lootsession beenden (Verlauf speichern)"
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
L["Session Control"] = "Lootsession-Steuerung"
L["Session Active"] = "Lootsession aktiv"
L["Session Inactive"] = "Lootsession inaktiv"
L["End Session"] = "Lootsession beenden"
L["Start Session"] = "Lootsession starten"
L["Open the Attendance Review window to process decay and end the session."] =
"Öffne das Anwesenheits-Überprüfungsfenster, um den Verfall zu verarbeiten und die Lootsession zu beenden."
L["Start a new raid session."] = "Eine neue Raid-Lootsession starten."
L["Raid History"] = "Raid-Verlauf"
L["Select Session"] = "Lootsession auswählen"
L["View details of current or past raid sessions."] =
"Details der aktuellen oder vergangenen Raid-Lootsessions anzeigen."
L["Delete Entry"] = "Eintrag löschen"
L["Permanently delete the selected history record."] = "Lösche den ausgewählten Raid-Verlaufsdatensatz dauerhaft."
L["Select a session to view details."] = "Wähle eine Lootsession aus, um Details anzuzeigen."
L["Error: History entry not found or empty."] = "Fehler: Raid-Verlaufs-Eintrag nicht gefunden oder leer."
L["No attendees recorded."] = "Keine Teilnehmer aufgezeichnet."
L["Attendees (%d):"] = "Teilnehmer (%d):"
L["Attendance & Decay"] = "Anwesenheit & Verfall"
L["Open Full History"] = "Vollständigen Verlauf öffnen"
L["Open the combined raid history window for the selected session."] =
"Öffne das kombinierte Raid-Verlaufsfenster für die ausgewählte Sitzung."

-- History.lua
L["Session History"] = "Lootsession-Verlauf"
L["Session Loot History"] = "Sitzungs-Loot-Verlauf"
L["Select Date"] = "Datum auswählen"
L["Delete Date"] = "Datum löschen"
L["Re-award"] = "Neu vergeben"
L["No entries for this date."] = "Keine Einträge für dieses Datum."
L["Removed %d entries for %s"] = "%d Einträge für %s entfernt"
L["No loot awarded in this session."] = "Kein Loot in dieser Sitzung vergeben."

-- RaidHistory.lua
L["Raid History"] = "Raid-Verlauf"
L["Loot Awarded"] = "Vergebenes Loot"
L["Players Attended"] = "Anwesende Spieler"
L["Position Changes"] = "Positionsänderungen"
L["Decay Applied"] = "Verfall angewendet"
L["No position changes recorded."] = "Keine Positionsänderungen aufgezeichnet."
L["Position log not available (pre-dates session tracking)."] =
"Positionsprotokoll nicht verfügbar (älter als Sitzungsverfolgung)."
L["... and %d more entries"] = "... und %d weitere Einträge"
L["Position log only available for current session."] = "Positionsprotokoll nur für die aktuelle Sitzung verfügbar."
L["Decay disabled."] = "Verfall deaktiviert."
L["No decay applied yet."] = "Noch kein Verfall angewendet."
L["Decay of %d positions was applied when session ended."] =
"Ein Verfall von %d Positionen wurde beim Ende der Sitzung angewendet."

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
L["Session Monitor"] = "Lootsession-Monitor"
L["Pending Trades"] = "Ausstehender Handel"
L["Stop Session"] = "Lootsession beenden"
L["Loot Backlog"] = "Loot-Rückstand"
L["History"] = "Verlauf"
L["Attendance"] = "Anwesenheit"
L["Version Check"] = "Versionsprüfung"
L["Loot Backlog"] = "Loot-Rückstand"
L["History"] = "Verlauf"
L["Session History"] = "Sitzungs-Verlauf"
L["Attendance"] = "Anwesenheit"
L["Version Check"] = "Versionsprüfung"
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
L["Add Private Note"] = "Private Notiz hinzufügen"
L["Add note to Loot Master..."] = "Notiz an Plündermeister hinzufügen..."
L["Voter Note"] = "Wählernotiz"

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
L["No assigned items."] = "Keine zugewiesenen Gegenstände."


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
L["Addon Connection: [%d] / [%d]"] = "Addon-Verbindung: [%d] / [%d]"
L["Refresh (%.0fs)"] = "Aktualisieren (%.0fs)"
L["Refresh Connections"] = "Verbindungen aktualisieren"
L["Systems/Loot Loaded"] = "Systeme/Loot geladen"
L["Wiped stale loot backlog from previous session."] = "Veraltetes Loot aus vorheriger Lootsession gelöscht."
L["Added Item %d to '%s'"] = "Gegenstand %d zu '%s' hinzugefügt"
L["Item unassigned from all priority lists."] = "Gegenstand von allen Prioritätslisten entfernt."
L["Skipped low quality item: %s"] = "Gegenstände geringer Qualität übersprungen: %s"
L["--- LOOT SCAN START (%d slots) ---"] = "--- LOOT-SCAN START (%d Slots) ---"
L["--- SCAN END ---"] = "--- SCAN ENDE ---"
L["AUTO-ADDED from self-loot: %s"] = "AUTOM. HINZUGEFÜGT aus Eigenem Loot: %s"
L["AUTO-ADDED from roll: %s"] = "AUTOM. HINZUGEFÜGT aus Wurf: %s"
L["Loot backlog cleared (dedup store preserved)."] = "Loot-Rückstand bereinigt (Duplikatenspeicherung erhalten)."
L["Manually added: %s"] = "Manuell hinzugefügt: %s"
L["Winner of %s is %s! (%s)"] = "Gewinner von %s ist %s! (%s)"
L["You have been awarded %s! Trade me."] = "Dir wurde %s zugesprochen! Handel mich an."
L["Restored %d votes for re-awarded item."] = "%d Stimmen für neu vergebenen Gegenstand wiederhergestellt."
L["Re-awarded item: %s"] = "Gegenstand neu vergeben: %s"
L["Item reverted to bidding session."] = "Gegenstand in die Lootsession zurückgegeben."
L["Added test items to session."] = "Testgegenstände zur Lootsession hinzugefügt."
L["Triggered disenchanter scan via version check."] = "Entzauberer-Scan via Versionsprüfung ausgelöst."

-- Trade.lua (Systems)
L["Systems/Trade Loaded"] = "Systeme/Handel geladen"
L["Bypassed Blizzard trade confirmation: %s"] = "Blizzard-Handelsbestätigung umgangen: %s"
L["Staged %s for %s."] = "%s für %s bereitgestellt."
L["Could not find %s in bags for %s."] = "Konnte %s nicht in den Taschen für %s finden."
L["Trade complete. %s marked as delivered to %s."] = "Handel abgeschlossen. %s als an %s geliefert markiert."

-- Popups
L["Do you want to enable Autopass for this raid session?\n(Raid members will automatically pass on managed loot)"] =
"Möchtest du automatisches Passen für diese Raidsitzung aktivieren?\n(Raidmitglieder passen automatisch auf zugewiesene Beute)"
L["Enable"] = "Aktivieren"
L["A previous Loot Session is still active. Do you want to close it?"] =
"Eine vorherige Lootsession ist noch aktiv. Möchtest du sie schließen?"
L["Yes (Close Session)"] = "Ja (Sitzung schließen)"
L["No (Keep Active)"] = "Nein (Aktiv lassen)"
L["Are you sure you want to perform this action?"] = "Bist du sicher, dass du diese Aktion ausführen möchtest?"
L["Resume Session"] = "Lootsession fortsetzen"
L["Resuming active raid session."] = "Aktive Raid-Lootsession wird fortgesetzt."


L["Award Log"] = "Vergabe-Log"
L["Loot Log"] = "Loot-Log"
L["ToDebugString"] = "Debug-Zeichenfolge"
L["Toggle Disenchanters Sidebar"] = "Entzauberer-Seitenleiste umschalten"
L["You voted: %s%s|r%s"] = "Du hast abgestimmt: %s%s|r%s"
L["min"] = "Min."
L["sec"] = "Sek."
L["You have outstanding loot votes! Type /dlc vote to reopen."] =
"Du hast noch ausstehende Loot-Abstimmungen! Gib /dlc vote ein, um sie wieder zu öffnen."
L["|cffff8000Vote closing in %s \226\128\148 still need your vote:|r %s"] =
"|cffff8000Abstimmung schließt in %s \226\128\148 deine Stimme wird noch benötigt:|r %s"

-- New Keys
L["All window positions have been reset."] = "Alle Fensterpositionen wurden zurückgesetzt."
L["Warning: No Loot Master configured. Use /dlc config to set one."] =
"Warnung: Kein Plündermeister konfiguriert. Nutze /dlc config, um einen festzulegen."
L["Role Update: You are Loot Master."] = "Rollen-Update: Du bist Plündermeister."
L["Role Update: You are Raider."] = "Rollen-Update: Du bist Raider."
L["Loot Master"] = "Plündermeister"
L["Raider"] = "Raider"
L["Role Update: You are %s (LM: %s)"] = "Rollen-Update: Du bist %s (PM: %s)"
L["Added item: %s"] = "Gegenstand hinzugefügt: %s"
L["Added new Priority List: %s (Initialized with shuffled roster)"] =
"Neue Prioritätsliste hinzugefügt: %s (Mit geshuffelten Roster initialisiert)"
L["Removed Priority List: %s"] = "Prioritätsliste entfernt: %s"
L["Renamed list to: %s"] = "Liste umbenannt in: %s"
L["Only the Loot Master or Raid Assists can view the Loot History."] =
"Nur der Plündermeister oder Schlachtzugsassistenten können den Plünderungsverlauf einsehen."
L["Only the Loot Master can add items to the session."] =
"Nur der Plündermeister kann Gegenstände zur Sitzung hinzufügen."
L["Open the configuration window to manage settings, priority lists, and rosters."] =
"Öffne das Konfigurationsfenster, um Einstellungen, Prioritätslisten und Roster zu verwalten."
L["Open Settings Window"] = "Konfigurationsfenster öffnen"

L["Bosses & Pulls"] = "Bosse & Versuche"
L["No boss logs recorded for this session."] = "Keine Boss-Logs für diese Sitzung aufgezeichnet."

L["Ready to Craft"] = "Bereit zum Herstellen"
L["Unskilled"] = "Fehlender Skill"
L["Ready"] = "Bereit"
L["Roll to receive this recipe because you have the profession and required skill to craft it."] =
"Würfeln, um dieses Rezept zu erhalten, da du den Beruf und die benötigte Fertigkeit besitzt, um es herzustellen."
L["Roll for this recipe even though you do not meet the skill or profession requirements yet."] =
"Für dieses Rezept würfeln, obwohl du die Fertigkeits- oder Berufsanforderungen noch nicht erfüllst."
L["Pass on this recipe."] = "Auf dieses Rezept passen."
L["Bid priority points on this item."] = "Prioritätspunkte auf diesen Gegenstand bieten."
L["Roll for main spec usage."] = "Für Hauptspezialisierung würfeln."
L["Roll for offspec usage."] = "Für Nebenspezialisierung würfeln."
L["Roll for transmogrification collection."] = "Für Transmogrifikationssammlung würfeln."
L["Pass on this item."] = "Auf diesen Gegenstand passen."
L["Trade window full. Remaining items will be staged in the next trade."] =
"Handelsfenster voll. Verbleibende Gegenstände werden beim nächsten Handel bereitgestellt."

-- Handover & Decay popups
L["No Loot Master has been detected in the group for 60+ seconds. Do you want to claim the Loot Master role?"] =
"Kein Plündermeister im Schlachtzug seit 60+ Sekunden erkannt. Möchtest du die Plündermeister-Rolle beanspruchen?"
L["Yes (Claim LM)"] = "Ja (PM beanspruchen)"
L["%s is handing you the Loot Master role. Accept?"] = "%s übergibt dir die Plündermeister-Rolle. Akzeptieren?"
L["Accept"] = "Akzeptieren"
L["Decline"] = "Ablehnen"
L["The last raid session (%s, %s) has pending decay. Apply decay now before starting a new session?"] =
"Die letzte Schlachtzugssitzung (%s, %s) hat ausstehenden Verfall. Verfall jetzt anwenden, bevor eine neue Sitzung gestartet wird?"
L["Apply Decay"] = "Verfall anwenden"
L["Skip"] = "Überspringen"
L["Review First"] = "Zuerst prüfen"
L["Claim LM Role"] = "PM-Rolle beanspruchen"
L["No Loot Master is detected in the raid. Claim the role to enable session management."] =
"Kein Plündermeister im Schlachtzug erkannt. Beanspruche die Rolle, um das Sitzungsmanagement zu aktivieren."
L["Hand Over LM Role"] = "PM-Rolle übergeben"
L["Start the handover process to the selected officer."] = "Starte den Übergabeprozess an den ausgewählten Offizier."
L["Choose an officer in the raid to hand over the Loot Master role to."] =
"Wähle einen Offizier im Schlachtzug aus, an den die Plündermeister-Rolle übergeben werden soll."
L["Select Officer for Handover"] = "Offizier für die Übergabe auswählen"

-- EJ Loot Import
L["DLC"] = "DLC"
L["Add to IM"] = "Zum IM hinzufügen"
L["DLC Loot Import"] = "DLC Loot Import"
L["%d items staged across %d lists"] = "%d Gegenstände in %d Listen vorbereitet"
L["— Skip —"] = "— Überspringen —"
L["No loot found for this boss."] = "Keine Beute für diesen Boss gefunden."
L["Add all loot from this boss/raid to the import staging area."] =
"Alle Beute von diesem Boss/Raid zum Import-Bereich hinzufügen."
L["Officer only."] = "Nur Offiziere."
