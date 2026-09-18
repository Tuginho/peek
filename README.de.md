# Peek

English: [README.md](README.md)

<p align="center"><img src="Resources/AppIcon-256.png" width="128" alt="Peek icon"></p>

## Was Peek macht

Peek ist eine native macOS-Menüleisten-App. Sie zeigt Fenster-Vorschauen beim
Hovern über Dock-Icons und macht Cmd+H so, dass nur das aktuell fokussierte
Fenster versteckt wird, statt die ganze App.

Peek läuft ohne Dock-Icon in der Menüleiste und ist nicht sandboxed.

## Herunterladen

`Peek-<Version>.zip` von der Releases-Seite des Repositories herunterladen,
entpacken, `Peek.app` nach `/Applications` verschieben, öffnen und die
angefragten Berechtigungen erteilen. Release-Builds sind universal (Apple
Silicon und Intel) und benötigen macOS 14 oder neuer.

Release-Builds sind nicht mit einer kostenpflichtigen Apple Developer ID
signiert und nicht notarisiert, deshalb blockiert Gatekeeper den ersten
Start. Das lässt sich über Systemeinstellungen → Datenschutz & Sicherheit →
„Dennoch öffnen" erlauben, oder das Quarantäne-Flag selbst entfernen:

```
xattr -dr com.apple.quarantine /Applications/Peek.app
```

Da die App nicht mit einer Developer ID signiert ist, bindet macOS die
erteilten Berechtigungen an das genaue Binary. Nach jedem Update müssen
Bedienungshilfen und Bildschirmaufnahme deshalb erneut erteilt werden; vorher
den alten Peek-Eintrag aus der jeweiligen Berechtigungsliste entfernen.

Wer stattdessen aus dem Quellcode baut (siehe „Bauen (aus dem Quellcode)"
unten) und mit `./scripts/install.sh` installiert, umgeht die
Gatekeeper-Abfrage, und mit einer kostenlosen „Apple Development"-Identity
bleiben die Berechtigungen auch über Rebuilds hinweg erhalten.

## Voraussetzungen

Das Folgende wird nur zum Bauen aus dem Quellcode benötigt; wer oben einen
Release-Build heruntergeladen hat, kann diesen Abschnitt überspringen.

- macOS 14 oder neuer
- Xcode mit Swift 6 Toolchain (`swift build`)
- Empfohlen: ein „Apple Development"-Zertifikat im Schlüsselbund (kostenlose
  Apple-ID in Xcode → Settings → Accounts genügt)

## Bauen (aus dem Quellcode)

```
./scripts/build.sh
```

Baut `build/Peek.app` im Release-Modus und signiert sie. Das Skript nimmt die
erste „Apple Development"-Identity aus dem Schlüsselbund; eine andere lässt
sich mit `PEEK_SIGN_IDENTITY=<SHA-1 oder Name>` vorgeben. Ohne Identity wird
ad-hoc signiert – dann verwirft macOS die erteilten Berechtigungen bei jedem
neuen Build.

Tests: `swift test`. In Xcode öffnen: `open Package.swift` (zum Ausführen
trotzdem das Skript verwenden, weil Berechtigungen, `LSUIElement` und
Login-Start das App-Bundle brauchen).

## Installieren/Starten

```
./scripts/install.sh
```

Baut die App, beendet eine laufende Instanz, ersetzt `/Applications/Peek.app`
und startet sie.

## Berechtigungen

Peek fragt beim ersten Start drei Berechtigungen ab (Menü → Berechtigungen…):

- **Bedienungshilfen**: Dock-Hover erkennen, Fenster steuern, Cmd+H abfangen.
- **Bildschirmaufnahme**: Fenster-Thumbnails aufnehmen. Nach dem Erteilen muss
  Peek neu gestartet werden, sonst bleibt die Freigabe ohne Wirkung.
- **Eingabeüberwachung** (optional): nur nötig, falls Cmd+H trotz
  Bedienungshilfen nicht reagiert.

## Cmd+H

Peek fängt Cmd+H ab und versteckt nur das gerade fokussierte Fenster der
vordersten App, statt die ganze App zu verstecken. Standardmäßig „parkt“
Peek das Fenster: Es verschiebt es fast vollständig aus dem sichtbaren
Bereich in eine freie Bildschirmecke (ein Streifen von 1 pt Breite und etwa
100 pt Höhe bleibt sichtbar) und beim
Zurückholen wieder an seine alte Position – beides ohne Animation. Über die
Einstellung „Verstecken per“ lässt sich stattdessen klassisches Minimieren
(mit der System-Animation) wählen. Ein anderes Fenster derselben App wird
danach automatisch nach vorne geholt; gibt es keins, fällt Peek auf das
normale Cmd+H (App verstecken) zurück. Peek merkt sich die von ihm
versteckten Fenster und holt sie wieder zurück, wenn im Dock auf das
App-Icon geklickt wird oder die App erneut aktiviert wird (je nach
Einstellung „Beim Aktivieren wiederherstellen“). Über die Einstellung
„Wiederherstellung bei Dock-Klick“ lässt sich wählen, ob dabei nur die von
Peek versteckten Fenster oder alle minimierten Fenster der App
zurückgeholt werden.

Peek fällt automatisch auf das native Cmd+H zurück, wenn das fokussierte
Fenster im Vollbildmodus ist, sich weder parken noch minimieren lässt, oder
wenn Secure Input aktiv ist (z. B. ein Passwortfeld hat den Fokus) und der
Event-Tap deshalb keine Tastendrücke sieht.

In den Einstellungen lässt sich Cmd+H für bestimmte Apps über die
Ausnahmeliste (Bundle-IDs) deaktivieren; für diese Apps verhält sich Cmd+H
wie gewohnt.

## Dock-Vorschau

Wenn der Mauszeiger über dem Dock-Symbol einer laufenden App verweilt, zeigt
Peek nach einer kurzen Verzögerung ein schwebendes Panel mit Vorschaubildern
aller Fenster dieser App – direkt über (oder neben, je nach Dock-Position)
dem Symbol. Jedes Fenster ist mit seinem Zustand markiert:

- **versteckt**: von Peek per Cmd+H versteckt.
- **minimiert**: normal minimiert (nicht über Peek).
- **ausgeblendet**: die App selbst ist ausgeblendet (Cmd+Option+H).

Ein Klick auf eine Vorschau holt das Fenster nach vorne. Beim Überfahren
einer Kachel erscheinen zwei Schaltflächen: Verstecken (nur bei sichtbaren
Fenstern) und Schließen. Das Panel bleibt offen, solange sich der Zeiger auf
dem Dock-Symbol, dem Panel oder dem Weg dazwischen befindet, und schließt
sich sonst automatisch.

Über jedem Dock-Symbol mit von Peek versteckten Fenstern zeichnet Peek
außerdem ein kleines Badge mit der Anzahl. macOS bietet dafür keine offizielle
API, das Badge ist ein eigenes, klickdurchlässiges Overlay-Fenster. Es
verschwindet kurzzeitig, während der Zeiger über dem Dock liegt (die
Dock-Vergrößerung würde die Position sonst verfälschen), und erscheint
danach wieder. In den Einstellungen lässt es sich ganz abschalten.

## Diagnose

Menü → Diagnose ausführen. Das Fenster zeigt den Report live, während er
läuft. Der komplette Report wird zusätzlich unter
`~/Library/Logs/Peek/diagnose-<Zeitstempel>.log` gespeichert.

## Einschränkungen

- „Verstecken" (Standardmethode „Parken") bewegt das Fenster fast vollständig
  aus dem sichtbaren Bereich, statt es unsichtbar zu machen – macOS bietet
  dafür keine API. Mission Control zeigt geparkte Fenster weiterhin an, und
  Cmd+` kann sie auswählen. Ein Streifen von 1 pt Breite und etwa 100 pt Höhe
  (plus Fensterschatten) bleibt in einer Bildschirmecke sichtbar, weil macOS
  kein Fenster vollständig außerhalb des Bildschirms zulässt. Vollbild-Fenster lassen sich nicht parken (Fallback: App
  ausblenden). Beim Beenden holt Peek geparkte Fenster automatisch zurück;
  nach einem Absturz übernimmt Peek sie beim nächsten Start wieder, und sie
  kommen auch per Dock-Klick zurück.
- In der Dock-Vorschau werden nur Fenster auf gerade sichtbaren Spaces
  aufgelistet (plus minimierte).
- Minimierte Fenster lassen sich nicht aufnehmen. Ihre Thumbnails stammen aus
  dem Cache von vorher; ohne Cache-Bild zeigt das Panel einen Platzhalter.
  Geparkte Fenster werden weiterhin live aufgenommen.
- macOS 15 und neuer fragt die Bildschirmaufnahme-Freigabe in Abständen neu
  ab. Ohne Freigabe zeigt die Vorschau Platzhalter statt Bilder.
- Bei aktivem Secure Input (Passwortfelder, Terminal „Secure Keyboard Entry")
  sieht Peek keine Tastendrücke; Cmd+H verhält sich dann wie gewohnt.

## Fehlersuche

- Cmd+H blendet weiter die ganze App aus: Menü → Berechtigungen… prüfen
  (Bedienungshilfen), Schalter „Cmd+H nur für aktuelles Fenster" und
  Ausnahmeliste prüfen.
- Keine Thumbnails: Bildschirmaufnahme erteilen und Peek neu starten.
- Kein Panel beim Hovern: Menü → Diagnose ausführen; der Abschnitt „Dock hover
  notifications" muss beim Überfahren der Icons Einträge zeigen.
- Berechtigungen nach einem Build verloren: die App war ad-hoc signiert, siehe
  „Bauen".
