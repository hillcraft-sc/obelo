# Privacy

Obelo is software you run on your own server. The people who make it do not run a service, do not have your data, and cannot see it.

## What the Obelo project collects

Nothing. There is no Obelo cloud, no account with us, no analytics, no advertising and no crash reporting in the server or in the iPhone, iPad and Mac apps. The apps talk only to the server address you give them.

## This website

This website is static pages. It has no cookies, no analytics and no forms, and its server keeps no access log. It is served through Cloudflare, which carries the traffic and can see that a visit happened, as with any site behind it.

## Your own Obelo server

Your tasks, notes, reminders, routines, calendar items, lists and bookmarks are stored in the database on the server you run. The person who runs that server can see everything on it, as with any self-hosted service. If you use someone else's Obelo server, ask them how they run it.

Private and locked notes are kept out of AI features, search results for other people, and logs.

## What a server you run can contact

The core of Obelo needs no outside service. These features contact one when you turn them on:

| When | Who is contacted | What they learn |
|---|---|---|
| A person has no uploaded profile picture | Gravatar, from their browser | A hash of their email address |
| Viewing Bookmarks | DuckDuckGo's icon service, from their browser | The domains of the bookmarked sites |
| AI Chat or Capture, if an AI provider is set up | That provider, from the server | The text asked or captured, plus for AI Chat a summary of the person's data (never private or locked notes). A local model keeps all of this in-house |
| Calendar sync, if connected | Google, iCloud or your CalDAV server | Normal calendar access for that account |
| Push notifications | Pushover, or your own ntfy server | The notification text. With a self-hosted ntfy, iPhones also get a wake-up signal relayed through ntfy.sh (a message ID only) |
| Email | Your email (SMTP) provider | The email content |
| Pages served through Cloudflare, if the host turns on its Web Analytics | Cloudflare | Page-view analytics |

A person can avoid the Gravatar request by uploading a profile picture. Whoever runs the server decides which of the others are on.

## The apps

The apps keep your sign-in on your device and send your requests only to your server. They ask for access to your photos or camera when you add a picture to a note, and to the microphone and speech recognition when you dictate a capture. Dictation uses Apple's speech recognition, which is governed by Apple's privacy policy, not ours.

## Changes

If this policy changes, the new version appears on this page and in the project's [change history](https://github.com/hillcraft-sc/obelo/commits/main/docs/PRIVACY.md).
