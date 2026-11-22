# Patch inventory — what each local change does (2026-11-08)

Every result in this project was produced with a specific set of local patches to free5GC (AMF) or
UERANSIM. This file lists each patch, what it changes, its specification basis, the image tag that
contains it, and which experiments used it. Original images are kept, so every earlier result can be
reproduced with the image it was measured with.

**Rule for interpreting results:** a patch can only enable behaviour that the specification requires;
any finding measured *after* a patch is a finding about the patched stack and must say so.

## free5GC AMF (base: free5gc/amf `main` @ b62608072087102cd3154d6fc5552376e0697e47)

| Patch (file) | What it changes | Spec basis | Image tag(s) | Used by |
|---|---|---|---|---|
| **#111 fix** `ch5-decipher-container-after-transfer.patch` | After a successful UEContextTransfer, deciphers the NAS message container of the protected Initial Registration and replaces the registration request with the inner message. Without it the AMF never processes the container and rejects with cause #111. | TS 24.501 §4.4.6 (AMF shall decipher the container); TS 23.502 §4.2.2.2.2 | `:fixed`, `:fixed-trace`, `:fixed-trace-realloc` | Exp 1 (fix rows), 2, 3, 4b, 5 |
| **State-use trace** `ch5_trace.go` + sed hooks | Logging only: logs the received UeContext (keys hashed), the state after copy, and the state at Registration Accept. No behaviour change. | — (instrumentation) | `:fixed-trace`, `:main-trace`, `:fixed-trace-realloc` | Exp 2, 4b, 5 |
| **Re-allocation target fix** `ch5-realloc-target-ranue.patch` (part 1, `callback.go`) | When N1MessageNotify arrives for a RAN UE NGAP ID this AMF has no record of, creates the RanUe instead of returning 404. | TS 23.502 §4.2.2.2.3 step 7(A)/8; TS 38.413 §8.6.2.2 | `:fixed-trace-realloc` | Exp 5 only |
| (part 2, `callback.go`) | Sets the new RanUe's TAI from the forwarded user location (otherwise the empty TAI fails the TAI check → TA_NOT_ALLOWED). | Needed for part 1 to work; no new behaviour | `:fixed-trace-realloc` | Exp 5 only |
| (part 3, `handler.go` + `sm.go`) | After a successful N1MessageNotify the initial AMF stops processing the registration but **keeps** the UE context (sentinel error that the state machine skips). Without it the initial AMF also sends its own Registration Accept. An earlier version of this part deregistered the UE; it was replaced because it caused an artefactual 404. | TS 23.502 §4.2.2.2.3 step 7(A)/8 (the target continues the procedure) | `:fixed-trace-realloc` | Exp 5 only |
| **realloc2** `ch5-realloc2-step8.patch` (applied on top of the re-allocation target fix) | (1) Initial AMF adds the MM/security context (`seafData`, `mmContextList`) to the N1MessageNotify UE context, built as the UEContextTransfer producer does (`gmm/ch5_realloc.go`). (2) Target marks the received security context available and derives NAS keys. (3) Target does not reject the forwarded mobility registration with #10 because its new UE record is "deregistered". (4) Target skips a second UEContextTransfer when the context already arrived by N1MessageNotify. (5) Target does not treat the forwarded clear-text Registration Request as a MAC failure (one-shot flag, only for that message). | TS 23.502 §4.2.2.2.3 step 7(A) ("the UE's SUPI and MM Context if available"; message "in clear text"), step 8 ("continues with the Registration procedure"; "continue using" the received 5G security context) | `:fixed-trace-realloc2` | Exp 5 (realloc2 runs) |
| **GUTI repair** `ch5-guti-repair.patch` (2026-11-10, applied after the #111 fix) | When `ServingAmfChanged` is set, the new AMF calls `AllocateGutiToUe` before Registration Accept (in `HandleInitialRegistration` and `HandleMobilityAndPeriodicRegistrationUpdating`), so the Accept carries a 5G-GUTI from its own GUAMI. Otherwise the AMF logs "Use original GUTI" and keeps the old AMF's GUTI. A repair *test*: it checks whether the unrefreshed GUTI causes the periodic-registration rejection. | TS 33.501 §6.12.3 (new 5G-GUTI at initial/mobility registration); TS 23.502 §4.2.2.2.2 step 21 | `:fixed-gutirepair` | GUTI repair test (`gr_*` runs) only |
| **Re-allocation trace** `ch5-realloc-trace.patch` | Logging only: logs the UeContext received via N1MessageNotify (key material redacted). | — (instrumentation) | `:fixed-trace-realloc` | Exp 5 only |

## UERANSIM (base: `master` @ 4f45e18f80b0684f7d6e29f1fea0f579e9243d68)

| Patch | Side | What it changes | Spec basis | Image tag(s) | Used by |
|---|---|---|---|---|---|
| 1 | UE | Keeps the current native NAS security context on reject cause #10. | TS 24.501 §5.5.1.3.5 | `:patched`, `:patched5`, `:patched6` | Exp 1–5 |
| 2 | UE | Keeps the in-memory context at the start of initial registration. | TS 24.501 §4.4.2.1.2 | same | Exp 1–5 |
| 3 | UE | Same sentence, on leaving 5GMM-DEREGISTERED. | TS 24.501 §4.4.2.1.2 | same | Exp 1–5 |
| 4 | UE | Removes Requested NSSAI from the cleartext REGISTRATION REQUEST. Side effect: the gNB (which reads the slice from NAS, not RRC) cannot route by slice. | TS 24.501 §4.4.6 | same | Exp 1–5 |
| 5 | gNB | On a DOWNLINK NAS TRANSPORT / INITIAL CONTEXT SETUP REQUEST that carries the **Old AMF IE** from a different AMF, re-associates the UE with that AMF and adopts its AMF UE NGAP ID. Upstream rejects it as an inconsistent remote UE NGAP ID. | TS 38.413 §8.6.2.2, §8.3.1.2 ("shall use … even if the RAN UE NGAP ID IE had been allocated … over a different NG interface instance") | `:patched5`, `:patched6` | Exp 5 only |
| 6 | UE | Adds CLI `slice-add <sst> <sd>`: appends a slice to the configured NSSAI and starts a mobility registration update with cause SLICE_CHANGE (the cause exists upstream but nothing triggers it). | TS 24.501 §5.5.1.3.2 | `:patched6` | Exp 5 (registered-UE runs) |
| 7 | UE | Mobility and periodic REGISTRATION REQUEST carry the ngKSI of the current native 5G NAS security context, as the initial REGISTRATION REQUEST already does. Upstream `sendMobilityRegistration` never sets it, so the message says "no key available" (7) and the AMF must re-authenticate. Added 2026-11-22. | Consistency with the initial registration; TS 24.501 §4.4.6 (the UE protects the initial NAS message with its current context) | `:patched7` (built with `PATCH5=1 PATCH7=1`) | Exp 4 Open5GS controls (`traffic_*_p7_*`) only. Called **patch 5** in the NetSoft paper (Table III), which lists only the UE patches it uses. |
| rt_tables | UE image | Copies `/usr/share/iproute2/rt_tables` to `/etc/iproute2/` so the UE TUN interface can be configured. No protocol change. | — | `:patched5`, `:patched6` | (future user-plane test) |

## What is *not* patched (and therefore measured)
- free5GC's choice to reject a mobility registration with a foreign GUTI with cause #10.
- What the initial AMF puts in the N1MessageNotify UE context — measured *before* realloc2 (it omits the security context); realloc2 adds it.
- The target AMF's handling of the forwarded registration — measured *before* realloc2 (#10 reject, re-authentication); realloc2 changes it.
- Under every patch level: whether the target applies the transferred event subscriptions, whether it reallocates the GUTI, and how it handles restrictions and policy (never patched). Exception: `:fixed-gutirepair` changes GUTI reallocation, and is used only in the GUTI repair test (`gr_*` runs), never for the measured GUTI finding.
- free5GC refreshing the GUTI on receipt of a registration rather than on Accept.
- Authentication with a SUPI but no SUCI after a failed context transfer (AUSF 400 → CONGESTION).
- Everything in Open5GS (no Open5GS patches).
