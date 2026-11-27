import { registerHooks } from "node:module";

// The image is pinned in open-parcels.nix. Recheck this patch when updating it.
const original = `    const routed = await this.deps.router.read(connectionId, mail, checkSenders);
    if (routed !== null) return routed;
    return {
      snapshots: this.#interpret(connectionId, mail, this.deps.interpret),
      returns: this.#interpret(connectionId, mail, this.deps.interpretReturns),
      orders: this.#interpret(connectionId, mail, this.deps.interpretOrders)
    };`;

const replacement = `    const routed = await this.deps.router.read(connectionId, mail, checkSenders);
    const reading = routed ?? {
      snapshots: this.#interpret(connectionId, mail, this.deps.interpret),
      returns: this.#interpret(connectionId, mail, this.deps.interpretReturns),
      orders: this.#interpret(connectionId, mail, this.deps.interpretOrders)
    };
    const domain = senderDomain(mail.from);
    if (!domain || (checkSenders && !authenticatedSender(mail.authentication, domain))) return reading;
    const numbers = localDhlTrackingNumbers(mail, domain);
    const existing = new Set(reading.snapshots.filter(parcel => parcel.carrier === "dhl")
      .map(parcel => parcel.trackingNumber));
    const additions = numbers.filter(number => !existing.has(number))
      .map(trackingNumber => snapshot({ carrier: "dhl", trackingNumber }));
    return { ...reading, snapshots: [...reading.snapshots, ...additions] };`;

export function localDhlTrackingNumbers(mail, senderDomain) {
  const numbers = new Set();
  for (const body of [mail.text, mail.html]) {
    for (const [link] of (body ?? "").matchAll(/https:\/\/[^\s"'<>]+/g)) {
      const url = URL.parse(link.replace(/&(?:amp|#38|#x26);/gi, "&"));
      if (!url || url.username || url.password || url.port) continue;

      let param;
      if (
        senderDomain === "dhl.de" &&
        url.hostname === "custcomm.dhl.de" &&
        /^\/go\/[^/]+\/[^/]+\.html$/i.test(url.pathname)
      ) {
        param = "piececode";
      } else if (
        url.hostname === "www.dhl.com" &&
        /^\/[a-z]{2}-[a-z]{2}\/home\/tracking\/tracking-parcel\.html$/i.test(url.pathname)
      ) {
        param = "tracking-id";
      } else {
        continue;
      }

      const values = url.searchParams.getAll(param);
      if (values.length !== 1) continue;
      const number = values[0].toUpperCase();
      if (/^(?:\d{10,22}|JJD\d{10,18}|[A-Z]{2}\d{9}[A-Z]{2})$/.test(number)) numbers.add(number);
    }
  }
  return [...numbers];
}

export function patchServer(source) {
  const index = source.indexOf(original);
  if (index < 0 || source.indexOf(original, index + original.length) >= 0) {
    throw new Error("Open Parcels DHL mail patch does not match the pinned server");
  }
  return source.replace(original, () => replacement) + "\n" + localDhlTrackingNumbers.toString();
}

registerHooks({
  load(url, context, nextLoad) {
    const result = nextLoad(url, context);
    if (url !== "file:///app/server/dist/main.js") return result;
    return { ...result, source: patchServer(Buffer.from(result.source).toString("utf8")) };
  },
});
