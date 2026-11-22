// Test subscriber (same keys as the free5GC testbed), schema from open5gs-dbctl add_ue_with_slice.
function sess() { return [{ name: "internet", type: NumberInt(3),
  qos: { index: NumberInt(9), arp: { priority_level: NumberInt(8), pre_emption_capability: NumberInt(1), pre_emption_vulnerability: NumberInt(2) } },
  ambr: { downlink: { value: NumberInt(1000000000), unit: NumberInt(0) }, uplink: { value: NumberInt(1000000000), unit: NumberInt(0) } },
  pcc_rule: [], _id: new ObjectId() }]; }
db.subscribers.deleteMany({ imsi: "208930000000001" });
db.subscribers.insertOne({ _id: new ObjectId(), schema_version: NumberInt(1), imsi: "208930000000001",
  msisdn: [], imeisv: [], mme_host: [], mm_realm: [], purge_flag: [],
  slice: [ { sst: NumberInt(1), sd: "010203", default_indicator: true, session: sess(), _id: new ObjectId() },
           { sst: NumberInt(1), sd: "112233", default_indicator: false, session: sess(), _id: new ObjectId() } ],
  security: { k: "8baf473f2f8fd09487cccbd7097c6862", op: null, opc: "8e27b6af0e692e750f32667a3b14605d", amf: "8000" },
  ambr: { downlink: { value: NumberInt(1000000000), unit: NumberInt(0) }, uplink: { value: NumberInt(1000000000), unit: NumberInt(0) } },
  access_restriction_data: 32, network_access_mode: 0, subscriber_status: 0, operator_determined_barring: 0,
  subscribed_rau_tau_timer: 12, __v: 0 });
print("subscribers:", db.subscribers.countDocuments({}));
