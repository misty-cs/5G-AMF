package gmm

// ch5 state-use trace (research instrumentation, not for upstream).
// Logs, for a UE whose context came from another AMF:
//   received  - the UeContext JSON returned by UEContextTransfer
//   copied    - the AMF's per-UE state right after CopyDataFromUeContextModel
//   accept    - the same state when Registration Accept is sent
// Keys are reduced to a SHA-256 prefix.

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"

	"github.com/free5gc/amf/internal/context"
	"github.com/free5gc/openapi/models"
)

func ch5Hash(s string) string {
	if s == "" {
		return ""
	}
	h := sha256.Sum256([]byte(s))
	return hex.EncodeToString(h[:4])
}

func ch5TraceReceived(ue *context.AmfUe, uc *models.Amf_Comm_UeContext) {
	b, err := json.Marshal(uc)
	if err != nil {
		ue.GmmLog.Infof("ch5trace received marshal error: %v", err)
		return
	}
	// redact key material before logging
	var m map[string]interface{}
	if json.Unmarshal(b, &m) == nil {
		if sd, ok := m["seafData"].(map[string]interface{}); ok {
			if k, ok := sd["keyAmf"].(map[string]interface{}); ok {
				if v, ok := k["keyVal"].(string); ok {
					k["keyVal"] = "sha256:" + ch5Hash(v)
				}
			}
			if v, ok := sd["nh"].(string); ok {
				sd["nh"] = "sha256:" + ch5Hash(v)
			}
		}
		if r, err := json.Marshal(m); err == nil {
			b = r
		}
	}
	ue.GmmLog.Infof("ch5trace received %s", b)
}

func ch5TraceState(ue *context.AmfUe, stage string) {
	m := map[string]interface{}{
		"supi": ue.Supi, "pei": ue.Pei, "guti": ue.Guti, "gpsi": ue.Gpsi,
		"udmGroupId": ue.UdmGroupId, "ausfGroupId": ue.AusfGroupId, "routingIndicator": ue.RoutingIndicator,
		"ngKsi": ue.NgKsi, "kamfHash": ch5Hash(ue.Kamf),
		"integrityAlg": ue.IntegrityAlg, "cipheringAlg": ue.CipheringAlg,
		"ulCount": ue.ULCount.Get(), "dlCount": ue.DLCount.Get(),
		"pcfId": ue.PcfId, "pcfAmPolicyUri": ue.AmPolicyUri,
		"allowedNssai3gpp": ue.AllowedNssai[models.AccessType_3_GPP_ACCESS],
		"subscribedNssaiCount": len(ue.SubscribedNssai),
		"traceData": ue.TraceData,
		"ueEventSubscriptions": len(ue.EventSubscriptionsInfo),
	}
	if am := ue.AccessAndMobilitySubscriptionData; am != nil {
		m["subUeAmbr"] = am.SubscribedUeAmbr
		m["subRfsp"] = am.RfspIndex
		m["restrictedRatList"] = am.RatRestrictions
		m["forbiddenAreaList"] = am.ForbiddenAreas
		m["serviceAreaRestriction"] = am.ServiceAreaRestriction
	}
	if ue.AmPolicyAssociation != nil {
		m["amPolicyReqTriggerList"] = ue.AmPolicyAssociation.Triggers
	}
	sm := 0
	ue.SmContextList.Range(func(_, _ interface{}) bool { sm++; return true })
	m["sessionContexts"] = sm
	ev := 0
	context.GetSelf().EventSubscriptions.Range(func(_, v interface{}) bool {
		if s, ok := v.(*context.AMFContextEventSubscription); ok {
			if s.EventSubscription.Supi == ue.Supi {
				ev++
			} else {
				for _, x := range s.UeSupiList {
					if x == ue.Supi {
						ev++
						break
					}
				}
			}
		}
		return true
	})
	m["amfEventSubscriptionsForSupi"] = ev
	b, err := json.Marshal(m)
	if err != nil {
		ue.GmmLog.Infof("ch5trace %s marshal error: %v", stage, err)
		return
	}
	ue.GmmLog.Infof("ch5trace %s %s", stage, b)
}
