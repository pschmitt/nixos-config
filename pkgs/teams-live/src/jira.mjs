export class JiraClient {
  constructor({ url = '', token = '', boardId = '', project = 'CKS' } = {}) {
    this.baseUrl = (url || '').replace(/\/+$/, '');
    this.token = token || '';
    this.boardId = String(boardId || '').trim();
    this.project = String(project || 'CKS').trim();
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
   * Retrieves single issue details.
   */
  async getIssue(issueKey) {
    const key = String(issueKey || '').trim().toUpperCase();
    if (!key) throw new Error('Issue key is required');
    const endpoint = `rest/api/2/issue/${encodeURIComponent(key)}?fields=summary,status,assignee,priority,issuetype`;
    const res = await this.request(endpoint);
    const fields = res.fields || {};
    return {
      key: res.key,
      summary: fields.summary || '(No summary)',
      status: fields.status?.name || 'Unknown',
      statusCategory: fields.status?.statusCategory?.key || '',
      assignee: fields.assignee?.displayName || 'Unassigned',
      priority: fields.priority?.name || 'None',
      issueType: fields.issuetype?.name || 'Task',
      url: this.baseUrl ? `${this.baseUrl}/browse/${res.key}` : '',
    };
  }

  /**
   * Retrieves open tasks in active sprint(s) that are To Do, In Progress, or In Review.
   * Does NOT leak Jira URL, board name, or board ID.
   */
  async getActiveSprintTasks() {
    const jql = `project = ${this.project} AND sprint in openSprints() AND statusCategory != Done ORDER BY status ASC, updated DESC`;
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
        url: this.baseUrl ? `${this.baseUrl}/browse/${issue.key}` : '',
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
