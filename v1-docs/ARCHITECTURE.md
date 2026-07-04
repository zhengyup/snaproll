# Architecture

## Product

Snaproll is a native iOS app that lets groups capture limited photos during an event and reveal them together later.

Core flow:

Create Event
→ Join Event
→ Take Limited Photos
→ Album Locked
→ Album Revealed

---

## Tech Stack

Frontend:

* SwiftUI

Camera:

* AVFoundation

Storage:

* Local device storage (MVP)
* Supabase (future)

Platform:

* iOS only

---

## Screens

Home

* Create Event
* Join Event

Create Event

* Event name
* Shot limit
* Unlock time

Event

* Event details
* Shot count
* Open Camera
* View Album

Camera

* Take photo
* No photo review

Locked Album

* Countdown
* No photo access

Gallery

* Revealed photos

---

## Models

Event

* id
* name
* shotLimit
* unlockTime

Member

* id
* displayName
* shotsUsed

Photo

* id
* eventId
* memberId
* localPath
* createdAt

---

## Development Order

Phase 1

* App navigation

Phase 2

* Event creation

Phase 3

* Camera capture

Phase 4

* Save photos locally

Phase 5

* Shot limit

Phase 6

* Locked album

Phase 7

* Reveal gallery

Phase 8

* Supabase backend

---

## Rules

* iOS only
* Native SwiftUI
* No Android
* No PWA
* No filters
* No social feed
* Keep MVP simple
