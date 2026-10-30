export class JiraClient {
  constructor({ url = '', token = '', boardId = '' } = {}) {
    this.baseUrl = (url || '').replace(/\/+$/, '');
    this.token = token || '';
    this.boardId = String(boardId || '').trim();
  }

  isConfigured() {
    return Boolean(this.baseUrl && this.token);
  }

  async request(path, { method = 'GET', body = null } = {}) {
    if (!this.baseUrl || !this.token) {
      throw new Error('Jira is not configured (missing URL or token)');
    }

    const url = `${this.baseUrl}/${path.replace(/^\/+/, '')}`;
    const headers = {
      Authorization: `Bearer ${this.token}`,
      Accept: 'application/json',
      'User-Agent': 'teams-live/1.0',
    };
    if (body) {
      headers['Content-Type'] = 'application/json';
    }

    const options = {
      method,
      headers,
      signal: AbortSignal.timeout(15_000),
    };
    if (body) {
      options.body = JSON.stringify(body);
    }

    const res = await fetch(url, options);
    if (!res.ok) {
      const errText = await res.text().catch(() => '');
      throw new Error(`Jira HTTP ${res.status}: ${errText.slice(0, 150)}`);
    }
    return await res.json();
  }

  /**
   * Retrieves open tasks in active sprint(s) that are To Do, In Progress, or In Review.
   * Does NOT leak Jira URL, board name, or board ID.
   */
  async getActiveSprintTasks() {
    const jql = 'sprint in openSprints() AND statusCategory != Done ORDER BY status ASC, updated DESC';
    const endpoint = `rest/api/2/search?jql=${encodeURIComponent(jql)}&maxResults=100&fields=summary,status,assignee`;
    const res = await this.request(endpoint);
    const issues = res.issues || [];

    const todo = [];
    const inProgress = [];
    const inReview = [];

    for (const issue of issues) {
      const statusObj = issue.fields?.status || {};
      const statusName = statusObj.name || '';
      const categoryKey = statusObj.statusCategory?.key || '';
      const assigneeObj = issue.fields?.assignee;
      const assigneeName = assigneeObj?.displayName || 'Unassigned';
      const summary = issue.fields?.summary || '';

      const item = {
        key: issue.key,
        summary,
        assignee: assigneeName,
        status: statusName,
      };

      if (statusName.toLowerCase() === 'in review' || statusName.toLowerCase().includes('review')) {
        inReview.push(item);
      } else if (categoryKey === 'indeterminate' || statusName.toLowerCase().includes('progress')) {
        inProgress.push(item);
      } else {
        todo.push(item);
      }
    }

    return {
      total: issues.length,
      todo,
      inProgress,
      inReview,
    };
  }
}
