# TLS / HTTPS recommendations

This guide is for **developers integrating the `formbricks_flutter` package**
into their app, especially when pointing the SDK at a **self-hosted Formbricks
instance**. It explains the SDK's TLS requirements and how to make a self-hosted
instance load correctly.

## How the SDK uses TLS

The SDK talks to your Formbricks instance URL (`appUrl` in the config) in two places, and **both use the device's standard certificate validation** (the OS trust store):

1. **REST calls** — fetching workspace + user state from `appUrl/api/...`.
2. **The survey WebView** — the survey UI is rendered in the platform WebView
   (WKWebView on iOS, the system WebView on Android), which loads the Formbricks
   survey runtime from `appUrl/js/surveys.umd.cjs` and submits responses back to
   `appUrl`.

The SDK does **not** weaken, bypass, or pin certificate validation. There is no
"trust all certificates" option — by design, so survey traffic can't be
intercepted (man‑in‑the‑middle).

## Requirements (what "just works")

Surveys load with **zero extra configuration** when your `appUrl` is HTTPS with a
certificate the device already trusts:

- ✅ **Publicly‑trusted HTTPS** — Formbricks Cloud, or a self‑hosted instance with
  a certificate from a public CA (e.g. **Let's Encrypt**). **This is the
  recommended setup.**
- ✅ **TLS 1.2 or newer** with modern cipher suites.
- ✅ The certificate's hostname (SAN) **matches the exact host** in your `appUrl`.

```dart
Formbricks(
  appUrl: 'https://surveys.example.com', // HTTPS, trusted cert
  workspaceId: 'wsp_...',
)
```

## Symptom of a TLS problem

If the device doesn't trust your server's certificate, the survey **modal opens
blank or never appears**, and (with debug logging on) you'll see something like
`Failed to load Formbricks Surveys library` in the console. The TLS handshake to
your server was rejected before the survey runtime could load.

> A common misread of this is _"the SDK doesn't support TLS."_ It does — it just
> refuses certificates the device's OS doesn't trust.

## Self‑hosting scenarios & fixes

### Self‑signed certificate, or an internal/corporate CA

The most common cause. The device has no trust anchor for your certificate, so
the connection is cancelled. **Fix it at the OS/network layer** — do not disable
validation:

- **Easiest:** put a **publicly‑trusted certificate** in front of your instance
  (e.g. Let's Encrypt). No app changes; fixes both the WebView and the REST
  calls.
- **Internal CA:** install your CA root on the device so it's trusted:
  - **iOS** — distribute the CA via an **MDM / configuration profile**, then
    enable full trust under _Settings → General → About → Certificate Trust
    Settings_.
  - **Android** — bundle the CA in **your app's** network security config (see
    below), or push it via MDM.

### Hostname mismatch or expired certificate

Reissue/renew the certificate so its SAN matches the exact host in `appUrl`, and
keep it current (automate renewal). Pointing `appUrl` at a raw IP or an internal
DNS name the certificate wasn't issued for will fail validation.

### Old TLS version

Enable **TLS 1.2+** on your server/reverse proxy. Modern WebViews refuse TLS
1.0/1.1 and weak ciphers.

### Mutual TLS (client certificates)

If your server requires a **client** certificate, the WebView presents none and
the connection fails. This is **not configurable in the SDK** — provision the
client identity at the OS level (iOS keychain via MDM/SCEP, Android `KeyChain`),
or front Formbricks with a gateway that handles mTLS and serves a normal trusted
certificate to the device.

## Android: trusting an internal CA (example)

Add a network security config to **your app** that trusts your CA, scoped to your
Formbricks domain only (so you don't broaden trust for the rest of the app):

`android/app/src/main/res/xml/network_security_config.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
  <domain-config>
    <domain includeSubdomains="true">surveys.example.com</domain>
    <trust-anchors>
      <!-- Your internal CA, bundled in the app's res/raw/ -->
      <certificates src="@raw/my_internal_ca" />
      <!-- Keep the public CAs too, so other traffic still works -->
      <certificates src="system" />
    </trust-anchors>
  </domain-config>
</network-security-config>
```

Reference it from `android/app/src/main/AndroidManifest.xml`:

```xml
<application
    android:networkSecurityConfig="@xml/network_security_config"
    ...>
```

## iOS notes (App Transport Security)

- iOS requires **HTTPS with TLS 1.2+** by default.
- For an **internal CA**, install it via an MDM/configuration profile and trust it
  (as above) — no app changes needed.
- A plaintext **`http://`** `appUrl` is blocked by App Transport Security. We
  **strongly recommend HTTPS** and do not bundle an ATS exception; if you must use
  HTTP for local development, add your own ATS exception to your app's
  `Info.plist` (not recommended for production).

## A note on plaintext HTTP

The SDK technically accepts an `http://` `appUrl`, but both platforms block
cleartext traffic by default (iOS ATS; Android cleartext policy on API 28+).
**Use HTTPS in production.** HTTP, if used at all, is for local development only.

## Required app permission (Android)

The host app must declare the internet permission so the WebView can load the
survey runtime:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```
