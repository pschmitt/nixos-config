export class OpsGenieClient {
  constructor({
    on_call_key = null,
    support_key = null,
    base_url = 'https://api.eu.opsgenie.com/v2',
    web_base_url = 'https://germanedgecloudgmbh.app.opsgenie.com',
  } = {}) {
    this.onCallKey = on_call_key;
    this.supportKey = support_key;
    this.baseUrl = (base_url || 'https://api.eu.opsgenie.com/v2').replace(/\/+$/, '');
    this.webBaseUrl = (web_base_url || 'https://germanedgecloudgmbh.app.opsgenie.com').replace(/\/+$/, '');
  }

  isConfigured() {
    return Boolean(this.onCallKey || this.supportKey);
  }

  alertUrl(alert) {
    const id = alert.id || alert.tinyId;
    return `${this.webBaseUrl}/alert/detail/${id}/details`;
  }

  async fetchQueueAlerts(key, queueName) {
    if (!key) return [];
    const url = `${this.baseUrl}/alerts?query=status%3Aopen&limit=100&sort=createdAt&order=desc`;
    const makeFetch = () =>
      fetch(url, {
        headers: {
          Authorization: `GenieKey ${key}`,
          Accept: 'application/json',
          'User-Agent': 'teams-live/1.0',
        },
        signal: AbortSignal.timeout(15_000),
      });

    let res;
    try {
      res = await makeFetch();
    } catch {
      await new Promise((r) => setTimeout(r, 1000));
      res = await makeFetch();
    }

    if (!res.ok) {
      const text = await res.text().catch(() => '');
      throw new Error(`OpsGenie HTTP ${res.status}: ${text || res.statusText}`);
    }

    const data = await res.json();
    return (data.data || []).map((alert) => ({
      ...alert,
      queue: queueName,
      url: this.alertUrl(alert),
    }));
  }

  async getAllOpenAlerts() {
    const [onCallRes, supportRes] = await Promise.allSettled([
      this.fetchQueueAlerts(this.onCallKey, 'On-Call'),
      this.fetchQueueAlerts(this.supportKey, 'Support'),
    ]);

    const onCallAlerts = onCallRes.status === 'fulfilled' ? onCallRes.value : [];
    const supportAlerts = supportRes.status === 'fulfilled' ? supportRes.value : [];
    const onCallError = onCallRes.status === 'rejected' ? onCallRes.reason.message : null;
    const supportError = supportRes.status === 'rejected' ? supportRes.reason.message : null;

    return {
      onCallAlerts,
      supportAlerts,
      onCallError,
      supportError,
    };
  }
}
